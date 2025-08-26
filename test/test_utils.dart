import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:mssql_connection/mssql_connection.dart';

String _uniqueDbName([String prefix = 'Test']) {
  final ts = DateTime.now().millisecondsSinceEpoch;
  final rnd = Random().nextInt(0xFFFFFF);
  return '${prefix}_${ts}_$rnd';
}

Future<void> runWithClientAndTempDb(Future<void> Function(MssqlClient client, String dbName) body) async {
  final server = Platform.environment['MSSQL_SERVER'] ?? '192.168.1.10:1433';
  final username = Platform.environment['MSSQL_USER'] ?? 'sa';
  final password = Platform.environment['MSSQL_PASS'] ?? 'eSeal@123';

  final client = MssqlClient(server: server, username: username, password: password);
  final ok = await client.connect();
  if (!ok) {
    throw StateError('Failed to connect to $server as $username');
  }

  final dbName = _uniqueDbName('Test');
  try {
    await client.execute('CREATE DATABASE [$dbName]');
    await client.execute('USE [$dbName]');
    await body(client, dbName);
  } finally {
    try {
      await client.execute('USE master');
      await client.execute('ALTER DATABASE [$dbName] SET SINGLE_USER WITH ROLLBACK IMMEDIATE');
      await client.execute('DROP DATABASE [$dbName]');
    } catch (_) {}
    await client.close();
  }
}

Future<Map<String, dynamic>> parseJson(String jsonStr) async => json.decode(jsonStr) as Map<String, dynamic>;
List<dynamic> parseRows(String jsonStr) => (json.decode(jsonStr) as Map<String, dynamic>)['rows'] as List<dynamic>;
int affectedCount(String jsonStr) => (json.decode(jsonStr) as Map<String, dynamic>)['affected'] as int? ?? 0;

/// A reusable temp-database harness for running many tests within a single DB.
///
/// This avoids the overhead of creating/dropping a database for each test case
/// when scaling up to dozens of cases per mode. Use setUpAll/tearDownAll in
/// your test group to initialize and dispose this harness once per group.
class TempDbHarness {
  late final MssqlClient client;
  late final String dbName;

  Future<void> init() async {
    final server = Platform.environment['MSSQL_SERVER'] ?? '192.168.1.10:1433';
    final username = Platform.environment['MSSQL_USER'] ?? 'sa';
    final password = Platform.environment['MSSQL_PASS'] ?? 'eSeal@123';

    client = MssqlClient(server: server, username: username, password: password);
    final ok = await client.connect();
    if (!ok) {
      throw StateError('Failed to connect to $server as $username');
    }

    dbName = _uniqueDbName('Bulk');
    await client.execute('CREATE DATABASE [$dbName]');
    await client.execute('USE [$dbName]');
  }

  Future<void> dispose() async {
    try {
      await client.execute('USE master');
      await client.execute('ALTER DATABASE [$dbName] SET SINGLE_USER WITH ROLLBACK IMMEDIATE');
      await client.execute('DROP DATABASE [$dbName]');
    } catch (_) {}
    await client.close();
  }

  Future<String> execute(String sql) => client.execute(sql);
  Future<String> query(String sql) => client.query(sql);
  Future<String> executeParams(String sql, Map<String, dynamic> params) => client.executeParams(sql, params);

  /// Drops the table if it exists and recreates it using the provided CREATE TABLE statement.
  Future<void> recreateTable(String createTableSql) async {
    // Attempt to extract table name from CREATE TABLE statement to drop it first.
    // Expect pattern like: CREATE TABLE [schema.]Name ( ... )
    final match = RegExp(r'CREATE\s+TABLE\s+([^\s(]+)', caseSensitive: false).firstMatch(createTableSql);
    if (match != null) {
      final tableIdent = match.group(1)!;
      // Normalize to two-part name with dbo if needed
      final normalized = tableIdent.contains('.') ? tableIdent : 'dbo.${tableIdent.replaceAll(RegExp(r'^[\[]|[\]]$'), '')}';
      await execute("IF OBJECT_ID('$normalized','U') IS NOT NULL DROP TABLE $normalized");
    }
    await execute(createTableSql);
  }
}
