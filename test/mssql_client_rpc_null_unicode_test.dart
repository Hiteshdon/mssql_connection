import 'package:test/test.dart';

import 'test_utils.dart';

/// Regression tests for issue #40: NULL and Unicode parameter bindings must
/// not drop the connection (Msg 3621 / SYBNVARCHAR 0x67 on Azure SQL Edge).
void main() {
  group('MssqlClient - RPC null and Unicode params (#40)', () {
    final harness = TempDbHarness();

    setUpAll(() async {
      await harness.init();
    });

    tearDownAll(() async {
      await harness.dispose();
    });

    test('SELECT with NULL parameter returns null column', () async {
      final rows = parseRows(
        await harness.executeParams('SELECT @p1 AS result', {'p1': null}),
      );
      expect(rows, hasLength(1));
      expect(rows.first['result'], isNull);
    });

    test('SELECT with Unicode string parameter returns intact value', () async {
      const value = 'Test 😊 Héllo';
      final rows = parseRows(
        await harness.executeParams('SELECT @p1 AS result', {'p1': value}),
      );
      expect(rows, hasLength(1));
      expect(rows.first['result'], value);
    });

    test('SELECT with ASCII-only string parameter still works', () async {
      const value = 'plain ascii';
      final rows = parseRows(
        await harness.executeParams('SELECT @p1 AS result', {'p1': value}),
      );
      expect(rows, hasLength(1));
      expect(rows.first['result'], value);
    });
  });
}
