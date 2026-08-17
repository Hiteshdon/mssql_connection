import 'dart:io';

import 'package:mssql_connection/mssql_connection.dart';
import 'package:mssql_connection/src/mssql_client.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  group('MssqlConnection connect options', () {
    late MssqlConnection conn;
    late String server;
    late String username;
    late String password;
    late String ip;
    late String port;

    setUp(() {
      server = Platform.environment['MSSQL_SERVER'] ?? '192.168.1.4:1433';
      username = Platform.environment['MSSQL_USER'] ?? 'sa';
      password =
          Platform.environment['MSSQL_PASS'] ??
          Platform.environment['MSSQL_PASSWORD'] ??
          'eSeal@123';
      final parts = server.split(':');
      ip = parts.isNotEmpty ? parts.first : '127.0.0.1';
      port = parts.length > 1 ? parts[1] : '1433';
      conn = MssqlConnection.getInstance();
    });

    tearDown(() async {
      await conn.disconnect();
    });

    Future<void> expectConnected({
      bool? encrypt,
      bool trustServerCertificate = false,
      String? tdsVersion,
    }) async {
      final ok = await conn.connect(
        ip: ip,
        port: port,
        databaseName: 'master',
        username: username,
        password: password,
        encrypt: encrypt,
        trustServerCertificate: trustServerCertificate,
        tdsVersion: tdsVersion,
      );

      expect(
        ok,
        isTrue,
        reason:
            'Failed to connect to $server with encrypt=$encrypt, trustServerCertificate=$trustServerCertificate, tdsVersion=$tdsVersion',
      );
      expect(conn.isConnected, isTrue);

      final rows = parseRows(await conn.getData('SELECT DB_NAME() AS db_name'));
      expect(rows, hasLength(1));
      expect(rows.first['db_name'], 'master');
    }

    test('connect accepts explicit tdsVersion=7.4', () async {
      await expectConnected(tdsVersion: '7.4');
    });

    test('connect with tdsVersion=7.4 negotiates TDS 7.4 protocol', () async {
      await expectConnected(tdsVersion: '7.4');

      final rows = parseRows(
        await conn.getData('''
SELECT protocol_version
FROM sys.dm_exec_connections
WHERE session_id = @@SPID
'''),
      );
      expect(rows, hasLength(1));
      final protocolVersion = rows.first['protocol_version'];
      expect(protocolVersion, isNotNull);
      // TDS major version is the high byte (7.4 → 0x74xxxxxx).
      final pv = protocolVersion is int
          ? protocolVersion
          : int.parse(protocolVersion.toString());
      expect((pv >> 24) & 0xFF, 0x74);
    });

    test('connect ignores unsupported tdsVersion and falls back', () async {
      await expectConnected(tdsVersion: '9.9');
    });

    test('connect accepts explicit encrypt=false', () async {
      await expectConnected(encrypt: false);
    });

    test(
      'connect accepts trustServerCertificate=true without breaking login',
      () async {
        await expectConnected(trustServerCertificate: true);
      },
    );

    test(
      'trustServerCertificate override clears CA verification settings for the target server',
      () async {
        final overrideKey = '\n$server';
        final overridePath =
            '${Directory.systemTemp.path}${Platform.pathSeparator}'
            'mssql_connection_trust_cert_${overrideKey.hashCode.abs()}.conf';
        final overrideFile = File(overridePath);
        if (overrideFile.existsSync()) {
          overrideFile.deleteSync();
        }

        await expectConnected(
          encrypt: false,
          trustServerCertificate: true,
          tdsVersion: '7.4',
        );

        expect(overrideFile.existsSync(), isTrue);
        final content = overrideFile.readAsStringSync();
        expect(content, contains('[global]'));
        expect(content, contains('ca file ='));
        expect(content, contains('crl file ='));
        expect(content, contains('check certificate hostname = no'));
        expect(content, contains('[$server]'));
        expect(content, contains('host = $ip'));
        expect(content, contains('port = $port'));
        expect(content, isNot(contains('check_ssl_hostname')));
      },
    );

    test('connect accepts combined options with encrypt=false', () async {
      await expectConnected(
        encrypt: false,
        trustServerCertificate: true,
        tdsVersion: '7.4',
      );
    });

    test(
      'parallel MssqlClient connects with mixed trust and TDS options do not interfere',
      () async {
        final serverAddress = '$ip:$port';
        final clients = <MssqlClient>[
          MssqlClient(
            server: serverAddress,
            username: username,
            password: password,
            trustServerCertificate: true,
            tdsVersion: '7.4',
          ),
          MssqlClient(
            server: serverAddress,
            username: username,
            password: password,
            encrypt: false,
          ),
          MssqlClient(
            server: serverAddress,
            username: username,
            password: password,
            trustServerCertificate: true,
            encrypt: false,
            tdsVersion: '7.4',
          ),
        ];

        try {
          final results = await Future.wait(
            clients.map((client) => client.connect()),
          );
          expect(results, everyElement(isTrue));

          final payloads = await Future.wait(
            clients.map(
              (client) => client.execute('SELECT DB_NAME() AS db_name'),
            ),
          );
          for (final payload in payloads) {
            final rows = parseRows(payload);
            expect(rows, hasLength(1));
            expect(rows.first['db_name'], isNotNull);
          }
        } finally {
          for (final client in clients) {
            await client.close();
          }
        }
      },
    );

    test(
      'connect supports encrypt=true + trustServerCertificate=true on TLS-enabled servers',
      () async {
        await expectConnected(
          encrypt: true,
          trustServerCertificate: true,
          tdsVersion: '7.4',
        );
      },
      skip: Platform.environment['MSSQL_TEST_TLS'] == 'true'
          ? false
          : 'Set MSSQL_TEST_TLS=true and point MSSQL_SERVER at a TLS-enabled SQL Server to validate encrypted login.',
    );
  });
}
