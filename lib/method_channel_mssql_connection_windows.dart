import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

import 'mssql_connection_platform_interface.dart';

/// A platform implementation of [MsSQLConnectionPlatform] using method channels for Windows.
class MethodChannelMsSQLConnectionWindows extends MsSQLConnectionPlatform {
  /// The method channel used to interact with the native platform on Windows.
  @visibleForTesting
  final MethodChannel methodChannel =
      const MethodChannel('mssql_connection/windows');

  @override
  Future<bool> connect({
    required String ip,
    required String port,
    required String databaseName,
    required String username,
    required String password,
    int timeoutInSeconds = 30,
  }) async {
    try {
      final bool? result = await methodChannel.invokeMethod<bool>('connect', {
        'server': '$ip,$port',
        'database': databaseName,
        'user': username,
        'password': password,
        'timeout': timeoutInSeconds.toString(),
      });
      return result ?? false;
    } on PlatformException catch (e) {
      throw refineError(e.message ?? e.toString());
    } catch (e) {
      throw refineError(e.toString());
    }
  }

  String refineError(String message) {
    return message
        .replaceAll("[Microsoft][ODBC Driver 18 for SQL Server]", "")
        .replaceAll("Message: ", "")
        .replaceAll("[SQL Server]", "")
        .trim();
  }

  @override
  Future<String> getData(String query) async {
    try {
      final String result = (await methodChannel
              .invokeMethod<String>('getData', {'query': query})) ??
          "";
      return result;
    } on PlatformException catch (e) {
      throw refineError(e.message ?? e.toString());
    } catch (e) {
      throw refineError(e.toString());
    }
  }

  @override
  Future<String> writeData(String query) async {
    try {
      final String? result =
          await methodChannel.invokeMethod<String>('writeData', {
        'query': query,
      });
      return result ?? '';
    } on PlatformException catch (e) {
      throw refineError(e.message ?? e.toString());
    } catch (e) {
      throw refineError(e.toString());
    }
  }

  @override
  Future<bool> disconnect() async {
    try {
      final bool? result = await methodChannel.invokeMethod<bool>('disconnect');
      return result ?? false;
    } on PlatformException catch (e) {
      throw refineError(e.message ?? e.toString());
    } catch (e) {
      throw refineError(e.toString());
    }
  }
}
