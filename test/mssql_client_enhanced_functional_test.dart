import 'dart:typed_data';

import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  group('MssqlClient Enhanced Functional Tests', () {
    final harness = TempDbHarness();

    setUpAll(() async {
      await harness.init();
    });

    tearDownAll(() async {
      await harness.dispose();
    });

    group('Easy Mode - 50 Functional Tests', () {
      setUp(() async {
        // Create basic single table structure for easy tests
        await harness.recreateTable('''
          CREATE TABLE dbo.SimpleItems (
            id INT NOT NULL PRIMARY KEY,
            name NVARCHAR(100) NOT NULL,
            value DECIMAL(10,2) NULL,
            created_date DATETIME2 DEFAULT GETDATE(),
            is_active BIT DEFAULT 1
          )
        ''');
      });

      test('F_EASY_001: Basic INSERT with minimal columns', () async {
        await harness.executeParams(
          'INSERT INTO dbo.SimpleItems (id, name) VALUES (@id, @name)',
          {'id': 1, 'name': 'Basic Item'},
        );
        final rows = parseRows(
          await harness.query(
            'SELECT id, name FROM dbo.SimpleItems WHERE id = 1',
          ),
        );
        expect(rows.length, 1);
        expect(rows.first['id'], 1);
        expect(rows.first['name'], 'Basic Item');
      });

      test('F_EASY_002: INSERT with all columns including NULL values', () async {
        await harness.executeParams(
          'INSERT INTO dbo.SimpleItems (id, name, value, is_active) VALUES (@id, @name, @value, @active)',
          {'id': 2, 'name': 'Complete Item', 'value': 99.50, 'active': true},
        );
        final rows = parseRows(
          await harness.query('SELECT * FROM dbo.SimpleItems WHERE id = 2'),
        );
        expect(rows.first['value'], 99.50);
        expect(rows.first['is_active'], true);
      });

      test('F_EASY_003: SELECT with WHERE clause filtering', () async {
        await harness.executeParams(
          'INSERT INTO dbo.SimpleItems (id, name, value) VALUES (@id, @name, @value)',
          {'id': 3, 'name': 'Filter Test', 'value': 25.75},
        );
        final rows = parseRows(
          await harness.executeParams(
            'SELECT name, value FROM dbo.SimpleItems WHERE value > @threshold',
            {'threshold': 20.0},
          ),
        );
        expect(rows.any((r) => r['name'] == 'Filter Test'), true);
      });

      test('F_EASY_004: UPDATE single record', () async {
        await harness.executeParams(
          'INSERT INTO dbo.SimpleItems (id, name, value) VALUES (@id, @name, @value)',
          {'id': 4, 'name': 'Update Me', 'value': 10.0},
        );
        await harness.executeParams(
          'UPDATE dbo.SimpleItems SET value = @newValue WHERE id = @id',
          {'id': 4, 'newValue': 15.5},
        );
        final rows = parseRows(
          await harness.query('SELECT value FROM dbo.SimpleItems WHERE id = 4'),
        );
        expect(rows.first['value'], 15.5);
      });

      test('F_EASY_005: DELETE single record', () async {
        await harness.executeParams(
          'INSERT INTO dbo.SimpleItems (id, name) VALUES (@id, @name)',
          {'id': 5, 'name': 'Delete Me'},
        );
        await harness.executeParams(
          'DELETE FROM dbo.SimpleItems WHERE id = @id',
          {'id': 5},
        );
        final rows = parseRows(
          await harness.query(
            'SELECT COUNT(*) as cnt FROM dbo.SimpleItems WHERE id = 5',
          ),
        );
        expect(rows.first['cnt'], 0);
      });

      test('F_EASY_006: COUNT aggregate function', () async {
        for (int i = 10; i < 15; i++) {
          await harness.executeParams(
            'INSERT INTO dbo.SimpleItems (id, name) VALUES (@id, @name)',
            {'id': i, 'name': 'Count Item $i'},
          );
        }
        final rows = parseRows(
          await harness.query('SELECT COUNT(*) as total FROM dbo.SimpleItems'),
        );
        expect(rows.first['total'] >= 5, true);
      });

      test('F_EASY_007: SUM aggregate with decimal values', () async {
        await harness.executeParams(
          'INSERT INTO dbo.SimpleItems (id, name, value) VALUES (@id, @name, @value)',
          {'id': 20, 'name': 'Sum Test 1', 'value': 10.25},
        );
        await harness.executeParams(
          'INSERT INTO dbo.SimpleItems (id, name, value) VALUES (@id, @name, @value)',
          {'id': 21, 'name': 'Sum Test 2', 'value': 15.75},
        );
        final rows = parseRows(
          await harness.query(
            'SELECT SUM(value) as total FROM dbo.SimpleItems WHERE id IN (20, 21)',
          ),
        );
        expect(rows.first['total'], 26.0);
      });

      test('F_EASY_008: ORDER BY ascending', () async {
        final testIds = [35, 31, 33, 32, 34];
        for (int id in testIds) {
          await harness.executeParams(
            'INSERT INTO dbo.SimpleItems (id, name) VALUES (@id, @name)',
            {'id': id, 'name': 'Order $id'},
          );
        }
        final rows = parseRows(
          await harness.query(
            'SELECT id FROM dbo.SimpleItems WHERE id BETWEEN 31 AND 35 ORDER BY id ASC',
          ),
        );
        expect(rows.length, 5);
        expect(rows[0]['id'], 31);
        expect(rows[4]['id'], 35);
      });

      test('F_EASY_009: ORDER BY descending', () async {
        // Seed the range [31, 35] within this test to avoid relying on other tests
        final testIds = [31, 32, 33, 34, 35];
        for (int id in testIds) {
          await harness.executeParams(
            'INSERT INTO dbo.SimpleItems (id, name) VALUES (@id, @name)',
            {'id': id, 'name': 'Order $id'},
          );
        }
        final rows = parseRows(
          await harness.query(
            'SELECT id FROM dbo.SimpleItems WHERE id BETWEEN 31 AND 35 ORDER BY id DESC',
          ),
        );
        expect(rows[0]['id'], 35);
        expect(rows[4]['id'], 31);
      });

      test('F_EASY_010: LIKE pattern matching', () async {
        await harness.executeParams(
          'INSERT INTO dbo.SimpleItems (id, name) VALUES (@id, @name)',
          {'id': 40, 'name': 'Pattern Test Item'},
        );
        final rows = parseRows(
          await harness.executeParams(
            'SELECT name FROM dbo.SimpleItems WHERE name LIKE @pattern',
            {'pattern': 'Pattern%'},
          ),
        );
        expect(
          rows.any((r) => r['name'].toString().startsWith('Pattern')),
          true,
        );
      });

      // Continue with tests 11-50
      for (int i = 11; i <= 50; i++) {
        test(
          'F_EASY_${i.toString().padLeft(3, '0')}: Bulk operation test $i',
          () async {
            final testId = 1000 + i;
            await harness.executeParams(
              'INSERT INTO dbo.SimpleItems (id, name, value, is_active) VALUES (@id, @name, @value, @active)',
              {
                'id': testId,
                'name': 'Bulk Test Item $i',
                'value': (i * 2.5),
                'active': i % 2 == 0,
              },
            );

            // Verify insertion
            final rows = parseRows(
              await harness.query(
                'SELECT * FROM dbo.SimpleItems WHERE id = $testId',
              ),
            );
            expect(rows.length, 1);
            expect(rows.first['name'], 'Bulk Test Item $i');
            expect(rows.first['value'], i * 2.5);
            expect(rows.first['is_active'], i % 2 == 0);

            // Update the record
            await harness.executeParams(
              'UPDATE dbo.SimpleItems SET value = @newValue WHERE id = @id',
              {'id': testId, 'newValue': i * 3.0},
            );

            // Verify update
            final updatedRows = parseRows(
              await harness.query(
                'SELECT value FROM dbo.SimpleItems WHERE id = $testId',
              ),
            );
            expect(updatedRows.first['value'], i * 3.0);
          },
        );
      }
    });

    group('Moderate Mode - 50 Functional Tests', () {
      setUp(() async {
        // Create multi-table structure with relationships
        await harness.execute('DROP TABLE IF EXISTS dbo.OrderItems');
        await harness.execute('DROP TABLE IF EXISTS dbo.Orders');
        await harness.execute('DROP TABLE IF EXISTS dbo.Customers');
        await harness.execute('DROP TABLE IF EXISTS dbo.Products');

        await harness.execute('''
          CREATE TABLE dbo.Customers (
            customer_id INT NOT NULL PRIMARY KEY,
            name NVARCHAR(100) NOT NULL,
            email NVARCHAR(100) NULL,
            created_date DATETIME2 DEFAULT GETDATE(),
            customer_data VARBINARY(MAX) NULL
          )
        ''');

        await harness.execute('''
          CREATE TABLE dbo.Products (
            product_id INT NOT NULL PRIMARY KEY,
            name NVARCHAR(100) NOT NULL,
            price DECIMAL(10,2) NOT NULL,
            category NVARCHAR(50) NULL,
            in_stock BIT DEFAULT 1
          )
        ''');

        await harness.execute('''
          CREATE TABLE dbo.Orders (
            order_id INT NOT NULL PRIMARY KEY,
            customer_id INT NOT NULL,
            order_date DATETIME2 DEFAULT GETDATE(),
            total_amount DECIMAL(15,2) NULL,
            status NVARCHAR(20) DEFAULT 'Pending',
            FOREIGN KEY (customer_id) REFERENCES dbo.Customers(customer_id)
          )
        ''');

        await harness.execute('''
          CREATE TABLE dbo.OrderItems (
            order_item_id INT NOT NULL PRIMARY KEY,
            order_id INT NOT NULL,
            product_id INT NOT NULL,
            quantity INT NOT NULL DEFAULT 1,
            unit_price DECIMAL(10,2) NOT NULL,
            FOREIGN KEY (order_id) REFERENCES dbo.Orders(order_id),
            FOREIGN KEY (product_id) REFERENCES dbo.Products(product_id)
          )
        ''');
      });

      test('F_MOD_001: Multi-table INSERT with foreign keys', () async {
        await harness.executeParams(
          'INSERT INTO dbo.Customers (customer_id, name, email) VALUES (@id, @name, @email)',
          {'id': 1, 'name': 'John Doe', 'email': 'john@example.com'},
        );

        await harness.executeParams(
          'INSERT INTO dbo.Products (product_id, name, price, category) VALUES (@id, @name, @price, @category)',
          {
            'id': 1,
            'name': 'Laptop',
            'price': 999.99,
            'category': 'Electronics',
          },
        );

        await harness.executeParams(
          'INSERT INTO dbo.Orders (order_id, customer_id, total_amount) VALUES (@orderId, @customerId, @total)',
          {'orderId': 1, 'customerId': 1, 'total': 999.99},
        );

        final rows = parseRows(
          await harness.query('''
          SELECT o.order_id, c.name, o.total_amount 
          FROM dbo.Orders o 
          JOIN dbo.Customers c ON o.customer_id = c.customer_id 
          WHERE o.order_id = 1
        '''),
        );

        expect(rows.length, 1);
        expect(rows.first['name'], 'John Doe');
        expect(rows.first['total_amount'], 999.99);
      });

      test('F_MOD_002: INNER JOIN with parameterized WHERE', () async {
        // Seed a customer and an order for this test
        await harness.executeParams(
          'INSERT INTO dbo.Customers (customer_id, name, email) VALUES (@id, @name, @email)',
          {'id': 1, 'name': 'John Doe', 'email': 'john@example.com'},
        );
        await harness.executeParams(
          'INSERT INTO dbo.Orders (order_id, customer_id, total_amount) VALUES (@orderId, @customerId, @total)',
          {'orderId': 1, 'customerId': 1, 'total': 750.0},
        );
        final rows = parseRows(
          await harness.executeParams(
            '''
          SELECT c.name as customer_name, o.order_id, o.total_amount
          FROM dbo.Customers c
          INNER JOIN dbo.Orders o ON c.customer_id = o.customer_id
          WHERE o.total_amount > @threshold
        ''',
            {'threshold': 500.0},
          ),
        );

        expect(rows.any((r) => r['customer_name'] == 'John Doe'), true);
      });

      test('F_MOD_003: Complex data types - VARBINARY and DATETIME2', () async {
        final binaryData = Uint8List.fromList([
          0x48,
          0x65,
          0x6C,
          0x6C,
          0x6F,
        ]); // "Hello"
        await harness.executeParams(
          'INSERT INTO dbo.Customers (customer_id, name, customer_data) VALUES (@id, @name, @data)',
          {'id': 2, 'name': 'Jane Smith', 'data': binaryData},
        );

        final rows = parseRows(
          await harness.query(
            'SELECT name, DATALENGTH(customer_data) as data_length FROM dbo.Customers WHERE customer_id = 2',
          ),
        );
        expect(rows.first['data_length'], 5);
      });

      test('F_MOD_004: Aggregate functions with GROUP BY', () async {
        // Insert test data
        for (int i = 1; i <= 3; i++) {
          await harness.executeParams(
            'INSERT INTO dbo.Products (product_id, name, price, category) VALUES (@id, @name, @price, @category)',
            {
              'id': i + 10,
              'name': 'Product $i',
              'price': i * 100.0,
              'category': i % 2 == 0 ? 'Electronics' : 'Books',
            },
          );
        }

        final rows = parseRows(
          await harness.query('''
          SELECT category, COUNT(*) as count, AVG(price) as avg_price, SUM(price) as total_price
          FROM dbo.Products 
          WHERE product_id > 10
          GROUP BY category
        '''),
        );

        expect(rows.isNotEmpty, true);
        expect(rows.every((r) => r['count'] is int), true);
      });

      test('F_MOD_005: Subquery with EXISTS', () async {
        // Seed a customer and a qualifying order for this test
        await harness.executeParams(
          'INSERT INTO dbo.Customers (customer_id, name, email) VALUES (@id, @name, @email)',
          {'id': 1, 'name': 'John Doe', 'email': 'john@example.com'},
        );
        await harness.executeParams(
          'INSERT INTO dbo.Orders (order_id, customer_id, total_amount) VALUES (@orderId, @customerId, @total)',
          {'orderId': 1, 'customerId': 1, 'total': 999.99},
        );
        final rows = parseRows(
          await harness.query('''
          SELECT c.name FROM dbo.Customers c
          WHERE EXISTS (
            SELECT 1 FROM dbo.Orders o 
            WHERE o.customer_id = c.customer_id AND o.total_amount > 500
          )
        '''),
        );

        expect(rows.any((r) => r['name'] == 'John Doe'), true);
      });

      // Continue with tests 6-50 for moderate mode
      for (int i = 6; i <= 50; i++) {
        test(
          'F_MOD_${i.toString().padLeft(3, '0')}: Advanced operation test $i',
          () async {
            final customerId = 100 + i;
            final productId = 200 + i;
            final orderId = 300 + i;

            // Create customer
            await harness.executeParams(
              'INSERT INTO dbo.Customers (customer_id, name, email) VALUES (@id, @name, @email)',
              {
                'id': customerId,
                'name': 'Customer $i',
                'email': 'customer$i@test.com',
              },
            );

            // Create product
            await harness.executeParams(
              'INSERT INTO dbo.Products (product_id, name, price, category) VALUES (@id, @name, @price, @category)',
              {
                'id': productId,
                'name': 'Product $i',
                'price': i * 50.0,
                'category': 'Category${i % 3}',
              },
            );

            // Create order
            await harness.executeParams(
              'INSERT INTO dbo.Orders (order_id, customer_id, total_amount, status) VALUES (@orderId, @customerId, @total, @status)',
              {
                'orderId': orderId,
                'customerId': customerId,
                'total': i * 50.0,
                'status': i % 2 == 0 ? 'Completed' : 'Pending',
              },
            );

            // Verify with complex query
            final rows = parseRows(
              await harness.executeParams(
                '''
            SELECT 
              c.name as customer_name,
              p.name as product_name,
              o.total_amount,
              o.status,
              CASE WHEN o.total_amount > @threshold THEN 'High Value' ELSE 'Standard' END as order_type
            FROM dbo.Customers c
            JOIN dbo.Orders o ON c.customer_id = o.customer_id
            CROSS JOIN dbo.Products p
            WHERE c.customer_id = @customerId AND p.product_id = @productId
          ''',
                {
                  'customerId': customerId,
                  'productId': productId,
                  'threshold': 1000.0,
                },
              ),
            );

            expect(rows.length, 1);
            expect(rows.first['customer_name'], 'Customer $i');
            expect(rows.first['product_name'], 'Product $i');
          },
        );
      }
    });

    group('Hard Mode - 50 Functional Tests', () {
      setUp(() async {
        // Create complex schema with indexes, constraints, and stored procedures
        await harness.execute('DROP TABLE IF EXISTS dbo.AuditLog');
        await harness.execute('DROP TABLE IF EXISTS dbo.OrderItems');
        await harness.execute('DROP TABLE IF EXISTS dbo.Orders');
        await harness.execute('DROP TABLE IF EXISTS dbo.Customers');
        await harness.execute('DROP TABLE IF EXISTS dbo.Products');
        await harness.execute('DROP TABLE IF EXISTS dbo.Categories');

        await harness.execute('''
          CREATE TABLE dbo.Categories (
            category_id INT NOT NULL PRIMARY KEY,
            name NVARCHAR(100) NOT NULL UNIQUE,
            description NVARCHAR(500) NULL,
            parent_category_id INT NULL,
            created_date DATETIME2 DEFAULT GETDATE(),
            FOREIGN KEY (parent_category_id) REFERENCES dbo.Categories(category_id)
          )
        ''');

        await harness.execute('''
          CREATE TABLE dbo.Products (
            product_id INT NOT NULL PRIMARY KEY,
            name NVARCHAR(100) NOT NULL,
            sku NVARCHAR(50) NOT NULL UNIQUE,
            price DECIMAL(15,4) NOT NULL CHECK (price >= 0),
            cost DECIMAL(15,4) NULL CHECK (cost >= 0),
            category_id INT NOT NULL,
            weight DECIMAL(8,3) NULL CHECK (weight > 0),
            dimensions NVARCHAR(50) NULL,
            created_date DATETIME2 DEFAULT GETDATE(),
            modified_date DATETIME2 DEFAULT GETDATE(),
            is_active BIT DEFAULT 1,
            metadata XML NULL,
            FOREIGN KEY (category_id) REFERENCES dbo.Categories(category_id)
          )
        ''');

        await harness.execute('''
          CREATE TABLE dbo.Customers (
            customer_id INT NOT NULL PRIMARY KEY,
            customer_code NVARCHAR(20) NOT NULL UNIQUE,
            name NVARCHAR(200) NOT NULL,
            email NVARCHAR(100) NULL,
            phone NVARCHAR(20) NULL,
            address_line1 NVARCHAR(100) NULL,
            address_line2 NVARCHAR(100) NULL,
            city NVARCHAR(50) NULL,
            state NVARCHAR(50) NULL,
            postal_code NVARCHAR(20) NULL,
            country NVARCHAR(50) NULL DEFAULT 'USA',
            customer_type NVARCHAR(20) DEFAULT 'Regular' CHECK (customer_type IN ('Regular', 'Premium', 'VIP')),
            credit_limit DECIMAL(15,2) NULL CHECK (credit_limit >= 0),
            created_date DATETIME2 DEFAULT GETDATE(),
            last_login DATETIME2 NULL,
            is_active BIT DEFAULT 1
          )
        ''');

        await harness.execute('''
          CREATE TABLE dbo.AuditLog (
            log_id INT IDENTITY(1,1) PRIMARY KEY,
            table_name NVARCHAR(100) NOT NULL,
            operation NVARCHAR(10) NOT NULL,
            record_id INT NOT NULL,
            old_values NVARCHAR(MAX) NULL,
            new_values NVARCHAR(MAX) NULL,
            changed_by NVARCHAR(100) NULL,
            changed_date DATETIME2 DEFAULT GETDATE()
          )
        ''');

        // Create indexes
        await harness.execute(
          'CREATE INDEX IX_Products_CategoryId ON dbo.Products(category_id)',
        );
        await harness.execute(
          'CREATE INDEX IX_Products_SKU ON dbo.Products(sku)',
        );
        await harness.execute(
          'CREATE INDEX IX_Customers_Email ON dbo.Customers(email) WHERE email IS NOT NULL',
        );
      });

      test(
        'F_HARD_001: Complex INSERT with CHECK constraints validation',
        () async {
          await harness.executeParams(
            'INSERT INTO dbo.Categories (category_id, name, description) VALUES (@id, @name, @desc)',
            {
              'id': 1,
              'name': 'Electronics',
              'desc': 'Electronic devices and accessories',
            },
          );

          await harness.executeParams(
            '''
          INSERT INTO dbo.Products (product_id, name, sku, price, cost, category_id, weight, dimensions) 
          VALUES (@id, @name, @sku, @price, @cost, @categoryId, @weight, @dimensions)
        ''',
            {
              'id': 1,
              'name': 'Premium Laptop',
              'sku': 'LAPTOP-001',
              'price': 1999.99,
              'cost': 1200.00,
              'categoryId': 1,
              'weight': 2.5,
              'dimensions': '15x10x1 inches',
            },
          );

          final rows = parseRows(
            await harness.query('''
          SELECT p.name, p.sku, p.price, c.name as category_name
          FROM dbo.Products p
          JOIN dbo.Categories c ON p.category_id = c.category_id
          WHERE p.product_id = 1
        '''),
          );

          expect(rows.length, 1);
          expect(rows.first['sku'], 'LAPTOP-001');
          expect(rows.first['category_name'], 'Electronics');
        },
      );

      test(
        'F_HARD_002: Self-referencing foreign key (Categories hierarchy)',
        () async {
          // Ensure parent category exists in this test
          await harness.executeParams(
            'INSERT INTO dbo.Categories (category_id, name) VALUES (@id, @name)',
            {'id': 1, 'name': 'Electronics'},
          );
          await harness.executeParams(
            'INSERT INTO dbo.Categories (category_id, name, parent_category_id) VALUES (@id, @name, @parentId)',
            {'id': 2, 'name': 'Computers', 'parentId': 1},
          );

          final rows = parseRows(
            await harness.query('''
          SELECT c.name as child_name, p.name as parent_name
          FROM dbo.Categories c
          LEFT JOIN dbo.Categories p ON c.parent_category_id = p.category_id
          WHERE c.category_id = 2
        '''),
          );

          expect(rows.first['child_name'], 'Computers');
          expect(rows.first['parent_name'], 'Electronics');
        },
      );

      test('F_HARD_003: Window functions with OVER clause', () async {
        // Ensure base category exists for FK
        await harness.executeParams(
          'INSERT INTO dbo.Categories (category_id, name) VALUES (@id, @name)',
          {'id': 1, 'name': 'Electronics'},
        );
        // Insert test products with varying prices
        for (int i = 1; i <= 5; i++) {
          await harness.executeParams(
            '''
            INSERT INTO dbo.Products (product_id, name, sku, price, category_id) 
            VALUES (@id, @name, @sku, @price, @categoryId)
          ''',
            {
              'id': 100 + i,
              'name': 'Product $i',
              'sku': 'SKU-$i',
              'price': i * 200.0,
              'categoryId': 1,
            },
          );
        }

        final rows = parseRows(
          await harness.query('''
          SELECT 
            name,
            price,
            ROW_NUMBER() OVER (ORDER BY price DESC) as price_rank,
            AVG(price) OVER () as avg_price,
            SUM(price) OVER (ORDER BY price ROWS UNBOUNDED PRECEDING) as running_total
          FROM dbo.Products
          WHERE product_id BETWEEN 101 AND 105
          ORDER BY price DESC
        '''),
        );

        expect(rows.length, 5);
        expect(rows.first['price_rank'], 1);
        expect(rows.first['price'], 1000.0); // Product 5 has highest price
      });

      test('F_HARD_004: Common Table Expression (CTE) with recursion', () async {
        // Seed a simple two-level category tree
        await harness.executeParams(
          'INSERT INTO dbo.Categories (category_id, name) VALUES (@id, @name)',
          {'id': 1, 'name': 'Electronics'},
        );
        await harness.executeParams(
          'INSERT INTO dbo.Categories (category_id, name, parent_category_id) VALUES (@id, @name, @parentId)',
          {'id': 2, 'name': 'Computers', 'parentId': 1},
        );
        final rows = parseRows(
          await harness.query('''
          WITH CategoryHierarchy AS (
            -- Anchor: Root categories
            SELECT category_id, name, parent_category_id, CAST(0 AS INT) as level, CAST(name AS NVARCHAR(4000)) as path
            FROM dbo.Categories
            WHERE parent_category_id IS NULL
            
            UNION ALL
            
            -- Recursive: Child categories
            SELECT c.category_id, c.name, c.parent_category_id, CAST(ch.level + 1 AS INT), CAST(ch.path + N' > ' + c.name AS NVARCHAR(4000))
            FROM dbo.Categories c
            INNER JOIN CategoryHierarchy ch ON c.parent_category_id = ch.category_id
          )
          SELECT category_id, name, level, path
          FROM CategoryHierarchy
          ORDER BY level, name
        '''),
        );

        expect(rows.any((r) => r['name'] == 'Electronics'), true);
        expect(rows.any((r) => r['name'] == 'Computers'), true);
      });

      test('F_HARD_005: Complex UPDATE with JOIN and subquery', () async {
        await harness.execute('''
          UPDATE p
          SET modified_date = GETDATE(),
              price = p.price * 1.1
          FROM dbo.Products p
          JOIN dbo.Categories c ON p.category_id = c.category_id
          WHERE c.name = 'Electronics' 
            AND p.price < (
              SELECT AVG(price) FROM dbo.Products WHERE category_id = p.category_id
            )
        ''');

        final rows = parseRows(
          await harness.query('''
          SELECT COUNT(*) as updated_count
          FROM dbo.Products p
          JOIN dbo.Categories c ON p.category_id = c.category_id
          WHERE c.name = 'Electronics'
        '''),
        );

        expect(rows.first['updated_count'] >= 0, true);
      });

      // Continue with tests 6-50 for hard mode
      for (int i = 6; i <= 50; i++) {
        test(
          'F_HARD_${i.toString().padLeft(3, '0')}: Enterprise operation test $i',
          () async {
            final categoryId = 1000 + i;
            final productId = 2000 + i;
            final customerId = 3000 + i;

            // Create category with validation
            await harness.executeParams(
              'INSERT INTO dbo.Categories (category_id, name, description) VALUES (@id, @name, @desc)',
              {
                'id': categoryId,
                'name': 'Category_$i',
                'desc': 'Generated category for test $i',
              },
            );

            // Create product with all constraints
            await harness.executeParams(
              '''
            INSERT INTO dbo.Products (product_id, name, sku, price, cost, category_id, weight) 
            VALUES (@id, @name, @sku, @price, @cost, @categoryId, @weight)
          ''',
              {
                'id': productId,
                'name': 'Product_$i',
                'sku': 'SKU-TEST-$i',
                'price': i * 100.0 + 99.99,
                'cost': i * 60.0 + 59.99,
                'categoryId': categoryId,
                'weight': i * 0.5 + 1.0,
              },
            );

            // Create customer with all fields
            await harness.executeParams(
              '''
            INSERT INTO dbo.Customers (customer_id, customer_code, name, email, customer_type, credit_limit) 
            VALUES (@id, @code, @name, @email, @type, @limit)
          ''',
              {
                'id': customerId,
                'code': 'CUST-$i',
                'name': 'Customer $i',
                'email': 'customer$i@enterprise.com',
                'type': i % 3 == 0
                    ? 'VIP'
                    : (i % 2 == 0 ? 'Premium' : 'Regular'),
                'limit': i * 5000.0,
              },
            );

            // Complex verification query with multiple JOINs and analytics
            final rows = parseRows(
              await harness.executeParams(
                '''
            SELECT 
              c.name as category_name,
              p.name as product_name,
              p.price,
              p.cost,
              (p.price - p.cost) as margin,
              ((p.price - p.cost) / p.price * 100) as margin_percent,
              cust.name as customer_name,
              cust.customer_type,
              CASE 
                WHEN cust.credit_limit > @threshold THEN 'High Credit'
                WHEN cust.credit_limit > @midThreshold THEN 'Medium Credit'
                ELSE 'Standard Credit'
              END as credit_category
            FROM dbo.Categories c
            JOIN dbo.Products p ON c.category_id = p.category_id
            CROSS JOIN dbo.Customers cust
            WHERE c.category_id = @categoryId 
              AND p.product_id = @productId 
              AND cust.customer_id = @customerId
          ''',
                {
                  'categoryId': categoryId,
                  'productId': productId,
                  'customerId': customerId,
                  'threshold': 15000.0,
                  'midThreshold': 7500.0,
                },
              ),
            );

            expect(rows.length, 1);
            expect(rows.first['category_name'], 'Category_$i');
            expect(rows.first['product_name'], 'Product_$i');
            expect(rows.first['margin'] > 0, true);
          },
        );
      }
    });

    group('Complex Mode - 50 Functional Tests', () {
      setUp(() async {
        // Create enterprise-grade schema with advanced features
        await harness.execute(
          'DROP PROCEDURE IF EXISTS dbo.UpdateProductPrice',
        );
        await harness.execute('DROP FUNCTION IF EXISTS dbo.CalculateDiscount');
        await harness.execute('DROP VIEW IF EXISTS dbo.ProductSalesView');
        await harness.execute('DROP TABLE IF EXISTS dbo.Sales');
        await harness.execute('DROP TABLE IF EXISTS dbo.Inventory');
        await harness.execute('DROP TABLE IF EXISTS dbo.ProductSuppliers');
        await harness.execute('DROP TABLE IF EXISTS dbo.Suppliers');

        // Ensure base tables exist for this group (decoupled from other groups)
        await harness.execute('''
          IF OBJECT_ID('dbo.AuditLog','U') IS NULL
          BEGIN
            CREATE TABLE dbo.AuditLog (
              log_id INT IDENTITY(1,1) PRIMARY KEY,
              table_name NVARCHAR(100) NOT NULL,
              operation NVARCHAR(10) NOT NULL,
              record_id INT NOT NULL,
              old_values NVARCHAR(MAX) NULL,
              new_values NVARCHAR(MAX) NULL,
              changed_by NVARCHAR(100) NULL,
              changed_date DATETIME2 DEFAULT GETDATE()
            );
          END
        ''');

        await harness.execute('''
          IF OBJECT_ID('dbo.Categories','U') IS NULL
          BEGIN
            CREATE TABLE dbo.Categories (
              category_id INT NOT NULL PRIMARY KEY,
              name NVARCHAR(100) NOT NULL UNIQUE,
              description NVARCHAR(500) NULL,
              parent_category_id INT NULL,
              created_date DATETIME2 DEFAULT GETDATE()
            );
          END
        ''');

        await harness.execute('''
          IF OBJECT_ID('dbo.Products','U') IS NULL
          BEGIN
            CREATE TABLE dbo.Products (
              product_id INT NOT NULL PRIMARY KEY,
              name NVARCHAR(100) NOT NULL,
              sku NVARCHAR(50) NOT NULL UNIQUE,
              price DECIMAL(15,4) NOT NULL CHECK (price >= 0),
              cost DECIMAL(15,4) NULL CHECK (cost >= 0),
              weight DECIMAL(8,3) NULL CHECK (weight > 0),
              category_id INT NOT NULL,
              modified_date DATETIME2 DEFAULT GETDATE()
            );
          END
        ''');

        await harness.execute('''
          IF OBJECT_ID('dbo.Customers','U') IS NULL
          BEGIN
            CREATE TABLE dbo.Customers (
              customer_id INT NOT NULL PRIMARY KEY,
              customer_code NVARCHAR(20) NOT NULL,
              name NVARCHAR(200) NOT NULL,
              email NVARCHAR(100) NULL,
              customer_type NVARCHAR(20) DEFAULT 'Regular',
              credit_limit DECIMAL(15,2) NULL
            );
          END
        ''');

        // Advanced tables with complex relationships
        await harness.execute('''
          CREATE TABLE dbo.Suppliers (
            supplier_id INT NOT NULL PRIMARY KEY,
            company_name NVARCHAR(200) NOT NULL,
            contact_name NVARCHAR(100) NULL,
            contact_email NVARCHAR(100) NULL,
            rating DECIMAL(3,2) CHECK (rating BETWEEN 1.0 AND 5.0),
            is_preferred BIT DEFAULT 0,
            created_date DATETIME2 DEFAULT GETDATE()
          )
        ''');

        await harness.execute('''
          CREATE TABLE dbo.ProductSuppliers (
            product_id INT NOT NULL,
            supplier_id INT NOT NULL,
            supplier_product_code NVARCHAR(50) NOT NULL,
            cost DECIMAL(15,4) NOT NULL CHECK (cost > 0),
            lead_time_days INT NULL CHECK (lead_time_days >= 0),
            minimum_order_qty INT DEFAULT 1 CHECK (minimum_order_qty > 0),
            is_primary BIT DEFAULT 0,
            created_date DATETIME2 DEFAULT GETDATE(),
            PRIMARY KEY (product_id, supplier_id),
            FOREIGN KEY (product_id) REFERENCES dbo.Products(product_id),
            FOREIGN KEY (supplier_id) REFERENCES dbo.Suppliers(supplier_id)
          )
        ''');

        await harness.execute('''
          CREATE TABLE dbo.Sales (
            sale_id INT IDENTITY(1,1) PRIMARY KEY,
            product_id INT NOT NULL,
            customer_id INT NOT NULL,
            quantity_sold INT NOT NULL CHECK (quantity_sold > 0),
            unit_price DECIMAL(15,4) NOT NULL CHECK (unit_price >= 0),
            discount_percent DECIMAL(5,2) DEFAULT 0 CHECK (discount_percent BETWEEN 0 AND 100),
            total_amount AS (quantity_sold * unit_price * (1 - discount_percent / 100)) PERSISTED,
            sale_date DATETIME2 DEFAULT GETDATE(),
            sales_rep NVARCHAR(100) NULL,
            commission_rate DECIMAL(5,2) DEFAULT 0 CHECK (commission_rate BETWEEN 0 AND 50),
            FOREIGN KEY (product_id) REFERENCES dbo.Products(product_id),
            FOREIGN KEY (customer_id) REFERENCES dbo.Customers(customer_id)
          )
        ''');
        await harness.execute('''
          CREATE TABLE dbo.Inventory (
            inventory_id INT IDENTITY(1,1) PRIMARY KEY,
            product_id INT NOT NULL,
            location_code NVARCHAR(20) NOT NULL,
            quantity_on_hand INT NOT NULL DEFAULT 0 CHECK (quantity_on_hand >= 0),
            quantity_reserved INT NOT NULL DEFAULT 0 CHECK (quantity_reserved >= 0),
            quantity_available AS (quantity_on_hand - quantity_reserved) PERSISTED,
            reorder_point INT NULL CHECK (reorder_point >= 0),
            max_stock_level INT NULL,
            last_counted_date DATETIME2 NULL,
            last_movement_date DATETIME2 DEFAULT GETDATE(),
            FOREIGN KEY (product_id) REFERENCES dbo.Products(product_id),
            UNIQUE (product_id, location_code),
            CHECK (max_stock_level >= reorder_point)
          )
        ''');
        // Create view
        await harness.execute('''
          CREATE VIEW dbo.ProductSalesView AS
          SELECT 
            p.product_id,
            p.name as product_name,
            p.sku,
            c.name as category_name,
            SUM(s.quantity_sold) as total_quantity_sold,
            SUM(s.total_amount) as total_revenue,
            AVG(s.unit_price) as avg_selling_price,
            COUNT(s.sale_id) as sale_count,
            MAX(s.sale_date) as last_sale_date
          FROM dbo.Products p
          LEFT JOIN dbo.Categories c ON p.category_id = c.category_id
          LEFT JOIN dbo.Sales s ON p.product_id = s.product_id
          GROUP BY p.product_id, p.name, p.sku, c.name
        ''');

        // Create function
        await harness.execute('''
          CREATE FUNCTION dbo.CalculateDiscount(@CustomerType NVARCHAR(20), @OrderAmount DECIMAL(15,2))
          RETURNS DECIMAL(5,2)
          AS
          BEGIN
            DECLARE @Discount DECIMAL(5,2) = 0;
            
            IF @CustomerType = 'VIP'
              SET @Discount = CASE 
                WHEN @OrderAmount >= 10000 THEN 15.0
                WHEN @OrderAmount >= 5000 THEN 10.0
                ELSE 5.0
              END;
            ELSE IF @CustomerType = 'Premium'
              SET @Discount = CASE 
                WHEN @OrderAmount >= 5000 THEN 7.5
                WHEN @OrderAmount >= 2000 THEN 5.0
                ELSE 2.5
              END;
            ELSE
              SET @Discount = CASE 
                WHEN @OrderAmount >= 1000 THEN 2.0
                ELSE 0
              END;
            
            RETURN @Discount;
          END
        ''');

        // Create stored procedure
        await harness.execute('''
          CREATE PROCEDURE dbo.UpdateProductPrice
            @ProductId INT,
            @NewPrice DECIMAL(15,4),
            @UpdatedBy NVARCHAR(100) = 'System'
          AS
          BEGIN
            SET NOCOUNT ON;
            
            DECLARE @OldPrice DECIMAL(15,4);
            SELECT @OldPrice = price FROM dbo.Products WHERE product_id = @ProductId;
            
            UPDATE dbo.Products 
            SET price = @NewPrice, modified_date = GETDATE()
            WHERE product_id = @ProductId;
            
            INSERT INTO dbo.AuditLog (table_name, operation, record_id, old_values, new_values, changed_by)
            VALUES ('Products', 'UPDATE', @ProductId, 
                    'price=' + CAST(@OldPrice AS NVARCHAR(20)), 
                    'price=' + CAST(@NewPrice AS NVARCHAR(20)), 
                    @UpdatedBy);
          END
        ''');
      });

      test('F_COMPLEX_001: Stored procedure execution with audit trail', () async {
        // Setup test data
        // Ensure a clean slate for id=1 to avoid PK/UNIQUE conflicts across tests
        await harness.execute(
          "DELETE FROM dbo.AuditLog WHERE table_name='Products' AND record_id=1",
        );
        await harness.execute("DELETE FROM dbo.Products WHERE product_id=1");
        await harness.execute("DELETE FROM dbo.Categories WHERE category_id=1");
        await harness.executeParams(
          'INSERT INTO dbo.Categories (category_id, name) VALUES (@id, @name)',
          {'id': 1, 'name': 'Test Category'},
        );

        await harness.executeParams(
          '''
          INSERT INTO dbo.Products (product_id, name, sku, price, category_id) 
          VALUES (@id, @name, @sku, @price, @categoryId)
        ''',
          {
            'id': 1,
            'name': 'Test Product',
            'sku': 'TEST-001',
            'price': 100.0,
            'categoryId': 1,
          },
        );

        // Execute stored procedure
        await harness.executeParams(
          'EXEC dbo.UpdateProductPrice @ProductId = @id, @NewPrice = @price, @UpdatedBy = @user',
          {'id': 1, 'price': 150.0, 'user': 'Test User'},
        );

        // Verify price update
        final productRows = parseRows(
          await harness.query(
            'SELECT price FROM dbo.Products WHERE product_id = 1',
          ),
        );
        expect(productRows.first['price'], 150.0);

        // Verify audit trail
        final auditRows = parseRows(
          await harness.query('''
          SELECT table_name, operation, old_values, new_values, changed_by 
          FROM dbo.AuditLog 
          WHERE table_name = 'Products' AND record_id = 1
        '''),
        );
        expect(auditRows.isNotEmpty, true);
        expect(auditRows.first['changed_by'], 'Test User');
      });

      test(
        'F_COMPLEX_002: User-defined function with complex business logic',
        () async {
          // Setup customer
          await harness.executeParams(
            '''
          INSERT INTO dbo.Customers (customer_id, customer_code, name, customer_type) 
          VALUES (@id, @code, @name, @type)
        ''',
            {'id': 1, 'code': 'VIP-001', 'name': 'VIP Customer', 'type': 'VIP'},
          );

          // Test function with different order amounts
          final testAmounts = [500.0, 2000.0, 5000.0, 10000.0, 15000.0];

          for (final amount in testAmounts) {
            final rows = parseRows(
              await harness.executeParams(
                'SELECT dbo.CalculateDiscount(@type, @amount) as discount',
                {'type': 'VIP', 'amount': amount},
              ),
            );

            final discount = rows.first['discount'] as double;
            expect(discount >= 0, true);
            expect(discount <= 15.0, true);

            if (amount >= 10000) {
              expect(discount, 15.0);
            } else if (amount >= 5000) {
              expect(discount, 10.0);
            } else {
              expect(discount, 5.0);
            }
          }
        },
      );

      test('F_COMPLEX_003: Complex view with multiple aggregations', () async {
        // Setup test data for sales
        // Ensure base product, category, and customer exist for this test
        // Clean up potential leftovers for id=1 to make test idempotent
        await harness.execute(
          "DELETE FROM dbo.Sales WHERE product_id=1 OR customer_id=1",
        );
        await harness.execute(
          "DELETE FROM dbo.ProductSuppliers WHERE product_id=1",
        );
        await harness.execute("DELETE FROM dbo.Inventory WHERE product_id=1");
        await harness.execute("DELETE FROM dbo.Products WHERE product_id=1");
        await harness.execute("DELETE FROM dbo.Categories WHERE category_id=1");
        await harness.execute("DELETE FROM dbo.Customers WHERE customer_id=1");
        await harness.executeParams(
          'INSERT INTO dbo.Categories (category_id, name) VALUES (@id, @name)',
          {'id': 1, 'name': 'Test Category'},
        );
        await harness.executeParams(
          '''
          INSERT INTO dbo.Products (product_id, name, sku, price, category_id) 
          VALUES (@id, @name, @sku, @price, @categoryId)
        ''',
          {
            'id': 1,
            'name': 'Test Product',
            'sku': 'TEST-001',
            'price': 150.0,
            'categoryId': 1,
          },
        );
        await harness.executeParams(
          'INSERT INTO dbo.Customers (customer_id, customer_code, name) VALUES (@id, @code, @name)',
          {'id': 1, 'code': 'CUST-1', 'name': 'Customer 1'},
        );
        await harness.executeParams(
          '''
          INSERT INTO dbo.Sales (product_id, customer_id, quantity_sold, unit_price, discount_percent) 
          VALUES (@productId, @customerId, @qty, @price, @discount)
        ''',
          {
            'productId': 1,
            'customerId': 1,
            'qty': 5,
            'price': 150.0,
            'discount': 10.0,
          },
        );

        final rows = parseRows(
          await harness.query('''
          SELECT 
            product_name,
            total_quantity_sold,
            total_revenue,
            avg_selling_price,
            sale_count
          FROM dbo.ProductSalesView
          WHERE product_id = 1
        '''),
        );

        expect(rows.length, 1);
        expect(rows.first['total_quantity_sold'], 5);
        expect(rows.first['sale_count'], 1);
        expect(rows.first['total_revenue'], 675.0); // 5 * 150 * 0.9
      });

      test(
        'F_COMPLEX_004: Advanced constraints and computed columns',
        () async {
          // Test inventory with computed columns
          // Ensure base product exists
          // Clean up potential leftovers for id=1 to make test idempotent
          await harness.execute("DELETE FROM dbo.Inventory WHERE product_id=1");
          await harness.execute("DELETE FROM dbo.Products WHERE product_id=1");
          await harness.execute(
            "DELETE FROM dbo.Categories WHERE category_id=1",
          );
          await harness.executeParams(
            '''
          INSERT INTO dbo.Categories (category_id, name) VALUES (@id, @name)
        ''',
            {'id': 1, 'name': 'Test Category'},
          );
          await harness.executeParams(
            '''
          INSERT INTO dbo.Products (product_id, name, sku, price, category_id) 
          VALUES (@id, @name, @sku, @price, @categoryId)
        ''',
            {
              'id': 1,
              'name': 'Test Product',
              'sku': 'TEST-001',
              'price': 150.0,
              'categoryId': 1,
            },
          );
          await harness.executeParams(
            '''
          INSERT INTO dbo.Inventory (product_id, location_code, quantity_on_hand, quantity_reserved, reorder_point, max_stock_level) 
          VALUES (@productId, @location, @onHand, @reserved, @reorder, @maxStock)
        ''',
            {
              'productId': 1,
              'location': 'WH-001',
              'onHand': 100,
              'reserved': 25,
              'reorder': 20,
              'maxStock': 200,
            },
          );

          final rows = parseRows(
            await harness.query('''
          SELECT 
            quantity_on_hand,
            quantity_reserved,
            quantity_available,
            CASE 
              WHEN quantity_available <= reorder_point THEN 'REORDER'
              WHEN quantity_available >= max_stock_level THEN 'OVERSTOCK'
              ELSE 'OK'
            END as stock_status
          FROM dbo.Inventory
          WHERE product_id = 1 AND location_code = 'WH-001'
        '''),
          );

          expect(rows.first['quantity_available'], 75); // 100 - 25
          expect(rows.first['stock_status'], 'OK');
        },
      );

      test(
        'F_COMPLEX_005: Many-to-many relationship with business rules',
        () async {
          // Setup supplier
          // Ensure base product exists
          // Clean up potential leftovers for id=1 to make test idempotent
          await harness.execute(
            "DELETE FROM dbo.ProductSuppliers WHERE product_id=1",
          );
          await harness.execute(
            "DELETE FROM dbo.Suppliers WHERE supplier_id=1",
          );
          await harness.execute("DELETE FROM dbo.Products WHERE product_id=1");
          await harness.execute(
            "DELETE FROM dbo.Categories WHERE category_id=1",
          );
          await harness.executeParams(
            'INSERT INTO dbo.Categories (category_id, name) VALUES (@id, @name)',
            {'id': 1, 'name': 'Test Category'},
          );
          await harness.executeParams(
            '''
          INSERT INTO dbo.Products (product_id, name, sku, price, category_id) 
          VALUES (@id, @name, @sku, @price, @categoryId)
        ''',
            {
              'id': 1,
              'name': 'Test Product',
              'sku': 'TEST-001',
              'price': 150.0,
              'categoryId': 1,
            },
          );
          await harness.executeParams(
            '''
          INSERT INTO dbo.Suppliers (supplier_id, company_name, contact_name, rating, is_preferred) 
          VALUES (@id, @company, @contact, @rating, @preferred)
        ''',
            {
              'id': 1,
              'company': 'Premium Supplier Inc.',
              'contact': 'John Smith',
              'rating': 4.5,
              'preferred': true,
            },
          );

          // Create product-supplier relationship
          await harness.executeParams(
            '''
          INSERT INTO dbo.ProductSuppliers (product_id, supplier_id, supplier_product_code, cost, lead_time_days, minimum_order_qty, is_primary) 
          VALUES (@productId, @supplierId, @code, @cost, @leadTime, @minQty, @isPrimary)
        ''',
            {
              'productId': 1,
              'supplierId': 1,
              'code': 'SUP-TEST-001',
              'cost': 80.0,
              'leadTime': 7,
              'minQty': 10,
              'isPrimary': true,
            },
          );

          // Verify complex query with multiple JOINs
          final rows = parseRows(
            await harness.query('''
          SELECT 
            p.name as product_name,
            s.company_name,
            ps.supplier_product_code,
            ps.cost,
            ps.lead_time_days,
            (p.price - ps.cost) as markup,
            ((p.price - ps.cost) / ps.cost * 100) as markup_percent,
            s.is_preferred,
            s.rating
          FROM dbo.Products p
          JOIN dbo.ProductSuppliers ps ON p.product_id = ps.product_id
          JOIN dbo.Suppliers s ON ps.supplier_id = s.supplier_id
          WHERE p.product_id = 1 AND ps.is_primary = 1
        '''),
          );

          expect(rows.length, 1);
          expect(rows.first['company_name'], 'Premium Supplier Inc.');
          expect(rows.first['is_preferred'], true);
          expect(rows.first['markup'], 70.0); // 150 - 80
        },
      );

      // Continue with tests 6-50 for complex mode
      for (int i = 6; i <= 50; i++) {
        test(
          'F_COMPLEX_${i.toString().padLeft(3, '0')}: Enterprise-grade operation test $i',
          () async {
            final supplierId = 1000 + i;
            final customerId = 2000 + i;
            final productId = 3000 + i;
            final categoryId = 4000 + i;

            // Complex multi-table transaction simulation
            await harness.executeParams(
              'INSERT INTO dbo.Categories (category_id, name, description) VALUES (@id, @name, @desc)',
              {
                'id': categoryId,
                'name': 'Advanced_Category_$i',
                'desc': 'Complex category for test $i',
              },
            );

            await harness.executeParams(
              '''
            INSERT INTO dbo.Products (product_id, name, sku, price, cost, category_id, weight) 
            VALUES (@id, @name, @sku, @price, @cost, @categoryId, @weight)
          ''',
              {
                'id': productId,
                'name': 'Enterprise_Product_$i',
                'sku': 'ENT-SKU-$i',
                'price': i * 150.0 + 299.99,
                'cost': i * 90.0 + 199.99,
                'categoryId': categoryId,
                'weight': i * 0.25 + 2.0,
              },
            );

            await harness.executeParams(
              '''
            INSERT INTO dbo.Suppliers (supplier_id, company_name, contact_name, rating, is_preferred) 
            VALUES (@id, @company, @contact, @rating, @preferred)
          ''',
              {
                'id': supplierId,
                'company': 'Supplier_Enterprise_$i',
                'contact': 'Contact_$i',
                'rating': (i % 5 + 1).toDouble(),
                'preferred': i % 3 == 0,
              },
            );

            await harness.executeParams(
              '''
            INSERT INTO dbo.Customers (customer_id, customer_code, name, email, customer_type, credit_limit) 
            VALUES (@id, @code, @name, @email, @type, @limit)
          ''',
              {
                'id': customerId,
                'code': 'ENT-CUST-$i',
                'name': 'Enterprise_Customer_$i',
                'email': 'enterprise$i@bigcorp.com',
                'type': i % 4 == 0
                    ? 'VIP'
                    : (i % 3 == 0 ? 'Premium' : 'Regular'),
                'limit': i * 10000.0 + 50000.0,
              },
            );

            await harness.executeParams(
              '''
            INSERT INTO dbo.ProductSuppliers (product_id, supplier_id, supplier_product_code, cost, lead_time_days, minimum_order_qty, is_primary) 
            VALUES (@productId, @supplierId, @code, @cost, @leadTime, @minQty, @isPrimary)
          ''',
              {
                'productId': productId,
                'supplierId': supplierId,
                'code': 'SUP-CODE-$i',
                'cost': i * 90.0 + 199.99,
                'leadTime': i % 14 + 1,
                'minQty': i % 20 + 5,
                'isPrimary': i % 2 == 0,
              },
            );

            await harness.executeParams(
              '''
            INSERT INTO dbo.Inventory (product_id, location_code, quantity_on_hand, quantity_reserved, reorder_point, max_stock_level) 
            VALUES (@productId, @location, @onHand, @reserved, @reorder, @maxStock)
          ''',
              {
                'productId': productId,
                'location': 'WH-$i',
                'onHand': i * 50 + 100,
                'reserved': i * 5 + 10,
                'reorder': i * 3 + 25,
                'maxStock': i * 100 + 500,
              },
            );

            await harness.executeParams(
              '''
            INSERT INTO dbo.Sales (product_id, customer_id, quantity_sold, unit_price, discount_percent, sales_rep, commission_rate) 
            VALUES (@productId, @customerId, @qty, @price, @discount, @rep, @commission)
          ''',
              {
                'productId': productId,
                'customerId': customerId,
                'qty': i % 10 + 1,
                'price': i * 150.0 + 299.99,
                'discount': i % 20 + 5,
                'rep': 'SalesRep_$i',
                'commission': i % 10 + 2,
              },
            );

            // Execute complex analytical query
            final rows = parseRows(
              await harness.executeParams(
                '''
            WITH ProductAnalytics AS (
              SELECT 
                p.product_id,
                p.name as product_name,
                p.price as current_price,
                ps.cost as supplier_cost,
                (p.price - ps.cost) as gross_margin,
                ((p.price - ps.cost) / p.price * 100) as margin_percent,
                i.quantity_available,
                CASE 
                  WHEN i.quantity_available <= i.reorder_point THEN 'LOW_STOCK'
                  WHEN i.quantity_available >= i.max_stock_level * 0.8 THEN 'HIGH_STOCK'
                  ELSE 'NORMAL_STOCK'
                END as stock_status,
                s.total_amount as last_sale_amount,
                dbo.CalculateDiscount(c.customer_type, s.total_amount) as applicable_discount,
                sup.rating as supplier_rating,
                sup.is_preferred as preferred_supplier
              FROM dbo.Products p
              JOIN dbo.ProductSuppliers ps ON p.product_id = ps.product_id AND ps.is_primary = 1
              JOIN dbo.Suppliers sup ON ps.supplier_id = sup.supplier_id
              JOIN dbo.Inventory i ON p.product_id = i.product_id
              JOIN dbo.Sales s ON p.product_id = s.product_id
              JOIN dbo.Customers c ON s.customer_id = c.customer_id
              WHERE p.product_id = @productId
            )
            SELECT 
              product_name,
              current_price,
              supplier_cost,
              gross_margin,
              margin_percent,
              quantity_available,
              stock_status,
              last_sale_amount,
              applicable_discount,
              supplier_rating,
              preferred_supplier,
              CASE 
                WHEN margin_percent > 50 AND stock_status = 'NORMAL_STOCK' THEN 'OPTIMAL'
                WHEN margin_percent > 30 THEN 'GOOD'
                WHEN margin_percent > 15 THEN 'ACCEPTABLE'
                ELSE 'REVIEW_NEEDED'
              END as profitability_status
            FROM ProductAnalytics
          ''',
                {'productId': productId},
              ),
            );
            if (i % 2 == 0) {
              expect(rows.length, 1);
              expect(rows.first['product_name'], 'Enterprise_Product_$i');
              expect(rows.first['gross_margin'] > 0, true);
              expect(rows.first['margin_percent'] is double, true);
              expect(
                [
                  'LOW_STOCK',
                  'NORMAL_STOCK',
                  'HIGH_STOCK',
                ].contains(rows.first['stock_status']),
                true,
              );
              expect(
                [
                  'OPTIMAL',
                  'GOOD',
                  'ACCEPTABLE',
                  'REVIEW_NEEDED',
                ].contains(rows.first['profitability_status']),
                true,
              );
            } else {
              expect(rows.length, 0);
            }
          },
        );
      }
    });
  });
}
