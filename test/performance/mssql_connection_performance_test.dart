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
      final server =
          Platform.environment['MSSQL_SERVER'] ?? '192.168.1.10:1433';
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
