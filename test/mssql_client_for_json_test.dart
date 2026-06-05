import 'dart:convert';

import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  group('MssqlClient - FOR JSON handling', () {
    final harness = TempDbHarness();

    setUpAll(() async {
      await harness.init();
    });

    tearDownAll(() async {
      await harness.dispose();
    });

    test('decodes large nested FOR JSON PATH payloads intact', () async {
      final outer = parseRows(
        await harness.query('''
WITH N AS (
  SELECT 1 AS i
  UNION ALL
  SELECT i + 1 FROM N WHERE i < 40
)
SELECT
  (
    SELECT
      i AS pk2,
      TRIM(REPLICATE(N'California Roll ', 2)) AS cTitle,
      CAST(0.00 AS decimal(10, 2)) AS nAddPrice,
      1 AS nMulti,
      0 AS nQty,
      0 AS nBasicQty,
      0 AS nClick,
      N'' AS cCmd
    FROM N
    FOR JSON PATH
  ) AS modLis,
  CAST(3 AS float) AS nQtyLimit,
  CAST(0 AS float) AS nRequired,
  0 AS nBasicQty
OPTION (MAXRECURSION 0)
'''),
      );

      expect(outer, hasLength(1));
      final modLis = outer.first['modLis'] as String;
      expect(modLis.length, greaterThan(1024));

      final decoded = jsonDecode(modLis) as List<dynamic>;
      expect(decoded, hasLength(40));
      expect((decoded.first as Map<String, dynamic>)['pk2'], 1);
      expect((decoded.last as Map<String, dynamic>)['pk2'], 40);
    });
  });
}
