import 'dart:typed_data';
import 'package:mssql_connection/mssql_connection.dart';

Future<void> main() async {
  // Replace with your server, username, and password.
  final client = MssqlClient(
    server: 'SERVER_HOST:PORT',
    username: 'USERNAME',
    password: 'PASSWORD',
  );

  final ok = await client.connect();
  if (!ok) {
    print('Connection failed');
    return;
  }

  // Simple query returning a variety of types
  final q1 = await client.query(
    """
    SELECT
      CAST(1 AS int)          AS i32,
      CAST(1 AS bigint)       AS i64,
      CAST(1.5 AS real)       AS r32,
      CAST(1.5 AS float)      AS r64,
      CAST(1 AS bit)          AS is_true,
      CAST(N'hello' AS nvarchar(10)) AS nv,
      CAST(0x010203 AS varbinary(3)) AS vb,
      CAST(GETDATE() AS datetime) AS dt
  """,
  );
  print(q1);

  // Parameterized query via sp_executesql
  final params = {
    '@id': 42,
    '@when': DateTime.now().toUtc().toIso8601String(), // pass as string; server converts
    '@blob': Uint8List.fromList([1, 2, 3, 4]),
  };
  final types = {
    '@id': SYBINT4,
    '@when': SYBVARCHAR, // send as nvarchar; SQL will CAST if needed
    '@blob': SYBVARBINARY,
  };
  final q2 = await client.queryParams(
    'SELECT @id AS id, CONVERT(datetime2, @when) AS when_dt2, @blob AS blob',
    params,
    types: types,
  );
  print(q2);

  await client.close();
}
