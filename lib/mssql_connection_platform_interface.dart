import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'mssql_connection_method_channel.dart';

abstract class MsSQLConnectionPlatform extends PlatformInterface {
  /// Constructs a MsSQLConnectionPlatform.
  MsSQLConnectionPlatform() : super(token: _token);

  static final Object _token = Object();

  static MsSQLConnectionPlatform _instance = MethodChannelMsSQLConnection();

  /// The default instance of [MsSQLConnectionPlatform] to use.
  ///
  /// Defaults to [MethodChannelMsSQLConnection].
  static MsSQLConnectionPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [MsSQLConnectionPlatform] when
  /// they register themselves.
  static set instance(MsSQLConnectionPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<bool> connect({required String ip,required String port,required String databaseName,required String username,required String password, int timeoutInSeconds = 15}) {
    throw UnimplementedError('connect() has not been implemented.');
  }

  Future<String> getData(String query) {
    throw UnimplementedError('getData() has not been implemented.');
  }

  Future<String> writeData(String query) {
    throw UnimplementedError('writeData() has not been implemented.');
  }

  Future<bool> disconnect() {
    throw UnimplementedError('disconnect() has not been implemented.');
  }
}
