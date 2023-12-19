import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'mssql_connection_platform_interface.dart';

class MethodChannelMsSQLConnection extends MsSQLConnectionPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final MethodChannel methodChannel = const MethodChannel('mssql_connection');

  @override
  Future<bool> connect(
      {required String ip,
      required String port,
      required String databaseName,
      required String username,
      required String password,
      int timeoutInSeconds = 30}) async {
    try {
      var invokeMethod = await methodChannel.invokeMethod<bool>(
            'connect',
            {
              'url': "jdbc:jtds:sqlserver://$ip:$port/$databaseName",
              'username': username,
              'password': password,
              'timeoutInSeconds': timeoutInSeconds,
            },
          ) ??
          false;
      return invokeMethod;
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<String> getData(String query) async {
    try {
      final String? result =
          await methodChannel.invokeMethod<String>('getData', {'query': query});
      return result ?? '';
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<String> writeData(String query) async {
    try {
      final String? result = await methodChannel
          .invokeMethod<String>('writeData', {'query': query});
      return result ?? '';
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<bool> disconnect() async {
    try {
      final bool? result = await methodChannel.invokeMethod<bool>('disconnect');
      return result ?? false;
    } catch (e) {
      rethrow;
    }
  }
}
