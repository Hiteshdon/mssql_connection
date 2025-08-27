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

Future<void> runWithClientAndTempDb(
  Future<void> Function(MssqlConnection client, String dbName) body,
) async {
  final server = Platform.environment['MSSQL_SERVER'] ?? '192.168.1.10:1433';
  final username = Platform.environment['MSSQL_USER'] ?? 'sa';
  final password =
      Platform.environment['MSSQL_PASS'] ??
      Platform.environment['MSSQL_PASSWORD'] ??
      'eSeal@123';

  // Parse server into ip and port (default 1433)
  final parts = server.split(':');
  final ip = parts.isNotEmpty ? parts.first : '127.0.0.1';
  final port = parts.length > 1 ? parts[1] : '1433';

  final client = MssqlConnection.getInstance();
  final ok = await client.connect(
    ip: ip,
    port: port,
    databaseName: 'master',
    username: username,
    password: password,
  );
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
      await client.execute(
        'ALTER DATABASE [$dbName] SET SINGLE_USER WITH ROLLBACK IMMEDIATE',
      );
      await client.execute('DROP DATABASE [$dbName]');
    } catch (_) {}
    await client.disconnect();
  }
}

// Compat layer so tests can call client.execute/query/executeParams with
// a MssqlConnection instance.
extension _TestClientCompat on MssqlConnection {
  Future<String> execute(String sql) => writeData(sql);
  Future<String> query(String sql) => getData(sql);
  Future<String> executeParams(String sql, Map<String, dynamic> params) =>
      writeDataWithParams(sql, params);
}

Future<Map<String, dynamic>> parseJson(String jsonStr) async =>
    json.decode(jsonStr) as Map<String, dynamic>;
List<dynamic> parseRows(String jsonStr) =>
    (json.decode(jsonStr) as Map<String, dynamic>)['rows'] as List<dynamic>;
int affectedCount(String jsonStr) =>
    (json.decode(jsonStr) as Map<String, dynamic>)['affected'] as int? ?? 0;

/// A reusable temp-database harness for running many tests within a single DB.
///
/// This avoids the overhead of creating/dropping a database for each test case
/// when scaling up to dozens of cases per mode. Use setUpAll/tearDownAll in
/// your test group to initialize and dispose this harness once per group.
class TempDbHarness {
  late final MssqlConnection client;
  late final String dbName;

  Future<void> init() async {
    final server = Platform.environment['MSSQL_SERVER'] ?? '192.168.1.10:1433';
    final username = Platform.environment['MSSQL_USER'] ?? 'sa';
    final password =
        Platform.environment['MSSQL_PASS'] ??
        Platform.environment['MSSQL_PASSWORD'] ??
        'eSeal@123';
    final parts = server.split(':');
    final ip = parts.isNotEmpty ? parts.first : '127.0.0.1';
    final port = parts.length > 1 ? parts[1] : '1433';

    client = MssqlConnection.getInstance();
    final ok = await client.connect(
      ip: ip,
      port: port,
      databaseName: 'master',
      username: username,
      password: password,
    );
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
      await client.execute(
        'ALTER DATABASE [$dbName] SET SINGLE_USER WITH ROLLBACK IMMEDIATE',
      );
      await client.execute('DROP DATABASE [$dbName]');
    } catch (_) {}
    await client.disconnect();
  }

  Future<String> execute(String sql) => client.execute(sql);
  Future<String> query(String sql) => client.query(sql);
  Future<String> executeParams(String sql, Map<String, dynamic> params) =>
      client.executeParams(sql, params);

  /// Drops the table if it exists and recreates it using the provided CREATE TABLE statement.
  Future<void> recreateTable(String createTableSql) async {
    // Attempt to extract table name from CREATE TABLE statement to drop it first.
    // Expect pattern like: CREATE TABLE [schema.]Name ( ... )
    final match = RegExp(
      r'CREATE\s+TABLE\s+([^\s(]+)',
      caseSensitive: false,
    ).firstMatch(createTableSql);
    if (match != null) {
      final tableIdent = match.group(1)!;
      // Build raw (unbracketed) two-part name for OBJECT_ID and a bracketed form for DROP TABLE
      String raw = tableIdent.replaceAll('[', '').replaceAll(']', '');
      if (!raw.contains('.')) raw = 'dbo.$raw';
      final parts = raw.split('.');
      final bracketed = '[${parts[0]}].[${parts[1]}]';
      await execute(
        "IF OBJECT_ID(N'$raw', N'U') IS NOT NULL DROP TABLE $bracketed",
      );
    }
    await execute(createTableSql);
  }
}

// Centralized test DB configuration
class TestDbConfig {
  final String ip;
  final int port;
  final String databaseName;
  final String username;
  final String password;

  const TestDbConfig({
    required this.ip,
    required this.port,
    required this.databaseName,
    required this.username,
    required this.password,
  });

  static TestDbConfig fromEnv() {
    final env = Platform.environment;
    return TestDbConfig(
      ip: env['MSSQL_IP']?.trim().isNotEmpty == true
          ? env['MSSQL_IP']!.trim()
          : '127.0.0.1',
      port: int.tryParse(env['MSSQL_PORT'] ?? '') ?? 1433,
      databaseName: env['MSSQL_DB']?.trim().isNotEmpty == true
          ? env['MSSQL_DB']!.trim()
          : 'master',
      username: env['MSSQL_USER']?.trim() ?? '',
      password: env['MSSQL_PASSWORD']?.trim() ?? '',
    );
  }

  static final TestDbConfig current = TestDbConfig.fromEnv();
}
