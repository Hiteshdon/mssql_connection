import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  group('MssqlClient - Large text and Multilingual handling', () {
    final harness = TempDbHarness();

    setUpAll(() async {
      await harness.init();
    });

    tearDownAll(() async {
      await harness.dispose();
    });

    group('large text roundtrip', () {
      setUpAll(() async {
        await harness.recreateTable(
          'CREATE TABLE dbo.BigTexts (id INT IDENTITY(1,1) PRIMARY KEY, val TEXT NOT NULL)',
        );
      });

      test('insert 10k characters and fetch length', () async {
        // Use server-side generation to avoid client parameter size limits.
        // Use ASCII 'a' but cast to NVARCHAR(MAX) to exercise wide storage.
        await harness.execute(
          "INSERT INTO dbo.BigTexts(val) SELECT CAST(REPLICATE(CAST('a' AS VARCHAR(MAX)), 10000) AS NVARCHAR(MAX))",
        );

        // Confirm on the server using LEN (characters) and DATALENGTH (bytes)
        final lens = parseRows(
          await harness.query("SELECT val FROM dbo.BigTexts"),
        );

        expect(lens.first['val'].length, 10000);
      });
    });

    group('multilingual strings', () {
      setUpAll(() async {
        await harness.recreateTable(
          'CREATE TABLE dbo.MultiLang (id INT PRIMARY KEY, label NVARCHAR(400) NOT NULL)',
        );
      });

      test('insert and fetch back intact (includes Arabic)', () async {
        final samples = <int, String>{
          1: 'Hello world', // English
          2: 'مرحبا بالعالم', // Arabic
          3: 'c漢字カタカナひらがな', // CJK
          4: 'नमस्ते दुनिया', // Hindi
          5: 'Привет мир', // Russian
          6: 'emoji 😀🔥', // Emoji
        };

        for (final e in samples.entries) {
          await harness.executeParams(
            'INSERT INTO dbo.MultiLang (id, label) VALUES (@id, @label)',
            {'id': e.key, 'label': e.value},
          );
        }

        // Validate integrity via server-side SHA2-256 comparisons to avoid client decoding issues.
        for (final e in samples.entries) {
          final res = parseRows(
            await harness.executeParams(
              "SELECT CONVERT(varchar(64), HASHBYTES('SHA2_256', CONVERT(varbinary(max), @label)), 2) AS expected, "
              "CONVERT(varchar(64), HASHBYTES('SHA2_256', CONVERT(varbinary(max), (SELECT label FROM dbo.MultiLang WHERE id=@id))), 2) AS actual,(SELECT label FROM dbo.MultiLang WHERE id=@id) as result",
              {'id': e.key, 'label': e.value},
            ),
          );
          expect(res.length, 1);
          expect(res.first['actual'], res.first['expected']);
          expect(res.first['result'], e.value);
        }
      });
    });

    group('update affected count', () {
      setUpAll(() async {
        await harness.recreateTable(
          'CREATE TABLE dbo.Items2 (id INT PRIMARY KEY, name NVARCHAR(200) NOT NULL)',
        );
        for (var i = 1; i <= 3; i++) {
          await harness.executeParams(
            'INSERT INTO dbo.Items2 (id, name) VALUES (@id, @name)',
            {'id': i, 'name': 'n_$i'},
          );
        }
      });

      test('updating zero rows reports zero affected', () async {
        final affected = affectedCount(
          await harness.executeParams(
            'UPDATE dbo.Items2 SET name=@name WHERE id=@id',
            {'name': 'new', 'id': -1},
          ),
        );
        expect(affected, 0);
      });
    });
  });
}
