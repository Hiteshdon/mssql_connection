import 'dart:io';
import 'dart:typed_data';

import 'package:mssql_connection/mssql_connection.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  group('MssqlConnection API', () {
    late MssqlConnection conn;
    late String server;
    late String username;
    late String password;
    late String ip;
    late String port;
    late String dbName;

    setUpAll(() async {
      // Read connection info from env with sensible fallbacks
      server = Platform.environment['MSSQL_SERVER'] ?? '192.168.1.10:1433';
      username = Platform.environment['MSSQL_USER'] ?? 'sa';
      password =
          Platform.environment['MSSQL_PASS'] ??
          Platform.environment['MSSQL_PASSWORD'] ??
          'eSeal@123';
      final parts = server.split(':');
      ip = parts.isNotEmpty ? parts.first : '127.0.0.1';
      port = parts.length > 1 ? parts[1] : '1433';

      // Use MssqlConnection exclusively: connect to master, create temp DB, switch to it
      conn = MssqlConnection.getInstance();
      final okMaster = await conn.connect(
        ip: ip,
        port: port,
        databaseName: 'master',
        username: username,
        password: password,
      );
      if (!okMaster) {
        throw StateError('Failed to connect to $server as $username');
      }

      dbName = 'ConnAPI_${DateTime.now().millisecondsSinceEpoch}';
      await conn.writeData('CREATE DATABASE [$dbName]');
      await conn.writeData('USE [$dbName]');

      expect(conn.isConnected, isTrue);
    });

    tearDownAll(() async {
      // Drop temp DB using the same MssqlConnection
      try {
        if (!conn.isConnected) {
          // Reconnect to master if needed
          final ok = await conn.connect(
            ip: ip,
            port: port,
            databaseName: 'master',
            username: username,
            password: password,
          );
          if (!ok) return; // best effort
        }
        await conn.writeData('USE master');
        await conn.writeData(
          'ALTER DATABASE [$dbName] SET SINGLE_USER WITH ROLLBACK IMMEDIATE',
        );
        await conn.writeData('DROP DATABASE [$dbName]');
      } catch (_) {
        // ignore cleanup failures
      } finally {
        await conn.disconnect();
      }
    });

    test('getData and writeData basic DDL/DML', () async {
      await conn.writeData(
        'CREATE TABLE dbo.T (id INT PRIMARY KEY, name NVARCHAR(50))',
      );
      await conn.writeData(
        "INSERT INTO dbo.T (id, name) VALUES (1, N'Alice'), (2, N'Bob')",
      );
      final rows = parseRows(
        await conn.getData('SELECT COUNT(*) AS cnt FROM dbo.T'),
      );
      expect(rows.first['cnt'], 2);
    });

    test('getDataWithParams and writeDataWithParams', () async {
      await conn.writeData(
        'CREATE TABLE dbo.P (id INT PRIMARY KEY, val VARBINARY(MAX))',
      );
      final ok = await conn.writeDataWithParams(
        'INSERT INTO dbo.P (id, val) VALUES (@id, @val)',
        {
          '@id': 10,
          '@val': Uint8List.fromList([1, 2, 3, 4]),
        },
      );
      expect(affectedCount(ok) >= 1, true);

      final out = await conn.getDataWithParams(
        'SELECT id, DATALENGTH(val) AS len FROM dbo.P WHERE id=@id',
        {'@id': 10},
      );
      final rows = parseRows(out);
      expect(rows.length, 1);
      expect(rows.first['len'], 4);
    });

    test('bulkInsert inserts multiple rows', () async {
      await conn.writeData(
        'CREATE TABLE dbo.Bulk (id INT NOT NULL, flag BIT NOT NULL, note NVARCHAR(100) NULL)',
      );
      final rows = [
        {'id': 1, 'flag': true, 'note': 'a'},
        {'id': 2, 'flag': false, 'note': 'b'},
        {'id': 3, 'flag': true, 'note': 'c'},
      ];
      final inserted = await conn.bulkInsert('dbo.Bulk', rows, batchSize: 2);
      expect(inserted, rows.length);
      final out = parseRows(
        await conn.getData('SELECT COUNT(*) AS cnt FROM dbo.Bulk'),
      );
      expect(out.first['cnt'], rows.length);
    });

    test('transaction helpers begin/commit', () async {
      await conn.writeData('CREATE TABLE dbo.Tx (id INT PRIMARY KEY)');
      await conn.beginTransaction();
      await conn.writeData('INSERT INTO dbo.Tx (id) VALUES (1)');
      await conn.commit();
      final rows = parseRows(
        await conn.getData('SELECT COUNT(*) AS cnt FROM dbo.Tx WHERE id=1'),
      );
      expect(rows.first['cnt'], 1);
    });

    test('transaction helpers begin/rollback', () async {
      await conn.beginTransaction();
      await conn.writeData('INSERT INTO dbo.Tx (id) VALUES (2)');
      await conn.rollback();
      final rows = parseRows(
        await conn.getData('SELECT COUNT(*) AS cnt FROM dbo.Tx WHERE id=2'),
      );
      expect(rows.first['cnt'], 0);
    });

    test('disconnect returns to not connected state', () async {
      final ok = await conn.disconnect();
      expect(ok, isTrue);
      expect(conn.isConnected, isFalse);

      // Reconnect implicitly through data call should succeed via cached creds
      final res = await conn.getData('SELECT 1 AS v');
      final rows = parseRows(res);
      expect(rows.first['v'], 1);
    });
  });
}
