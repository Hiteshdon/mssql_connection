import 'package:flutter_test/flutter_test.dart';
import 'package:mssql_connection/mssql_connection.dart';
import 'package:mssql_connection/mssql_connection_platform_interface.dart';
import 'package:mssql_connection/mssql_connection_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockMsSQLConnectionPlatform
    with MockPlatformInterfaceMixin
    implements MsSQLConnectionPlatform {
  @override
  Future<bool> connect(
      {required String ip,
      required String port,
      required String databaseName,
      required String username,
      required String password,
      int timeoutInSeconds = 15}) async {
    // Implementing the connect method
    return Future.value(true);
  }

  @override
  Future<bool> disconnect() async {
    // Implementing the disconnect method
    return Future.value(true);
  }

  @override
  Future<String> getData(String query) async {
    // Implementing the getData method
    return Future.value("Mocked data");
  }

  @override
  Future<String> writeData(String query) async {
    // Implementing the writeData method
    return Future.value("Mocked result");
  }

  @override
  Future<dynamic> executeParameterizedQuery(String sql, List<String> params) async {
    // Implementing the executeParameterizedQuery method
    return Future.value("Mocked parameterized query result");
  }
}

void main() {
  final MsSQLConnectionPlatform initialPlatform =
      MsSQLConnectionPlatform.instance;

  test('$MethodChannelMsSQLConnection is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelMsSQLConnection>());
  });

  test('MssqlConnection mock test', () async {
    MssqlConnection mssqlConnectionPlugin = MssqlConnection.getInstance();
    MockMsSQLConnectionPlatform fakePlatform = MockMsSQLConnectionPlatform();
    MsSQLConnectionPlatform.instance = fakePlatform;

    // Test the connect method
    bool connectResult = await mssqlConnectionPlugin.connect(
      ip: "mockIp",
      port: "mockPort",
      databaseName: "mockDatabaseName",
      username: "mockUsername",
      password: "mockPassword",
    );
    expect(connectResult, true);

    // Test the disconnect method
    bool disconnectResult = await mssqlConnectionPlugin.disconnect();
    expect(disconnectResult, true);

    // Test the getData method
    String getDataResult = await mssqlConnectionPlugin.getData("mockQuery");
    expect(getDataResult, "Mocked data");

    // Test the writeData method
    String writeDataResult = await mssqlConnectionPlugin.writeData("mockQuery");
    expect(writeDataResult, "Mocked result");
  });
}
