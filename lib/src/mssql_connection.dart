import 'dart:async';
import 'dart:convert';

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
  bool? _encrypt;
  bool _trustServerCertificate = false;
  String? _tdsVersion;

  bool get isConnected => _client?.isConnected == true;

  Future<bool> connect({
    required String ip,
    required String port,
    required String databaseName,
    required String username,
    required String password,
    int timeoutInSeconds = 15,

    /// Encryption mode. `true` → require TLS; `false` → disable TLS;
    /// `null` → use FreeTDS default.
    bool? encrypt,

    /// When `true`, FreeTDS will not verify the server’s SSL certificate
    /// hostname (`check_ssl_hostname = no`). Requires the native OS to
    /// support environment-variable manipulation via FFI.
    bool trustServerCertificate = false,

    /// TDS protocol version string: `'7.0'`, `'7.1'`, `'7.2'`, `'7.3'`, or
    /// `'7.4'` (recommended for SQL Server 2012+). Null → FreeTDS default.
    String? tdsVersion,
  }) async {
    // Basic input validation to prevent invalid dbopen calls and fail fast.
    final ipTrim = ip.trim();
    final portTrim = port.trim();
    final userTrim = username.trim();
    final pwd = password; // allow spaces in password
    final timeout = timeoutInSeconds < 0 ? 0 : timeoutInSeconds;

    if (ipTrim.isEmpty) {
      MssqlLogger.w('connect(params) | invalid ip (empty)');
      return false;
    }
    if (portTrim.isEmpty) {
      MssqlLogger.w('connect(params) | invalid port (empty)');
      return false;
    }
    final portNum = int.tryParse(portTrim);
    if (portNum == null || portNum <= 0 || portNum > 65535) {
      MssqlLogger.w(
        'connect(params) | invalid port (non-numeric or out-of-range): $portTrim',
      );
      return false;
    }
    if (userTrim.isEmpty) {
      MssqlLogger.w('connect(params) | invalid username (empty)');
      return false;
    }
    if (pwd.isEmpty) {
      MssqlLogger.w('connect(params) | invalid password (empty)');
      return false;
    }

    _ip = ipTrim;
    _port = portTrim;
    _database = databaseName;
    _username = userTrim;
    _password = pwd;
    _timeoutInSeconds = timeout;
    _encrypt = encrypt;
    _trustServerCertificate = trustServerCertificate;
    _tdsVersion = tdsVersion;

    try {
      final server = '$ipTrim:$portTrim';
      _client = MssqlClient(
        server: server,
        username: userTrim,
        password: pwd,
        encrypt: _encrypt,
        trustServerCertificate: _trustServerCertificate,
        tdsVersion: _tdsVersion,
      );
      final ok = await _client!.connect(loginTimeoutSeconds: timeout);
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

  /// Execute a batch of write statements inside a single transaction for
  /// higher throughput. Each query is executed sequentially, and all are
  /// committed on success. On failure, a rollback is performed and the
  /// exception is rethrown.
  ///
  /// Returns the list of JSON result strings from each statement.
  Future<List<String>> writeBatch(List<String> queries) async {
    await _ensureConnectedOrReconnect();
    final results = <String>[];
    await writeData('BEGIN TRAN');
    try {
      for (final q in queries) {
        results.add(await _client!.execute(q));
      }
      await writeData('COMMIT');
      return results;
    } catch (e) {
      try {
        await writeData('ROLLBACK');
      } catch (_) {}
      rethrow;
    }
  }

  /// Execute a batch of parameterized write statements inside a transaction.
  /// Each entry is a (query, params) pair. All are committed on success.
  Future<List<String>> writeBatchWithParams(
    List<(String query, Map<String, dynamic> params)> statements,
  ) async {
    await _ensureConnectedOrReconnect();
    final results = <String>[];
    await writeData('BEGIN TRAN');
    try {
      for (final (query, params) in statements) {
        results.add(await _client!.executeParams(query, params));
      }
      await writeData('COMMIT');
      return results;
    } catch (e) {
      try {
        await writeData('ROLLBACK');
      } catch (_) {}
      rethrow;
    }
  }

  /// Get data and return already-parsed JSON (Map) instead of a raw String.
  /// Avoids the caller needing to jsonDecode the result.
  Future<Map<String, dynamic>> getDataAsMap(String query) async {
    final raw = await getData(query);
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  /// Get only the rows list from a query, skipping metadata parsing.
  Future<List<Map<String, dynamic>>> getRows(String query) async {
    final map = await getDataAsMap(query);
    final rows = map['rows'];
    if (rows is List) {
      return rows.cast<Map<String, dynamic>>();
    }
    return [];
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
      _encrypt = null;
      _trustServerCertificate = false;
      _tdsVersion = null;
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
        encrypt: _encrypt,
        trustServerCertificate: _trustServerCertificate,
        tdsVersion: _tdsVersion,
      );
      return;
    }
    throw StateError('Not connected. Call connect() first.');
  }

  static String _escapeBrackets(String name) => name.replaceAll(']', ']]');
}
