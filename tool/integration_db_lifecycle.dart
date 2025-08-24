import 'dart:typed_data';
import 'package:mssql_connection/mssql_connection.dart';

Future<int> main() async {
  // Provided credentials
  const server = '192.168.1.10:1433';
  const username = 'sa';
  const password = 'eSeal@123';

  final client = MssqlClient(server: server, username: username, password: password);
  final ok = await client.connect();
  if (!ok) {
    print('CONNECT FAILED');
    return 1;
  }

  final dbName = 'Test_${DateTime.now().millisecondsSinceEpoch}';
  print('Using database: $dbName');

  try {
    // Create DB
    print('Creating DB...');
    print(await client.execute('CREATE DATABASE [$dbName]'));

    // Switch context
    print('Using DB...');
    print(await client.execute('USE [$dbName]'));

    // Create table
    print('Creating table...');
    print(await client.execute('''
      CREATE TABLE dbo.Items (
        id INT NOT NULL PRIMARY KEY,
        name NVARCHAR(100) NOT NULL,
        created DATETIME NULL,
        flag BIT NULL,
        data VARBINARY(MAX) NULL
      )
    '''));

    // Insert via sp_executesql with explicit types
    print('Inserting row via params...');
    final insertRes = await client.executeParams(
      'INSERT INTO dbo.Items (id, name, created, flag, data) VALUES (@id, @name, @created, @flag, @data)',
      {
        'id': 1,
        'name': 'hello',
        'created': DateTime.now(),
        'flag': true,
        'data': Uint8List.fromList([1, 2, 3, 4])
      },
      types: {
        'id': SYBINT4,
        'name': SYBNVARCHAR,
        'created': SYBDATETIME,
        'flag': SYBBIT,
        'data': SYBVARBINARY,
      },
    );
    print(insertRes);

    // Query back
    print('Selecting rows...');
    final rowsJson = await client.query('SELECT id, name, created, flag, DATALENGTH(data) AS data_len FROM dbo.Items');
    print(rowsJson);
  } catch (e) {
    print('ERROR: $e');
  } finally {
    // Always drop DB; force single_user to avoid locks
    print('Dropping DB...');
    try {
      await client.execute('USE master');
      await client.execute('ALTER DATABASE [$dbName] SET SINGLE_USER WITH ROLLBACK IMMEDIATE');
      print(await client.execute('DROP DATABASE [$dbName]'));
    } catch (e) {
      print('Drop DB error: $e');
    }
    await client.close();
  }

  return 0;
}
