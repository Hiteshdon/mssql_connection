import 'dart:io';
import 'dart:typed_data';

import 'package:mssql_connection/mssql_connection.dart';

Future<void> main() async {
  // Configure from environment for easy local testing.
  // Set MSSQL_SERVER, MSSQL_USER, MSSQL_PASS or rely on test defaults.
  final server = Platform.environment['MSSQL_SERVER'] ?? '192.168.1.10:1433';
  final username = Platform.environment['MSSQL_USER'] ?? 'sa';
  final password = Platform.environment['MSSQL_PASS'] ?? 'eSeal@123';

  final client = MssqlClient(
    server: server,
    username: username,
    password: password,
  );

  final ok = await client.connect();
  if (!ok) {
    print('Connection failed to $server as $username');
    return;
  }

  // Simple query returning a variety of types
  final q1 = await client.query("""
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
  print(q1);

  // Parameterized query via sp_executesql using automatic type inference
  final params = {
    '@id': 42, // int -> int
    '@when': DateTime.now().toUtc(), // DateTime -> datetime
    '@blob': Uint8List.fromList([1, 2, 3, 4]), // bytes -> varbinary(max)
  };
  final q2 = await client.queryParams(
    'SELECT @id AS id, CONVERT(datetime2, @when) AS when_dt2, @blob AS blob',
    params,
  );
  print(q2);

  await client.close();
}
