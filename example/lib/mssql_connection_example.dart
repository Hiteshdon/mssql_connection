import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:mssql_connection/mssql_connection.dart';
void main() async {
  // Enable verbose logs to diagnose native loading/execution
  // Configure from environment for easy local testing.
  // Set MSSQL_SERVER (e.g. 192.168.1.10:1433), MSSQL_USER, MSSQL_PASS, MSSQL_DB.
  debugPrint("Using connection settings:");
  final server = Platform.environment['MSSQL_SERVER'] ?? '192.168.1.10:1433';
  final username = Platform.environment['MSSQL_USER'] ?? 'sa';
  final password = Platform.environment['MSSQL_PASS'] ?? 'eSeal@123';
  final database = Platform.environment['MSSQL_DB'] ?? 'master';

  final parts = server.split(':');
  final ip = parts.isNotEmpty ? parts.first : server;
  final port = parts.length > 1 ? parts[1] : '1433';

  final conn = MssqlConnection.getInstance();
  bool ok;
  try {
    ok = await conn.connect(
      ip: ip,
      port: port,
      databaseName: database,
      username: username,
      password: password,
    );
  } catch (e, st) {
    debugPrint('connect threw: $e\n$st');
    return;
  }
  if (!ok) {
    debugPrint('Connection failed to $server as $username');
    return;
  }

  // Simple query returning a variety of types
  final q1 = await conn.getData("""
    SELECT
      CAST(1 AS int)          AS i32,
      CAST(1 AS bigint)       AS i64,
      CAST(1.5 AS real)       AS r32,
      CAST(1.5 AS float)      AS r64,
      CAST(1 AS bit)          AS is_true,
      CAST(N'hello' AS nvarchar(10)) AS nv,
      CAST(0x010203 AS varbinary(3)) AS vb,
      CAST(GETDATE() AS datetime) AS dt
  """);
  debugPrint(q1);

  // Parameterized query via sp_executesql using automatic type inference
  final params = {
    '@id': 42, // int -> int
    '@when': DateTime.now().toUtc(), // DateTime -> datetime
    '@blob': Uint8List.fromList([1, 2, 3, 4]), // bytes -> varbinary(max)
  };
  final q2 = await conn.getDataWithParams(
    'SELECT @id AS id, CONVERT(datetime2, @when) AS when_dt2, @blob AS blob',
    params,
  );
  debugPrint(q2);

  // Basic DDL/DML using write helpers
  await conn.writeData(
    'CREATE TABLE #tmp (id INT PRIMARY KEY, name NVARCHAR(50), age INT NULL)',
  );
  final q3 = await conn.writeDataWithParams(
    'INSERT INTO #tmp (id, name) VALUES (@id, @name)',
    {'@id': 1, '@name': 'Alice'},
  );
  debugPrint(q3);
  final q4 = await conn.writeDataWithParams(
    'INSERT INTO #tmp (id, name) VALUES (@id, @name)',
    {'@id': 2, '@name': 'Alice'},
  );
  debugPrint(q4);
  final q5 = await conn.writeDataWithParams(
    'UPDATE #tmp SET age = @age WHERE name = @name',
    {'@id': 2, '@name': 'Alice', '@age': 30},
  );
  debugPrint(q5);
  // Verify rows before bulk insert
  debugPrint(await conn.getData('SELECT * FROM #tmp'));
  // Bulk insert
  final bulkRows = [
    {'id': 3, 'name': 'Bob', 'age': 25},
    {'id': 4, 'name': 'Charlie', 'age': 35},
  ];
  final bulkResult = await conn.bulkInsert(
    '#tmp',
    bulkRows,
    columns: ['id', 'name', 'age'],
  );
  debugPrint('Bulk insert result: $bulkResult');
  // Verify rows after bulk insert
  debugPrint(await conn.getData('SELECT * FROM #tmp'));

  await conn.disconnect();
}
