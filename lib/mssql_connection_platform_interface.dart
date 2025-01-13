import 'dart:io'; // Import Platform for detecting the OS

import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'mssql_connection_method_channel.dart';
import 'method_channel_mssql_connection_windows.dart';

/// A platform interface for interacting with MS SQL Server databases.
///
/// This class declares methods for performing common database operations,
/// and platform-specific implementations should extend this class.
abstract class MsSQLConnectionPlatform extends PlatformInterface {
  /// Constructs a [MsSQLConnectionPlatform].
  MsSQLConnectionPlatform() : super(token: _token);

  static final Object _token = Object();

  static MsSQLConnectionPlatform? _instance;

  /// The default instance of [MsSQLConnectionPlatform] to use.
  ///
  /// This is a singleton, and the instance will be set based on the platform.
  static MsSQLConnectionPlatform get instance {
    if (_instance == null) {
      if (Platform.isWindows) {
        _instance = MethodChannelMsSQLConnectionWindows();
      } else {
        _instance = MethodChannelMsSQLConnection();
      }
    }
    return _instance!;
  }

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [MsSQLConnectionPlatform] when
  /// they register themselves.
  static set instance(MsSQLConnectionPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Connects to the MS SQL Server database.
  ///
  /// The required parameters are the IP address, port, database name,
  /// username, password, and an optional timeout in seconds.
  Future<bool> connect({
    required String ip,
    required String port,
    required String databaseName,
    required String username,
    required String password,
    int timeoutInSeconds = 15,
  });

  /// Retrieves data from the database using the specified SQL query.
  Future<String> getData(String query);

  /// Writes data to the database using the specified SQL query.
  Future<String> writeData(String query);

  /// Disconnects from the MS SQL Server database.
  Future<bool> disconnect();
}
