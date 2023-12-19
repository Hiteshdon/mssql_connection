import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mssql_connection/mssql_connection_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MethodChannelMsSQLConnection platform = MethodChannelMsSQLConnection();
  const MethodChannel channel = MethodChannel('mssql_connection');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      channel,
      (MethodCall methodCall) async {
        switch (methodCall.method) {
          case 'connect':
            // Implementing the connect method
            return true;
          case 'disconnect':
            // Implementing the disconnect method
            return true;
          case 'getData':
            // Implementing the getData method
            return 'Mocked data';
          case 'writeData':
            // Implementing the writeData method
            return 'Mocked result';
          default:
            return null;
        }
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('connect', () async {
    bool result = await platform.connect(
      ip: 'mockIp',
      port: 'mockPort',
      databaseName: 'mockDatabaseName',
      username: 'mockUsername',
      password: 'mockPassword',
    );
    expect(result, true);
  });

  test('disconnect', () async {
    bool result = await platform.disconnect();
    expect(result, true);
  });

  test('getData', () async {
    String result = await platform.getData('mockQuery');
    expect(result, 'Mocked data');
  });

  test('writeData', () async {
    String result = await platform.writeData('mockQuery');
    expect(result, 'Mocked result');
  });
}
