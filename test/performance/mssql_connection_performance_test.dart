import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:mssql_connection/mssql_connection.dart';
import 'package:test/test.dart';

import '../test_utils.dart';

/// Performance benchmarks for MssqlConnection.
///
/// Notes:
/// - Defaults to increasing sizes: 1M, 5M, 10M (override via PERF_SIZES).
/// - These are heavy, long-running tests meant for local benchmarking. Tag or
///   filter them in CI if needed.
/// - Ensure your SQL Server has sufficient resources and the login has rights
///   to create/drop databases and tables.
void main() {
  final sizes = _readPerfSizes();

  group('Performance: Connection lifecycle', () {
    late String ip, port, db, user, pass;

    setUp(() {
      final server = Platform.environment['MSSQL_SERVER'] ?? '192.168.1.4:1433';
      user = Platform.environment['MSSQL_USER'] ?? 'sa';
      pass =
          Platform.environment['MSSQL_PASS'] ??
          Platform.environment['MSSQL_PASSWORD'] ??
          'eSeal@123';
      final parts = server.split(':');
      ip = parts.isNotEmpty ? parts.first : '127.0.0.1';
      port = parts.length > 1 ? parts[1] : '1433';
      db = 'master';
    });

    test('connect() and disconnect() timing', () async {
      final conn = MssqlConnection.getInstance();

      // Connect
      final rssBefore = _rssMB();
      final swConnect = Stopwatch()..start();
      final ok = await conn.connect(
        ip: ip,
        port: port,
        databaseName: db,
        username: user,
        password: pass,
        timeoutInSeconds: 15,
      );
      swConnect.stop();
      expect(ok, isTrue, reason: 'Failed to connect');

      // Disconnect
      final swDisconnect = Stopwatch()..start();
      final discOk = await conn.disconnect();
      swDisconnect.stop();
      expect(discOk, isTrue);

      final rssAfter = _rssMB();

      _printLine(
        '[Connect] Established in ${_fmtMs(swConnect.elapsedMilliseconds)} ms',
      );
      _printLine(
        '[Disconnect] Closed in ${_fmtMs(swDisconnect.elapsedMilliseconds)} ms',
      );
      _printLine(
        '[Memory] RSS start=${rssBefore.toStringAsFixed(1)} MB, end=${rssAfter.toStringAsFixed(1)} MB, delta=${(rssAfter - rssBefore).toStringAsFixed(1)} MB',
      );
    });
  });

  group('Performance: Operations (DDL, DML, Params, Bulk, Query)', () {
    final db = TempDbHarness();

    setUpAll(() async {
      await db.init();
    });

    tearDownAll(() async {
      await db.dispose();
    });

    test('DDL: CREATE TABLE and ALTER TABLE timing', () async {
      final table = 'dbo.[PerfDDL_${DateTime.now().millisecondsSinceEpoch}]';
      final rssBefore = _rssMB();
      final sw = Stopwatch()..start();
      await db.execute('CREATE TABLE $table (id INT NOT NULL PRIMARY KEY)');
      await db.execute('ALTER TABLE $table ADD name NVARCHAR(100) NULL');
      await db.execute('DROP TABLE $table');
      sw.stop();
      final rssAfter = _rssMB();
      _printLine(
        '[DDL] CREATE/ALTER/DROP completed in ${_fmtMs(sw.elapsedMilliseconds)} ms, RSS delta ${(rssAfter - rssBefore).toStringAsFixed(1)} MB',
      );
    });

    for (final n in sizes) {
      test(
        'DML: INSERT/UPDATE/DELETE $n rows (batched multi-values)',
        () async {
          final table =
              'dbo.[PerfDML_${DateTime.now().millisecondsSinceEpoch}]';
          await db.recreateTable(
            'CREATE TABLE $table (id INT NOT NULL PRIMARY KEY, flag BIT NOT NULL, note NVARCHAR(100) NULL)',
          );

          // Batched INSERT using multi-values to avoid 1M single-row statements.
          final batchSize = 1000; // rows per INSERT
          final batches = (n / batchSize).ceil();
          var inserted = 0;
          // Use a single transaction to minimize log flushes and round-trips
          await db.execute('BEGIN TRAN');
          final ins = Stopwatch()..start();
          for (var b = 0; b < batches; b++) {
            final startId = b * batchSize + 1;
            final endId = min((b + 1) * batchSize, n);
            final values = StringBuffer();
            for (var id = startId; id <= endId; id++) {
              if (values.isNotEmpty) values.write(',');
              values.write('($id, ${id % 2}, N\'note_$id\')');
            }
            await db.execute(
              'INSERT INTO $table (id, flag, note) VALUES ${values.toString()}',
            );
            inserted += (endId - startId + 1);
          }
          ins.stop();
          await db.execute('COMMIT');
          expect(inserted, n);

          final upd = Stopwatch()..start();
          await db.execute(
            'UPDATE $table SET flag = CASE WHEN flag = 0 THEN 1 ELSE 0 END',
          );
          upd.stop();

          final del = Stopwatch()..start();
          await db.execute('DELETE FROM $table');
          del.stop();

          _printBench(op: 'DML INSERT', rows: n, ms: ins.elapsedMilliseconds);
          _printBench(op: 'DML UPDATE', rows: n, ms: upd.elapsedMilliseconds);
          _printBench(op: 'DML DELETE', rows: n, ms: del.elapsedMilliseconds);
        },
        timeout: Timeout(Duration(days: 1)),
      );
    }

    for (final n in sizes) {
      test(
        'Parameterized inserts: $n rows (executeParams)',
        () async {
          final table =
              'dbo.[PerfParams_${DateTime.now().millisecondsSinceEpoch}]';
          await db.recreateTable(
            'CREATE TABLE $table (id INT NOT NULL PRIMARY KEY, payload NVARCHAR(100) NOT NULL)',
          );

          // Per-row RPCs (slower). Use a single transaction and NOCOUNT to mitigate overhead.
          const batch = 1000; // per-batch stats
          final batches = (n / batch).ceil();
          final latencies = <int>[]; // ms per batch
          var totalInserted = 0;
          await db.execute('BEGIN TRAN; SET NOCOUNT ON;');
          final total = Stopwatch()..start();
          for (var b = 0; b < batches; b++) {
            final startId = b * batch + 1;
            final endId = min((b + 1) * batch, n);
            final sw = Stopwatch()..start();
            for (var id = startId; id <= endId; id++) {
              await db.executeParams(
                'INSERT INTO $table (id, payload) VALUES (@id, @p)',
                {'@id': id, '@p': 'x' * 20},
              );
            }
            sw.stop();
            latencies.add(sw.elapsedMilliseconds);
            totalInserted += (endId - startId + 1);
          }
          total.stop();
          await db.execute('COMMIT');
          expect(totalInserted, n);

          final avgBatchMs = latencies.isEmpty
              ? 0
              : (latencies.reduce((a, b) => a + b) / latencies.length).round();
          _printBench(
            op: 'Params INSERT',
            rows: n,
            ms: total.elapsedMilliseconds,
            extra: 'avg batch ${_fmtMs(avgBatchMs)} ms',
          );
        },
        timeout: Timeout(Duration(days: 1)),
      );
    }

    for (final n in sizes) {
      test('Bulk insert: $n rows (batched)', () async {
        final table = 'dbo.[PerfBulk_${DateTime.now().millisecondsSinceEpoch}]';
        await db.recreateTable(
          'CREATE TABLE $table (id INT NOT NULL PRIMARY KEY, flag BIT NOT NULL, note NVARCHAR(100) NULL)',
        );

        final chunk = 10000; // generate this many rows per client->server call
        final chunks = (n / chunk).ceil();
        final latencies = <int>[];
        var totalInserted = 0;

        final rssBefore = _rssMB();
        final total = Stopwatch()..start();
        for (var c = 0; c < chunks; c++) {
          final startId = c * chunk + 1;
          final endId = min((c + 1) * chunk, n);
          final rows = <Map<String, dynamic>>[];
          rows.reserve(endId - startId + 1); // hint for growable list
          for (var id = startId; id <= endId; id++) {
            rows.add({'id': id, 'flag': id % 2 == 0, 'note': 'note_$id'});
          }
          final sw = Stopwatch()..start();
          final inserted = await db.client.bulkInsert(
            table,
            rows,
            batchSize: 2000,
          );
          sw.stop();
          latencies.add(sw.elapsedMilliseconds);
          totalInserted += inserted;
        }
        total.stop();
        final rssAfter = _rssMB();

        expect(totalInserted, n);
        final avgBatchMs = latencies.isEmpty
            ? 0
            : (latencies.reduce((a, b) => a + b) / latencies.length).round();
        _printBench(
          op: 'Bulk Insert',
          rows: n,
          ms: total.elapsedMilliseconds,
          extra:
              'avg chunk ${_fmtMs(avgBatchMs)} ms, RSS +${(rssAfter - rssBefore).toStringAsFixed(1)} MB',
        );
      }, timeout: Timeout(Duration(days: 1)));
    }

    for (final n in sizes) {
      test(
        'Query and retrieve $n rows (JSON encode included)',
        () async {
          final table =
              'dbo.[PerfQuery_${DateTime.now().millisecondsSinceEpoch}]';
          await db.recreateTable(
            'CREATE TABLE $table (id INT NOT NULL PRIMARY KEY, payload NVARCHAR(50) NOT NULL)',
          );

          // Fill table using a set-based INSERT for speed (data prep only).
          // Consider using a numbers/tally table for 10M+ on your server.
          await db.execute('''
DECLARE @N BIGINT = $n;
;WITH N AS (
  SELECT 1 AS i
  UNION ALL
  SELECT i + 1 FROM N WHERE i < @N
)
INSERT INTO $table (id, payload)
SELECT i, REPLICATE(N'X', 20) FROM N OPTION (MAXRECURSION 0);
''');

          // Measure getData (includes JSON encoding in native side/API contract)
          final rssBefore = _rssMB();
          final sw = Stopwatch()..start();
          final jsonStr = await db.query(
            'SELECT id, payload FROM $table ORDER BY id',
          );
          sw.stop();
          final rssMid = _rssMB();

          // Force iteration of all rows on the Dart side to ensure full materialization.
          final rows = parseRows(jsonStr);
          int checked = 0;
          for (final _ in rows) {
            checked++;
          }
          expect(checked, n);
          final rssAfter = _rssMB();

          _printBench(
            op: 'Query',
            rows: n,
            ms: sw.elapsedMilliseconds,
            extra:
                'RSS +${(rssMid - rssBefore).toStringAsFixed(1)} MB (on fetch), +${(rssAfter - rssBefore).toStringAsFixed(1)} MB (after parse)',
          );
        },
        timeout: Timeout(Duration(days: 1)),
      );
    }
  });

  // ---------------------------------------------------------------------------
  // Speed tests: focused on specific operations with assertion-based thresholds
  // ---------------------------------------------------------------------------

  group('Performance: Speed assertions (small-scale)', () {
    final db = TempDbHarness();

    setUpAll(() async => db.init());
    tearDownAll(() async => db.dispose());

    // -- writeBatch throughput -------------------------------------------------
    test(
      'writeBatch: 500 statements in one transaction < 10s',
      () async {
        await db.ensureConnected();
        await db.recreateTable(
          'CREATE TABLE dbo.SpeedBatch (id INT NOT NULL PRIMARY KEY, v NVARCHAR(50))',
        );

        final stmts = List.generate(
          500,
          (i) =>
              "INSERT INTO dbo.SpeedBatch VALUES (${i + 1}, N'val_${i + 1}')",
        );

        final sw = Stopwatch()..start();
        final results = await db.client.writeBatch(stmts);
        sw.stop();

        expect(results, hasLength(500));
        _printBench(
          op: 'writeBatch-500',
          rows: 500,
          ms: sw.elapsedMilliseconds,
        );
        expect(
          sw.elapsedMilliseconds,
          lessThan(10000),
          reason: '500 batched writes should complete in < 10 s',
        );
      },
      timeout: Timeout(Duration(seconds: 30)),
    );

    // -- BCP vs single-row INSERT comparison -----------------------------------
    test(
      'BCP vs single-row INSERT: 10,000 rows speed comparison',
      () async {
        await db.ensureConnected();
        final ts = DateTime.now().millisecondsSinceEpoch;
        await db.recreateTable(
          'CREATE TABLE dbo.SpeedBcp_$ts (id INT NOT NULL PRIMARY KEY, val NVARCHAR(50))',
        );
        await db.recreateTable(
          'CREATE TABLE dbo.SpeedSingle_$ts (id INT NOT NULL PRIMARY KEY, val NVARCHAR(50))',
        );

        const n = 10000;
        final rows = List.generate(
          n,
          (i) => {'id': i + 1, 'val': 'v_${i + 1}'},
        );

        // BCP path
        final swBcp = Stopwatch()..start();
        final inserted = await db.client.bulkInsert(
          'dbo.SpeedBcp_$ts',
          rows,
          batchSize: 2000,
        );
        swBcp.stop();
        expect(inserted, n);

        // Single-row parameterized INSERT path (baseline)
        final swSingle = Stopwatch()..start();
        await db.execute('BEGIN TRAN');
        for (var i = 0; i < n; i++) {
          await db.executeParams(
            'INSERT INTO dbo.SpeedSingle_$ts (id, val) VALUES (@id, @val)',
            {'@id': i + 1, '@val': 'v_${i + 1}'},
          );
        }
        await db.execute('COMMIT');
        swSingle.stop();

        _printBench(op: 'BCP-10k', rows: n, ms: swBcp.elapsedMilliseconds);
        _printBench(
          op: 'SingleRPC-10k',
          rows: n,
          ms: swSingle.elapsedMilliseconds,
        );
        _printLine(
          '[BCP vs Single] ratio = ${(swSingle.elapsedMilliseconds / (swBcp.elapsedMilliseconds == 0 ? 1 : swBcp.elapsedMilliseconds)).toStringAsFixed(1)}x faster with BCP',
        );
        expect(
          swBcp.elapsedMilliseconds,
          lessThan(swSingle.elapsedMilliseconds),
          reason: 'BCP should be faster than per-row parameterized INSERT',
        );
      },
      timeout: Timeout(Duration(minutes: 5)),
    );

    // -- getData throughput (100k rows) ----------------------------------------
    test(
      'getData: 100,000 rows fetched and JSON-decoded < 30s',
      () async {
        await db.ensureConnected();
        await db.recreateTable(
          'CREATE TABLE dbo.SpeedQuery (id INT NOT NULL PRIMARY KEY, val NVARCHAR(50))',
        );

        const n = 100000;
        // Seed with set-based insert
        await db.execute('''
DECLARE @N INT = $n;
;WITH Nums AS (SELECT 1 AS i UNION ALL SELECT i+1 FROM Nums WHERE i < @N)
INSERT INTO dbo.SpeedQuery (id, val)
SELECT i, REPLICATE(N'X', 20) FROM Nums OPTION (MAXRECURSION 0);
''');

        final sw = Stopwatch()..start();
        final jsonStr = await db.query(
          'SELECT id, val FROM dbo.SpeedQuery ORDER BY id',
        );
        sw.stop();

        final parsed = parseRows(jsonStr);
        expect(parsed.length, n);
        _printBench(op: 'getData-100k', rows: n, ms: sw.elapsedMilliseconds);
        expect(
          sw.elapsedMilliseconds,
          lessThan(30000),
          reason: '100k rows getData should complete in < 30 s',
        );
      },
      timeout: Timeout(Duration(seconds: 60)),
    );

    // -- getDataWithParams latency (per-query overhead) -------------------------
    test(
      'getDataWithParams: 1,000 parameterized SELECTs < 20s',
      () async {
        await db.ensureConnected();
        await db.recreateTable(
          'CREATE TABLE dbo.SpeedParams (id INT NOT NULL PRIMARY KEY, val NVARCHAR(50))',
        );
        const n = 1000;
        // Seed rows
        await db.execute('''
DECLARE @N INT = $n;
;WITH Nums AS (SELECT 1 AS i UNION ALL SELECT i+1 FROM Nums WHERE i < @N)
INSERT INTO dbo.SpeedParams (id, val)
SELECT i, N'seed' FROM Nums OPTION (MAXRECURSION 0);
''');

        final sw = Stopwatch()..start();
        for (var i = 1; i <= n; i++) {
          final r = await db.executeParams(
            'SELECT id, val FROM dbo.SpeedParams WHERE id = @id',
            {'@id': i},
          );
          final map = jsonDecode(r) as Map<String, dynamic>;
          expect((map['rows'] as List).isNotEmpty, isTrue);
        }
        sw.stop();
        _printBench(
          op: 'getDataWithParams-1k-SELECTs',
          rows: n,
          ms: sw.elapsedMilliseconds,
        );
        expect(
          sw.elapsedMilliseconds,
          lessThan(20000),
          reason: '1,000 parameterized SELECTs should complete in < 20 s',
        );
      },
      timeout: Timeout(Duration(seconds: 60)),
    );

    // -- Mixed-type BCP (int, float, bit, nvarchar, datetime) ------------------
    test(
      'BCP mixed-type: 50,000 rows with diverse column types < 15s',
      () async {
        await db.ensureConnected();
        final ts = DateTime.now().millisecondsSinceEpoch;
        await db.recreateTable('''
CREATE TABLE dbo.SpeedMixed_$ts (
  id       INT NOT NULL PRIMARY KEY,
  score    FLOAT NOT NULL,
  active   BIT NOT NULL,
  label    NVARCHAR(100) NOT NULL,
  created  NVARCHAR(50) NOT NULL
)''');

        const n = 50000;
        final now = DateTime.now();
        final rows = List.generate(
          n,
          (i) => {
            'id': i + 1,
            'score': (i + 1) * 1.5,
            'active': i % 2 == 0,
            'label': 'row_label_${i + 1}',
            'created': _formatDt(now),
          },
        );

        final sw = Stopwatch()..start();
        final inserted = await db.client.bulkInsert(
          'dbo.SpeedMixed_$ts',
          rows,
          batchSize: 5000,
        );
        sw.stop();

        expect(inserted, n);
        _printBench(op: 'BCP-mixed-50k', rows: n, ms: sw.elapsedMilliseconds);
        expect(
          sw.elapsedMilliseconds,
          lessThan(15000),
          reason: '50k mixed-type BCP should complete in < 15 s',
        );
      },
      timeout: Timeout(Duration(seconds: 60)),
    );

    // -- getRows convenience API -----------------------------------------------
    test(
      'getRows: returns parsed List directly for 10,000 rows',
      () async {
        await db.ensureConnected();
        await db.recreateTable(
          'CREATE TABLE dbo.SpeedGetRows (id INT NOT NULL PRIMARY KEY)',
        );
        const n = 10000;
        await db.execute('''
DECLARE @N INT = $n;
;WITH Nums AS (SELECT 1 AS i UNION ALL SELECT i+1 FROM Nums WHERE i < @N)
INSERT INTO dbo.SpeedGetRows (id) SELECT i FROM Nums OPTION (MAXRECURSION 0);
''');

        final sw = Stopwatch()..start();
        final rows = await db.client.getRows('SELECT id FROM dbo.SpeedGetRows');
        sw.stop();

        expect(rows.length, n);
        _printBench(op: 'getRows-10k', rows: n, ms: sw.elapsedMilliseconds);
      },
      timeout: Timeout(Duration(seconds: 30)),
    );

    // -- Connection reconnect latency ------------------------------------------
    test(
      'reconnect after disconnect completes < 2s',
      () async {
        await db.ensureConnected();
        final conn = db.client;

        await conn.disconnect();
        expect(conn.isConnected, isFalse);

        final sw = Stopwatch()..start();
        // Force reconnect by calling getData (triggers _ensureConnectedOrReconnect)
        final server =
            Platform.environment['MSSQL_SERVER'] ?? '192.168.1.4:1433';
        final parts = server.split(':');
        final ip = parts.isNotEmpty ? parts.first : '127.0.0.1';
        final port = parts.length > 1 ? parts[1] : '1433';
        final ok = await conn.connect(
          ip: ip,
          port: port,
          databaseName: db.dbName,
          username: Platform.environment['MSSQL_USER'] ?? 'sa',
          password:
              Platform.environment['MSSQL_PASS'] ??
              Platform.environment['MSSQL_PASSWORD'] ??
              'eSeal@123',
        );
        sw.stop();
        expect(ok, isTrue);
        _printLine(
          '[Reconnect] completed in ${_fmtMs(sw.elapsedMilliseconds)} ms',
        );
        expect(
          sw.elapsedMilliseconds,
          lessThan(2000),
          reason: 'Reconnect to LAN SQL Server should be < 2 s',
        );
      },
      timeout: Timeout(Duration(seconds: 10)),
    );
  });

  // ---------------------------------------------------------------------------
  // Speed tests: 1M row focused benchmarks
  // ---------------------------------------------------------------------------

  group('Performance: 1M row speed benchmarks', () {
    final db = TempDbHarness();

    setUpAll(() async => db.init());
    tearDownAll(() async => db.dispose());

    test(
      'BCP bulk insert: 1,000,000 rows < 120s',
      () async {
        await db.ensureConnected();
        await db.recreateTable(
          'CREATE TABLE dbo.PerfSpeed1M (id INT NOT NULL PRIMARY KEY, flag BIT NOT NULL, note NVARCHAR(50) NULL)',
        );

        const n = 1000000;
        const chunkSize = 50000;
        var total = 0;
        final sw = Stopwatch()..start();
        for (var start = 1; start <= n; start += chunkSize) {
          final end = min(start + chunkSize - 1, n);
          final chunk = List.generate(
            end - start + 1,
            (i) => {
              'id': start + i,
              'flag': (start + i) % 2 == 0,
              'note': 'n${start + i}',
            },
          );
          total += await db.client.bulkInsert(
            'dbo.PerfSpeed1M',
            chunk,
            batchSize: 10000,
          );
        }
        sw.stop();
        expect(total, n);
        _printBench(op: 'BCP-1M', rows: n, ms: sw.elapsedMilliseconds);
        expect(
          sw.elapsedMilliseconds,
          lessThan(120000),
          reason: '1M row BCP should complete in < 120 s',
        );
      },
      timeout: Timeout(Duration(minutes: 5)),
    );

    test(
      'getData: read back 1,000,000 rows < 120s',
      () async {
        await db.ensureConnected();
        // Uses the table populated by the insert test above (same harness/db)
        final sw = Stopwatch()..start();
        final json = await db.query(
          'SELECT id, flag, note FROM dbo.PerfSpeed1M',
        );
        sw.stop();

        final rows = parseRows(json);
        expect(rows.length, 1000000);
        _printBench(
          op: 'getData-1M',
          rows: rows.length,
          ms: sw.elapsedMilliseconds,
        );
        expect(
          sw.elapsedMilliseconds,
          lessThan(120000),
          reason: '1M row getData should complete in < 120 s',
        );
      },
      timeout: Timeout(Duration(minutes: 5)),
    );
  });
}

