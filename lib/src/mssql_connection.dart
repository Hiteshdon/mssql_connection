import 'dart:async';

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
    // Basic input validation to prevent invalid dbopen calls and fail fast.
    final _ipTrim = ip.trim();
    final _portTrim = port.trim();
    final _userTrim = username.trim();
    final _pwd = password; // allow spaces in password
    final _timeout = timeoutInSeconds < 0 ? 0 : timeoutInSeconds;

    if (_ipTrim.isEmpty) {
      MssqlLogger.w('connect(params) | invalid ip (empty)');
      return false;
    }
    if (_portTrim.isEmpty) {
      MssqlLogger.w('connect(params) | invalid port (empty)');
      return false;
    }
    final portNum = int.tryParse(_portTrim);
    if (portNum == null || portNum <= 0 || portNum > 65535) {
      MssqlLogger.w('connect(params) | invalid port (non-numeric or out-of-range): $_portTrim');
      return false;
    }
    if (_userTrim.isEmpty) {
      MssqlLogger.w('connect(params) | invalid username (empty)');
      return false;
    }
    if (_pwd.isEmpty) {
      MssqlLogger.w('connect(params) | invalid password (empty)');
      return false;
    }

    _ip = _ipTrim;
    _port = _portTrim;
    _database = databaseName;
    _username = _userTrim;
    _password = _pwd;
    _timeoutInSeconds = _timeout;

    try {
      final server = '$_ipTrim:$_portTrim';
      _client = MssqlClient(
        server: server,
        username: _userTrim,
        password: _pwd,
      );
      final ok = await _client!.connect(loginTimeoutSeconds: _timeout);
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
      // Clear saved params so offline calls do not attempt implicit reconnect
      _ip = null;
      _port = null;
      _database = null;
      _username = null;
      _password = null;
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
