import 'dart:typed_data';

import 'package:mssql_connection/mssql_connection.dart';

Future<int> main() async {
  // Provided credentials
  const server = '192.168.1.10:1433';
  const username = 'sa';
  const password = 'eSeal@123';

  // Parse server into ip/port
  final parts = server.split(':');
  final ip = parts.isNotEmpty ? parts.first : '127.0.0.1';
  final port = parts.length > 1 ? parts[1] : '1433';

  final conn = MssqlConnection.getInstance();
  print('Connecting to master...');
  final ok = await conn.connect(
    ip: ip,
    port: port,
    databaseName: 'master',
    username: username,
    password: password,
  );
  if (!ok) {
    print('CONNECT FAILED');
    return 1;
  }

  final dbName = 'Test_${DateTime.now().millisecondsSinceEpoch}';
  print('Using database: $dbName');

  try {
    // Create DB
    print('Creating DB...');
    print(await conn.writeData('CREATE DATABASE [$dbName]'));

    // Switch context
    print('Using DB...');
    print(await conn.writeData('USE [$dbName]'));

    // Create table
    print('Creating table...');
    print(
      await conn.writeData('''
      CREATE TABLE dbo.Items (
        id INT NOT NULL PRIMARY KEY,
        name NVARCHAR(100) NOT NULL,
        created DATETIME NULL,
        flag BIT NULL,
        data VARBINARY(MAX) NULL
      )
    '''),
    );

    // Insert via sp_executesql with explicit types
    print('Inserting row via params...');
    final insertRes = await conn.writeDataWithParams(
      'INSERT INTO dbo.Items (id, name, created, flag, data) VALUES (@id, @name, @created, @flag, @data)',
      {
        'id': 1,
        'name': 'hello',
        'created': DateTime.now(),
        'flag': true,
        'data': Uint8List.fromList([1, 2, 3, 4]),
      },
    );
    print(insertRes);
    // print('Waiting for 5 minutes(Manual Inspection)...');
    // await Future.delayed(const Duration(minutes: 5));
    // Query back
    print('Selecting rows...');
    final rowsJson = await conn.getData(
      'SELECT id, name, created, flag, DATALENGTH(data) AS data_len FROM dbo.Items',
    );
    print(rowsJson);
  } catch (e) {
    print('ERROR: $e');
  } finally {
    // Always drop DB; force single_user to avoid locks
    print('Dropping DB...');
    try {
      await conn.writeData('USE master');
      await conn.writeData(
        'ALTER DATABASE [$dbName] SET SINGLE_USER WITH ROLLBACK IMMEDIATE',
      );
      print(await conn.writeData('DROP DATABASE [$dbName]'));
    } catch (e) {
      print('Drop DB error: $e');
    }
    await conn.disconnect();
  }

  return 0;
}