// ---------------------------------------------------------------------------
// Shared format helper for DateTime -> SQL-compatible string
// ---------------------------------------------------------------------------
String _formatDt(DateTime dt) {
  final d = dt.toUtc();
  String two(int n) => n < 10 ? '0$n' : '$n';
  return '${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)}'
      'T${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
}

// ---------- Helpers ----------

List<int> _readPerfSizes() {
  final env = Platform.environment['PERF_SIZES'];
  if (env == null || env.trim().isEmpty) {
    // Default to increasing sizes suitable for stress testing.
    // Override via PERF_SIZES, e.g. "100000,1000000" for lighter runs.
    return [1000000, 5000000, 10000000];
  }
  return env
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .map((s) => int.parse(s.replaceAll('_', '').replaceAll(',', '')))
      .toList();
}

void _printBench({
  required String op,
  required int rows,
  required int ms,
  String? extra,
}) {
  final perSec = ms > 0 ? (rows / (ms / 1000)).round() : 0;
  final msg =
      '[$op] ${_fmtInt(rows)} rows in ${_fmtMs(ms)} ms → ${_fmtInt(perSec)} rows/sec'
      '${extra != null && extra.isNotEmpty ? ' | $extra' : ''}';
  _printLine(msg);
}

void _printLine(String s) {
  // Keep output readable and copy-paste friendly.
  // Example:
  // [Bulk Insert] 1,000,000 rows inserted in 12,450 ms → 80,321 rows/sec
  // Using a plain print keeps results visible in test output.
  // ignore: avoid_print
  print(s);
}

