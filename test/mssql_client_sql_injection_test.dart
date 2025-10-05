import 'package:test/test.dart';
import 'test_utils.dart';

void main() {
  group('MssqlClient - SQL Injection Security', () {
    final harness = TempDbHarness();

    setUpAll(() async {
      await harness.init();
    });

    tearDownAll(() async {
      await harness.dispose();
    });

    group('easy', () {
      setUpAll(() async {
        await harness.recreateTable('CREATE TABLE dbo.Items (id INT PRIMARY KEY, name NVARCHAR(600) COLLATE Latin1_General_100_CI_AS_SC NOT NULL)');
      });

      // 50 cases: quotes, unicode, whitespace, brackets, semicolons as data
      final basePayloads = <String>[
        "O'Hara",
        'plain',
        'with spaces',
        'newline\ninside',
        'tab\tinside',
        'unicode café',
        'emoji 😀',
        'brackets [x]',
        'parens (x)',
        'comma,here',
        'semi;colon',
        'double"quote',
        r"path C:\\Temp\\file.txt",
        'json {"a":1}',
        'xml <tag>v</tag>',
        'percent 100%',
        'underscore_value',
        'dash-value',
        'colon:value',
        'pipe|value',
        'tilde~value',
        'backtick`value',
        'caret^value',
        'multi ;; ;;',
        'quotes "double" and \'single\'',
        'braces {curly}',
        'slashes / \\,',
        'accents naïve façade',
        'cjk 漢字カタカナひらがな',
        'rtl العربية',
        'long '.padRight(200, 'x'),
      ];
      final easyPayloads = [
        for (var i = 0; i < 70; i++) "val_'$i'; -- safe $i",
        ...basePayloads,
      ]; // 70 + ~30 = ~100

      for (var i = 0; i < easyPayloads.length; i++) {
        final id = 1000 + i;
        final payload = easyPayloads[i];
        test('easy case #$i stores literal safely', () async {
          await harness.executeParams('INSERT INTO dbo.Items (id, name) VALUES (@id, @name)', {'id': id, 'name': payload});
          // await Future.delayed(const Duration(seconds: 20));
          final rows = parseRows(await harness.query('SELECT name FROM dbo.Items WHERE id=$id'));
          expect(rows.single['name'], payload);
        });
      }
    });

    group('moderate', () {
      setUpAll(() async {
        await harness.recreateTable('CREATE TABLE dbo.Items (id INT PRIMARY KEY, name NVARCHAR(400) NOT NULL)');
      });

      // 50 cases: common SQLi literals inserted as data
      final patterns = <String>[
        "'; DROP TABLE dbo.Items; --",
        "'; EXEC xp_cmdshell('dir'); --",
        "' OR '1'='1",
        "' OR 1=1 --",
        "') OR ('a'='a",
        "' UNION SELECT NULL --",
        "' ; WAITFOR DELAY '0:0:1' --",
        '" OR "1"="1',
        '%%27 OR 1=1 --',
        'name%;--',
      ];
  final moderatePayloads = [for (var k = 0; k < 10; k++) ...patterns.map((p) => '$p [$k]')]; // 100

      for (var i = 0; i < moderatePayloads.length; i++) {
        final id = 2000 + i;
        final payload = moderatePayloads[i];
        test('moderate case #$i literal injection not executed', () async {
          await harness.executeParams('INSERT INTO dbo.Items (id, name) VALUES (@id, @name)', {'id': id, 'name': payload});
          // Table must still exist and row must contain literal payload
          final t = parseRows(await harness.query(
              "SELECT COUNT(*) AS cnt FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA='dbo' AND TABLE_NAME='Items'"));
          expect(t.first['cnt'], 1);
          final rows = parseRows(await harness.query('SELECT name FROM dbo.Items WHERE id=$id'));
          expect(rows.length, 1, reason: 'expected row for id=$id');
          expect(rows.first['name'], payload);
        });
      }
    });

    group('hard', () {
      setUpAll(() async {
        await harness.recreateTable('CREATE TABLE dbo.Items (id INT PRIMARY KEY, name NVARCHAR(400) NOT NULL)');
        // Seed deterministic data
        for (var i = 1; i <= 5; i++) {
          await harness.executeParams('INSERT INTO dbo.Items (id, name) VALUES (@id, @name)', {'id': i, 'name': 'name_$i'});
        }
      });

      // 50 cases: WHERE clause attempts should not match any rows
      final whereAttempts = [
        for (var i = 0; i < 50; i++) "name_1' OR 1=1 -- [$i]",
        for (var i = 0; i < 50; i++) "name_2') OR ('a'='a [$i]",
      ]; // 100
      for (var i = 0; i < whereAttempts.length; i++) {
        final inject = whereAttempts[i];
        test('hard case #$i WHERE injection yields zero rows', () async {
          final rows = parseRows(await harness.executeParams(
              'SELECT id, name FROM dbo.Items WHERE name=@name ORDER BY id', {'name': inject}));
          expect(rows.length, 0);
        });
      }
    });

    group('complex', () {
      setUpAll(() async {
        await harness.recreateTable('CREATE TABLE dbo.Items (id INT PRIMARY KEY, name NVARCHAR(400) NOT NULL)');
        await harness.executeParams('INSERT INTO dbo.Items (id, name) VALUES (@id, @name)', {'id': 1, 'name': 'alpha'});
      });

      // 50 cases: stacked statements and time-based attempts treated as data only
      final complexPatterns = <String>[
        "x'; DROP DATABASE tempdb; --",
        "x'; CREATE LOGIN bad WITH PASSWORD='x'; --",
        "x'; EXEC ('sp_who'); --",
        "x'; WAITFOR DELAY '0:0:1'; --",
        "x'; BEGIN TRAN; ROLLBACK; --",
        "x'; SELECT @@version; --",
        ") ; DROP TABLE dbo.Items; --",
        "'; IF (1=1) SELECT 1; --",
        "'; RAISERROR('boom',16,1); --",
        "'; DECLARE @x INT; SET @x=1; --",
      ];
  final complexPayloads = [for (var k = 0; k < 10; k++) ...complexPatterns.map((p) => '$p [$k]')]; // 100

      for (var i = 0; i < complexPayloads.length; i++) {
        final payload = complexPayloads[i];
        test('complex case #$i stacked statements treated as data', () async {
          await harness.executeParams('UPDATE dbo.Items SET name=@name WHERE id=@id', {'id': 1, 'name': payload});
          final t = parseRows(await harness.query(
              "SELECT COUNT(*) AS cnt FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA='dbo' AND TABLE_NAME='Items'"));
          expect(t.first['cnt'], 1);
          final rows = parseRows(await harness.query('SELECT id, name FROM dbo.Items WHERE id=1'));
          expect(rows.length, 1, reason: 'expected row for id=1');
          expect(rows.first['name'], payload);
        });
      }
    });
  });
}
