import 'mssql_connection_platform_interface.dart';

/// A singleton class for managing MS SQL Server database connections.
///
/// Example:
/// ```dart
/// MssqlConnection mssqlConnection = MssqlConnection.getInstance();
///
/// // Connect to the database
/// bool isConnected = await mssqlConnection.connect(
///   ip: 'your_ip',
///   port: 'your_port',
///   databaseName: 'your_database_name',
///   username: 'your_username',
///   password: 'your_password',
///   timeoutInSeconds: 15,
/// );
///
/// // Fetch data from the database
/// String query = 'SELECT * FROM YourTable';
/// String result = await mssqlConnection.getData(query);
///
/// // Write data to the database
/// String updateQuery = 'UPDATE YourTable SET columnName = "NewValue" WHERE condition';
/// String writeResult = await mssqlConnection.writeData(updateQuery);
///
/// // Disconnect from the database
/// bool isDisconnected = await mssqlConnection.disconnect();
/// ```
class MssqlConnection {
  static MssqlConnection? _instance;

  bool _isConnected = false;

  bool get isConnected => _isConnected;

  MssqlConnection._(); // Private constructor

  /// Returns the singleton instance of [MssqlConnection].
  static MssqlConnection getInstance() {
    _instance ??=
        MssqlConnection._(); // Create a new instance if it doesn't exist
    return _instance!;
  }

  /// Connects to the MS SQL Server database.
  ///
  /// Parameters:
  /// - [ip]: IP address of the server.
  /// - [port]: Port number to connect.
  /// - [databaseName]: Name of the database.
  /// - [username]: Username for authentication.
  /// - [password]: Password for authentication.
  /// - [timeoutInSeconds]: Timeout duration for the connection (default is 15 seconds).
  Future<bool> connect({
    required String ip,
    required String port,
    required String databaseName,
    required String username,
    required String password,
    int timeoutInSeconds = 15,
  }) async {
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

  /// Fetches data from the MS SQL Server database based on the provided query.
  ///
  /// Parameters:
  /// - [query]: SQL query to retrieve data.
  Future<String> getData(String query) {
    try {
      return MsSQLConnectionPlatform.instance.getData(query);
    } catch (e) {
      rethrow;
    }
  }

  /// Writes data to the MS SQL Server database based on the provided query.
  ///
  /// Parameters:
  /// - [query]: SQL query to write data.
  Future<String> writeData(String query) {
    try {
      return MsSQLConnectionPlatform.instance.writeData(query);
    } catch (e) {
      rethrow;
    }
  }

  /// Executes a parameterized query against the database.
  ///
  /// This method uses prepared statements to prevent SQL injection attacks.
  /// 
  /// Parameters:
  /// - [sql]: SQL query with placeholders ('?') for parameters.
  /// - [params]: List of parameter values to bind to the query.
  ///
  /// Returns the query result for SELECT queries or affected rows count for INSERT/UPDATE/DELETE.
  Future<dynamic> executeParameterizedQuery(String sql, List<String> params) {
    try {
      return MsSQLConnectionPlatform.instance.executeParameterizedQuery(sql, params);
    } catch (e) {
      rethrow;
    }
  }

  /// Disconnects from the MS SQL Server database.
  Future<bool> disconnect() {
    try {
      _isConnected = false;
      return MsSQLConnectionPlatform.instance.disconnect();
    } catch (e) {
      rethrow;
    }
  }
}
