import 'dart:typed_data';

import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  group('MssqlConnection Modes - Functional', () {
    test('easy: simple insert/select', () async {
      await runWithClientAndTempDb((client, db) async {
        await client.writeData('''
          CREATE TABLE dbo.Items (
            id INT NOT NULL PRIMARY KEY,
            name NVARCHAR(100) NOT NULL
          )
        ''');

        await client.writeDataWithParams(
          'INSERT INTO dbo.Items (id, name) VALUES (@id, @name)',
          {'id': 1, 'name': 'hello'},
        );
        final rowsJson = await client.getData('SELECT id, name FROM dbo.Items');
        final rows = parseRows(rowsJson);
        expect(rows.length, 1);
        expect(rows.first['id'], 1);
        expect(rows.first['name'], 'hello');
      });
    });

    test('moderate: multiple types incl NULL and varbinary', () async {
      await runWithClientAndTempDb((client, db) async {
        await client.writeData('''
          CREATE TABLE dbo.Items (
            id INT NOT NULL PRIMARY KEY,
            name NVARCHAR(100) NOT NULL,
            created DATETIME NULL,
            flag BIT NULL,
            data VARBINARY(MAX) NULL
          )
        ''');

        await client.writeDataWithParams(
          'INSERT INTO dbo.Items (id, name, created, flag, data) VALUES (@id, @name, @created, @flag, @data)',
          {
            'id': 1,
            'name': 'hello',
            'created': DateTime.now(),
            'flag': true,
            'data': Uint8List.fromList([1, 2, 3, 4]),
          },
        );
        final rowsJson = await client.getData(
          'SELECT id, name, flag, DATALENGTH(data) AS data_len FROM dbo.Items',
        );
        final rows = parseRows(rowsJson);
        expect(rows.length, 1);
        expect(rows.first['id'], 1);
        expect(rows.first['name'], 'hello');
        expect(rows.first['flag'], true);
        expect(rows.first['data_len'], 4);
      });
    });

    test('hard: multi-row insert and filtered select', () async {
      await runWithClientAndTempDb((client, db) async {
        await client.writeData(
          'CREATE TABLE dbo.Items (id INT PRIMARY KEY, name NVARCHAR(100) NOT NULL)',
        );
        for (var i = 1; i <= 5; i++) {
          await client.writeDataWithParams(
            'INSERT INTO dbo.Items (id, name) VALUES (@id, @name)',
            {'id': i, 'name': 'name_$i'},
          );
        }
        final rowsJson = await client.getData(
          'SELECT id, name FROM dbo.Items WHERE name LIKE \u0027name_%\u0027 ORDER BY id',
        );
        final rows = parseRows(rowsJson);
        expect(rows.length, 5);
        expect(rows.first['id'], 1);
        expect(rows.last['id'], 5);
      });
    });

    test('complex: mixed operations and verification', () async {
      await runWithClientAndTempDb((client, db) async {
        await client.writeData(
          'CREATE TABLE dbo.Items (id INT PRIMARY KEY, name NVARCHAR(100) NOT NULL, flag BIT NULL)',
        );
        // Insert two
        await client.writeDataWithParams(
          'INSERT INTO dbo.Items (id, name, flag) VALUES (@id, @name, @flag)',
          {'id': 1, 'name': 'alpha', 'flag': true},
        );
        await client.writeDataWithParams(
          'INSERT INTO dbo.Items (id, name, flag) VALUES (@id, @name, @flag)',
          {'id': 2, 'name': 'beta', 'flag': false},
        );
        // Update one
        await client.writeDataWithParams(
          'UPDATE dbo.Items SET flag=@flag WHERE id=@id',
          {'id': 2, 'flag': true},
        );
        // Select check
        final rowsJson = await client.getData(
          'SELECT COUNT(*) AS cnt, SUM(CASE WHEN flag=1 THEN 1 ELSE 0 END) AS flagged FROM dbo.Items',
        );
        final rows = parseRows(rowsJson);
        expect(rows.first['cnt'], 2);
        expect(rows.first['flagged'], 2);
      });
    });
  });
  group('MssqlConnection Modes - Functional (bulk)', () {
    final harness = TempDbHarness();
    setUpAll(() async {
      await harness.init();
    });
    tearDownAll(() async {
      await harness.dispose();
    });

    group('easy', () {
      setUpAll(() async {
        await harness.recreateTable(
          'CREATE TABLE dbo.Items (id INT PRIMARY KEY, name NVARCHAR(100) NOT NULL)',
        );
      });
      for (var i = 1; i <= 50; i++) {
        final id = 10000 + i;
        test('easy bulk case #$i insert/select', () async {
          await harness.executeParams(
            'INSERT INTO dbo.Items (id, name) VALUES (@id, @name)',
            {'id': id, 'name': 'hello_$i'},
          );
          final rows = parseRows(
            await harness.query('SELECT id, name FROM dbo.Items WHERE id=$id'),
          );
          expect(rows.single['id'], id);
          expect(rows.single['name'], 'hello_$i');
        });
      }
    });

    group('moderate', () {
      setUpAll(() async {
        await harness.recreateTable(
          'CREATE TABLE dbo.Items (id INT PRIMARY KEY, name NVARCHAR(100) NOT NULL, created DATETIME NULL, flag BIT NULL, data VARBINARY(MAX) NULL)',
        );
      });
      for (var i = 0; i < 50; i++) {
        final id = 20000 + i;
        final created = i % 3 == 0
            ? null
            : DateTime.fromMillisecondsSinceEpoch(1700000000000 + i * 1000);
        final flag = i % 2 == 0;
        final dataLen = [1, 2, 4, 8, 16, 24, 32, 48, 64, 128][i % 10];
        final data = Uint8List.fromList(
          List.generate(dataLen, (j) => j & 0xFF),
        );
        test('moderate bulk case #$i types incl NULL/varbinary', () async {
          await harness.executeParams(
            'INSERT INTO dbo.Items (id, name, created, flag, data) VALUES (@id, @name, @created, @flag, @data)',
            {
              'id': id,
              'name': 'name_$i',
              'created': created,
              'flag': flag,
              'data': data,
            },
          );
          final rows = parseRows(
            await harness.query(
              'SELECT id, name, flag, DATALENGTH(data) AS data_len FROM dbo.Items WHERE id=$id',
            ),
          );
          expect(rows.single['id'], id);
          expect(rows.single['name'], 'name_$i');
          expect(rows.single['flag'], flag);
          expect(rows.single['data_len'], dataLen);
        });
      }
    });

    group('hard', () {
      setUp(() async {
        await harness.recreateTable(
          'CREATE TABLE dbo.Items (id INT PRIMARY KEY, name NVARCHAR(100) NOT NULL)',
        );
      });
      for (var i = 0; i < 50; i++) {
        test('hard bulk case #$i multi-row + filtered select', () async {
          for (var j = 1; j <= 12; j++) {
            await harness.executeParams(
              'INSERT INTO dbo.Items (id, name) VALUES (@id, @name)',
              {'id': i * 100 + j, 'name': 'p${i}_$j'},
            );
          }
          final rows = parseRows(
            await harness.query(
              "SELECT id, name FROM dbo.Items WHERE name LIKE 'p${i}_%' ORDER BY id",
            ),
          );
          expect(rows.length, 12);
          expect(rows.first['name'], 'p${i}_1');
          expect(rows.last['name'], 'p${i}_12');
        });
      }
    });

    group('complex', () {
      setUp(() async {
        await harness.recreateTable(
          'CREATE TABLE dbo.Items (id INT PRIMARY KEY, name NVARCHAR(100) NOT NULL, flag BIT NULL)',
        );
        await harness.executeParams(
          'INSERT INTO dbo.Items (id, name, flag) VALUES (@id, @name, @flag)',
          {'id': 1, 'name': 'alpha', 'flag': true},
        );
        await harness.executeParams(
          'INSERT INTO dbo.Items (id, name, flag) VALUES (@id, @name, @flag)',
          {'id': 2, 'name': 'beta', 'flag': false},
        );
      });
      for (var i = 0; i < 50; i++) {
        test('complex bulk case #$i mixed ops', () async {
          final toggle = i % 2 == 0;
          // DML: update flag
          await harness.executeParams(
            'UPDATE dbo.Items SET flag=@flag WHERE id=@id',
            {'id': 2, 'flag': toggle},
          );

          // DDL: add a column and create/drop index per test
          await harness.execute(
            'ALTER TABLE dbo.Items ADD notes NVARCHAR(50) NULL',
          );
          final note = 'note_$i';
          await harness.executeParams(
            'UPDATE dbo.Items SET notes=@n WHERE id=@id',
            {'id': 1, 'n': note},
          );
          final ixName = 'IX_Items_name_$i';
          await harness.execute('CREATE INDEX [$ixName] ON dbo.Items(name)');

          // DML: delete and reinsert row 2 to test DELETE/INSERT
          await harness.execute('DELETE FROM dbo.Items WHERE id=2');
          await harness.executeParams(
            'INSERT INTO dbo.Items (id, name, flag, notes) VALUES (@id, @name, @flag, @notes)',
            {'id': 2, 'name': 'beta', 'flag': toggle, 'notes': 'ok'},
          );

          // Verify state
          final rows = parseRows(
            await harness.query(
              'SELECT COUNT(*) AS cnt, SUM(CASE WHEN flag=1 THEN 1 ELSE 0 END) AS flagged FROM dbo.Items',
            ),
          );
          expect(rows.single['cnt'], 2);
          expect(rows.single['flagged'], toggle ? 2 : 1);
          final n = parseRows(
            await harness.query('SELECT notes FROM dbo.Items WHERE id=1'),
          );
          expect(n.single['notes'], note);

          // DDL cleanup: drop index
          await harness.execute('DROP INDEX [$ixName] ON dbo.Items');
          final ix = parseRows(
            await harness.query(
              "SELECT COUNT(*) AS cnt FROM sys.indexes WHERE name='$ixName'",
            ),
          );
          expect(ix.single['cnt'], 0);
        });
      }
    });
  });
}
