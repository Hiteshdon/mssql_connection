import 'mssql_connection_platform_interface.dart';

class MssqlConnection {
  static MssqlConnection? _instance;

  bool _isConnected = false;

  bool get isConnected => _isConnected;

  MssqlConnection._(); // Private constructor

  static MssqlConnection getInstance() {
    _instance ??=
        MssqlConnection._(); // Create a new instance if it doesn't exist
    return _instance!;
  }

  Future<bool> connect(
      {required String ip,
      required String port,
      required String databaseName,
      required String username,
      required String password,
      int timeoutInSeconds = 15}) async {
    try {
      _isConnected = await MsSQLConnectionPlatform.instance.connect(
        ip: ip,
        port: port,
        databaseName: databaseName,
        username: username,
        password: password,
        timeoutInSeconds: timeoutInSeconds,
      );

      return _isConnected;
    } catch (e) {
      rethrow;
    }
  }

  Future<String> getData(String query) {
    try {
      return MsSQLConnectionPlatform.instance.getData(query);
    } catch (e) {
      rethrow;
    }
  }

  Future<String> writeData(String query) {
    try {
      return MsSQLConnectionPlatform.instance.writeData(query);
    } catch (e) {
      rethrow;
    }
  }

  Future<bool> disconnect() {
    try {
      return MsSQLConnectionPlatform.instance.disconnect();
    } catch (e) {
      rethrow;
    }
  }
}
