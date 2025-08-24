import 'package:mssql_connection/mssql_connection.dart';
import 'package:test/test.dart';

void main() {
  group('Exports and constants', () {
    test('SYB* constants match expected values', () {
      expect(SYBINT4, equals(56));
      expect(SYBINT8, equals(127));
      expect(SYBFLT8, equals(62));
      expect(SYBBIT, equals(50));
      expect(SYBVARCHAR, equals(39));
      expect(SYBVARBINARY, equals(37));
    });

    test('MssqlClient symbol is exported', () {
      // Type check only; do not instantiate to avoid loading native libs in tests
      expect(MssqlClient, isNotNull);
    });
  });
}
