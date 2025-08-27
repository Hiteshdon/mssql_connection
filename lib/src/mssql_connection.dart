import 'dart:async';

import 'ffi/freetds_bindings.dart';
import 'mssql_client.dart';
import 'native_logger.dart';

class MssqlConnection {
  static final MssqlConnection _instance = MssqlConnection._internal();
  factory MssqlConnection.getInstance() => _instance;
  MssqlConnection._internal();

  MssqlClient? _client;

  String? _ip;
  String? _port;
  String? _database;
  String? _username;
  String? _password;
  int _timeoutInSeconds = 15;

  bool get isConnected => _client?.isConnected == true;

  Future<bool> connect({
    required String ip,
    required String port,
    required String databaseName,
    required String username,
    required String password,
    int timeoutInSeconds = 15,
  }) async {
    _ip = ip;
    _port = port;
    _database = databaseName;
    _username = username;
    _password = password;
    _timeoutInSeconds = timeoutInSeconds;

    try {
      // Apply global timeouts before creating the connection.
      final db = DBLib.load();
      try {
        // Best-effort; ignore return codes here, we'll surface errors on connect.
        db.dbsetlogintime(timeoutInSeconds);
        db.dbsettime(timeoutInSeconds);
      } catch (_) {}

      final server = '$ip:$port';
      _client = MssqlClient(
        server: server,
        username: username,
        password: password,
      );
      final ok = await _client!.connect();
      if (!ok) return false;

      // Select database for this session.
      if (databaseName.isNotEmpty) {
        await _client!.execute('USE [${_escapeBrackets(databaseName)}]');
        // If USE fails, subsequent queries will fail accordingly.
        MssqlLogger.i('Switched database to $databaseName');
      }
      return true;
    } catch (e, st) {
      MssqlLogger.e('connect failed: $e\n$st');
      return false;
    }
  }

  Future<String> getData(String query) async {
    await _ensureConnectedOrReconnect();
    return _client!.execute(query);
  }

  Future<String> writeData(String query) async {
    await _ensureConnectedOrReconnect();
    return _client!.execute(query);
  }

  Future<String> getDataWithParams(
    String query,
    Map<String, dynamic> params,
  ) async {
    await _ensureConnectedOrReconnect();
    return _client!.executeParams(query, params);
  }

  Future<String> writeDataWithParams(
    String query,
    Map<String, dynamic> params,
  ) async {
    await _ensureConnectedOrReconnect();
    return _client!.executeParams(query, params);
  }

  Future<int> bulkInsert(
    String tableName,
    List<Map<String, dynamic>> rows, {
    List<String>? columns,
    int batchSize = 1000,
  }) async {
    await _ensureConnectedOrReconnect();
    return _client!.bulkInsert(
      tableName,
      rows,
      columns: columns,
      batchSize: batchSize,
    );
  }

  Future<bool> disconnect() async {
    try {
      await _client?.close();
      return true;
    } catch (_) {
      return false;
    } finally {
      _client = null;
    }
  }

  // Basic transaction helpers (optional, convenience)
  Future<void> beginTransaction() async {
    await writeData('BEGIN TRAN');
  }

  Future<void> commit() async {
    await writeData('COMMIT');
  }

  Future<void> rollback() async {
    await writeData('ROLLBACK');
  }

  Future<void> _ensureConnectedOrReconnect() async {
    if (_client?.isConnected == true) return;
    // Attempt reconnection using last known parameters if available
    if (_ip != null &&
        _port != null &&
        _database != null &&
        _username != null &&
        _password != null) {
      await connect(
        ip: _ip!,
        port: _port!,
        databaseName: _database!,
        username: _username!,
        password: _password!,
        timeoutInSeconds: _timeoutInSeconds,
      );
      return;
    }
    throw StateError('Not connected. Call connect() first.');
  }

  static String _escapeBrackets(String name) => name.replaceAll(']', ']]');
}