String _fmtInt(int v) {
  final s = v.toString();
  final buf = StringBuffer();
  var count = 0;
  for (var i = s.length - 1; i >= 0; i--) {
    buf.write(s[i]);
    count++;
    if (count == 3 && i != 0) {
      buf.write(',');
      count = 0;
    }
  }
  return buf.toString().split('').reversed.join();
}

String _fmtMs(int ms) => _fmtInt(ms);

double _rssMB() {
  try {
    final bytes = ProcessInfo.currentRss;
    return bytes / (1024 * 1024);
  } catch (_) {
    return double.nan; // Not available on some platforms
  }
}

// Lightweight reserve extension to reduce re-allocations for large bulk lists.
extension on List<Map<String, dynamic>> {
  // Capacity hint; Dart lists don't expose capacity so this is a no-op.
  void reserve(int additional) {}
}

/*
Extending/Running:
- Increase sizes via env, e.g. on PowerShell:
  $env:PERF_SIZES = "1000000,5000000,10000000"; dart test .\test\performance\mssql_connection_performance_test.dart

- To focus on one benchmark, use `-n` to filter by test name.

- Consider tagging these tests with a custom tag and excluding from CI, or
  configure CI runners with ample resources and MSSQL access.

- For even larger loads, raise batch/chunk sizes judiciously to balance client
  memory and server throughput. Monitor ProcessInfo.currentRss.
*/
