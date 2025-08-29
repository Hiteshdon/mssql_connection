import 'dart:io';

import 'package:mssql_connection/mssql_connection.dart';
import 'package:mssql_connection/src/mssql_client.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

// Set RUN_DB_TESTS=1 in environment to enable tests that require a live DB + native libs.
final bool _runDbTests = true;

void main() {
  print(_runDbTests);
  group('Negative cases - connection', () {
    test('connect fails with wrong credentials (low timeout)', () async {
      final server = Platform.environment['MSSQL_SERVER'] ?? '127.0.0.1:1433';
      final parts = server.split(':');
      final ip = parts.isNotEmpty ? parts.first : '127.0.0.1';
      final port = parts.length > 1 ? parts[1] : '1433';

      // Use low-level client to avoid mutating the public singleton state
      final client = MssqlClient(
        server: '$ip:$port',
        username: 'sa',
        password: 'definitely-wrong',
      );
      if (!_runDbTests) return; // offline skip
      final ok = await client.connect(loginTimeoutSeconds: 2);
      expect(ok, isFalse);
    });

    test('connect fails to unreachable port quickly', () async {
      // Use a likely-closed port
      final client = MssqlClient(
        server: '127.0.0.1:1',
        username: 'sa',
        password: 'x',
      );
      if (!_runDbTests) return;
      final ok = await client.connect(loginTimeoutSeconds: 2);
      expect(ok, isFalse);
    });
  });

  group('Negative cases - SQL execution (syntax/semantics)', () {
    final harness = TempDbHarness();

    setUpAll(() async {
      if (!_runDbTests) return;
      await harness.init();
      await harness.recreateTable('''
        CREATE TABLE dbo.NegItems (
          id INT NOT NULL PRIMARY KEY,
          name NVARCHAR(50) NULL
        )
      ''');
    });

    tearDownAll(() async {
      if (!_runDbTests) return;
      await harness.dispose();
    });

    test('invalid SQL syntax throws SQLException (writeData)', () async {
      if (!_runDbTests) return;
      await expectLater(
        harness.execute('SELEC 1'),
        throwsA(isA<SQLException>()),
      );
    });

    test('invalid SQL syntax throws SQLException (getData)', () async {
      if (!_runDbTests) return;
      await expectLater(
        harness.query('SELET * FROM dbo.NegItems'),
        throwsA(isA<SQLException>()),
      );
    });

    test(
      'missing parameter in executeParams returns error or throws',
      () async {
        if (!_runDbTests) return;
        try {
          final out = await harness.executeParams('SELECT @missingParam', {});
          final m = parseJson(out);
          expect(m.containsKey('error') || (m['rows'] as List).isEmpty, isTrue);
        } on SQLException {
          // acceptable: some providers surface this as an exception
        }
      },
    );

    test('type overflow via params surfaces error', () async {
      if (!_runDbTests) return;
      // INT column can't store > INT32 max
      final tooBig = 9223372036854775807; // fits bigint, not int
      try {
        await harness.executeParams(
          'INSERT INTO dbo.NegItems (id, name) VALUES (@id, @name)',
          {'id': tooBig, 'name': 'x'},
        );
        fail('Expected an error due to int overflow');
      } catch (e) {
        expect(e, isA<SQLException>());
      }
    });

    test('bulkInsert into non-existent table throws', () async {
      if (!_runDbTests) return;
      final conn = harness.client;
      final rows = [
        {'id': 1, 'name': 'a'},
        {'id': 2, 'name': 'b'},
      ];
      await expectLater(
        conn.bulkInsert('dbo.NoSuchTable', rows),
        throwsA(isA<SQLException>()),
      );
    });

    test('transaction rollback after error leaves table empty', () async {
      if (!_runDbTests) return;
      final c = harness.client;
      await c.beginTransaction();
      try {
        // wrong column name triggers error
        await harness.execute(
          "INSERT INTO dbo.NegItems (id, wrong_name) VALUES (1, N'x')",
        );
        fail('expected SQLException');
      } catch (_) {
        await c.rollback();
      }
      final rows = parseRows(await harness.query('SELECT * FROM dbo.NegItems'));
      expect(rows, isEmpty);
    });
  });

  group('Edge-case regression', () {
    final harness = TempDbHarness();

    setUpAll(() async {
      if (!_runDbTests) return;
      await harness.init();
      await harness.recreateTable('''
        CREATE TABLE dbo.Texts (
          k INT PRIMARY KEY,
          v NVARCHAR(200) NULL
        )
      ''');
    });

    tearDownAll(() async {
      if (!_runDbTests) return;
      await harness.dispose();
    });

    test(
      'NVARCHAR parameters with non-ASCII characters are handled correctly',
      () async {
        if (!_runDbTests) return;
        final unicode = 'こんにちは世界 👋';
        final affected = affectedCount(
          await harness.executeParams(
            'INSERT INTO dbo.Texts (k, v) VALUES (@k, @v)',
            {'k': 1, 'v': unicode},
          ),
        );
        expect(affected, 1);

        final rows = parseRows(
          await harness.executeParams('SELECT v FROM dbo.Texts WHERE k=@k', {
            'k': 1,
          }),
        );
        expect(rows.first['v'], unicode);
      },
    );
  });

  group('Offline API negative behavior (no DB)', () {
    test(
      'getData without connect throws StateError when no saved params',
      () async {
        final c = MssqlConnection.getInstance();
        // Ensure disconnected
        await c.disconnect();
        await expectLater(c.getData('SELECT 1'), throwsA(isA<StateError>()));
      },
    );

    test('writeDataWithParams without connect throws StateError', () async {
      final c = MssqlConnection.getInstance();
      await c.disconnect();
      await expectLater(
        c.writeDataWithParams('SELECT @p', {'p': 1}),
        throwsA(isA<StateError>()),
      );
    });
  });
}
