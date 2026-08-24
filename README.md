# MSSQL Connection Plugin

The `mssql_connection` plugin allows Flutter applications to seamlessly connect to and interact with Microsoft SQL Server databases, offering rich functionality for querying and data manipulation.

🚀 Now powered by Dart FFI + FreeTDS with support for Windows, Android, iOS, macOS, and Linux. Simplify SQL Server access with a small, consistent API. 🔗

---

## Features

- 🔄 **Cross-Platform (FFI + FreeTDS)**: Windows, Android, iOS, macOS, Linux.
- 📊 **Unified JSON**: `{ columns: [...], rows: [...], affected: N }` for reads/writes.
- 🔒 **Parameterized Queries**: Call with `getDataWithParams`/`writeDataWithParams` to reduce injection risk.
- 🔧 **Transactions**: `beginTransaction`, `commit`, `rollback`.
- � **Bulk Insert**: High-throughput inserts using FreeTDS BCP.
- ⏳ **Timeouts + Reconnect**: Login timeout and auto-reconnect on demand.

---

## Installation

To use the MsSQL Connection plugin in your Flutter project, follow these simple steps:

1. **Add Dependency**:
   Open your `pubspec.yaml` file and add the following:

   ```yaml
   dependencies:
     mssql_connection: ^3.0.0
   ```

   Replace `^3.0.0` with the latest version.

2. **Install Packages**:
   Run the following command to fetch the plugin:

   ```bash
   flutter pub get
   ```

3. **Copy native libraries (Flutter apps only, one-time step)**:

   `mssql_connection` is a pure Dart package (not a registered Flutter
   plugin), so it works in plain Dart backend/CLI projects too. The
   trade-off: Flutter's automatic native-library bundling only applies to
   registered plugins, so **Flutter apps must run this once** after adding
   the dependency (and again after `flutter clean` or upgrading the
   package), from the root of your Flutter app:

   ```bash
   dart run mssql_connection:setup
   ```

   This copies the bundled FreeTDS libraries into `android/app/src/main/jniLibs`,
   `linux/Libraries`, `windows/Libraries`, and `macos/Libraries`, and prints
   the remaining manual step needed for iOS (adding the XCFrameworks in
   Xcode) and for packaged desktop release builds (bundling the libraries
   next to the built executable). Skipping this step causes a runtime error
   like `Failed to load dynamic library 'libsybdb.so': dlopen failed:
   library "libsybdb.so" not found` on Android (or the platform equivalent
   elsewhere).

   **Android: automate it instead.** Rather than remembering to re-run the
   command after every `flutter clean`, add this to the end of your app's
   `android/app/build.gradle.kts` once, and every subsequent
   `flutter run`/`flutter build` re-syncs the libraries automatically:

   ```kotlin
   tasks.register<Exec>("mssqlConnectionSetup") {
       workingDir = rootProject.projectDir.parentFile // the Flutter project root
       commandLine("dart", "run", "mssql_connection:setup")
       isIgnoreExitValue = true
   }

   tasks.named("preBuild") {
       dependsOn("mssqlConnectionSetup")
   }
   ```

   (Verified against a real `flutter build apk --debug`: the task runs
   automatically, and `libsybdb.so`/`libct.so` for all three bundled ABIs
   end up in the built APK's `lib/` folder with no manual step.)

   **Android: also add the INTERNET permission.** `flutter create` does not
   add this by default, and its absence produces a `connect()` failure that
   looks identical to a native-library problem (both just return `false`
   with no distinguishing error in the UI). Add this to
   `android/app/src/main/AndroidManifest.xml`, as a direct child of the
   top-level `<manifest>` element:

   ```xml
   <uses-permission android:name="android.permission.INTERNET" />
   ```

   (Verified end-to-end on a real Android device: after adding both the
   Gradle hook above and this permission, the example app connected to a
   live SQL Server and ran a query successfully.)

4. **Import the Plugin**:
   Include the plugin in your Dart code:

   ```dart
   import 'package:mssql_connection/mssql_connection.dart';
   ```

5. **Initialize Connection**:
   Get an instance of `MssqlConnection`:

   ```dart
   MssqlConnection mssqlConnection = MssqlConnection.getInstance();
   ```

---

## Usage/Examples

### Example Screenshots
<img src="https://github.com/Hiteshdon/mssql_connection/blob/f58ae81722cd6472d2e574913b54230c0467f6e5/images/image1.png?raw=true" alt="Connection Establishing Screen" width="300"/>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;
<img src="https://github.com/Hiteshdon/mssql_connection/blob/f58ae81722cd6472d2e574913b54230c0467f6e5/images/image2.png?raw=true" alt="Read & Write Operations Screen" width="300"/>

---

### **Connect to Database**

Establish a connection to the Microsoft SQL Server using the `connect` method with customizable parameters:

```dart
bool isConnected = await mssqlConnection.connect(
  ip: 'your_server_ip',
  port: 'your_server_port',
  databaseName: 'your_database_name',
  username: 'your_username',
  password: 'your_password',
  timeoutInSeconds: 15,
  // Optional TLS / TDS settings (v3.1.0+):
  encrypt: false,               // true = require TLS, false = disable, null = default
  trustServerCertificate: true, // skip cert hostname check (local dev)
  tdsVersion: '7.4',            // recommended for SQL Server 2012+
);

// `isConnected` returns true if the connection is established.
```

**Hosted providers** (Azure, SmartASP, Site4Now) often require `encrypt: true` or `trustServerCertificate: true`. **Local SQL Server** without a trusted certificate usually needs `encrypt: false` and/or `trustServerCertificate: true`.

**Named instances** (`SERVER\INSTANCE`) are not resolved automatically — use the instance's **static TCP port** (e.g. `ip:49242`) or configure `freetds.conf`.

**Web** is not supported (FFI + native FreeTDS cannot run in Flutter Web).

---

### **Get Data**

Fetch data from the database using the `getData` method:

```dart
String query = 'SELECT * FROM your_table';
String result = await mssqlConnection.getData(query);

// `result` contains data in JSON format.
```

---

### **Write Data**

Perform insert, update, or delete operations using the `writeData` method:

```dart
String query = 'UPDATE your_table SET column_name = "new_value" WHERE condition';
String result = await mssqlConnection.writeData(query);

// `result` contains details about the operation, e.g., affected rows.
```

---

### Parameterized queries

Avoid manual string concatenation and let the library pass parameters safely via `sp_executesql`:

```dart
final res = await mssqlConnection.getDataWithParams(
  'SELECT * FROM Users WHERE Name LIKE @name AND IsActive = @active',
  {
    'name': '%john%',
    'active': true,
  },
);
```

---

### Transactions

```dart
await mssqlConnection.beginTransaction();
try {
  await mssqlConnection.writeData('UPDATE Accounts SET Balance = Balance - 100 WHERE Id = 1');
  await mssqlConnection.writeData('UPDATE Accounts SET Balance = Balance + 100 WHERE Id = 2');
  await mssqlConnection.commit();
} catch (_) {
  await mssqlConnection.rollback();
  rethrow;
}
```

---

### Bulk insertion

Highest throughput for structured row data — uses FreeTDS BCP under the hood (~50,000 rows/sec):

```dart
final rows = [
  {'Id': 1, 'Name': 'Alice'},
  {'Id': 2, 'Name': 'Bob'},
];
final inserted = await mssqlConnection.bulkInsert('dbo.Users', rows, batchSize: 1000);
```

---

### Batched writes (multiple statements in one round-trip)

For arbitrary SQL statements (not just single-table inserts), `writeBatch` sends all
statements in a single network round-trip wrapped in a transaction — much faster than
calling `writeData` per statement:

```dart
final statements = List.generate(
  500,
  (i) => "INSERT INTO dbo.Logs (id, msg) VALUES (${i + 1}, N'entry_${i + 1}')",
);
final results = await mssqlConnection.writeBatch(statements);
```

For parameterized statements, `writeBatchWithParams` gives the same round-trip
reduction while keeping values safely escaped (no manual string concatenation):

```dart
final statements = List.generate(
  500,
  (i) => (
    'INSERT INTO dbo.Logs (id, msg) VALUES (@id, @msg)',
    <String, dynamic>{'@id': i + 1, '@msg': 'entry_${i + 1}'},
  ),
);
final results = await mssqlConnection.writeBatchWithParams(statements);
```

`writeBatchWithParams` is ~80x faster than calling `writeDataWithParams` per
statement, since it batches many statements into few `dbsqlexec` round-trips
instead of one RPC per row.

---

### **Disconnect**

Close the database connection when it's no longer needed:

```dart
bool isDisconnected = await mssqlConnection.disconnect();

// `isDisconnected` returns true if the connection was successfully closed.
```

---

## 🔄 Version 3.0.0 Highlights

- Cross-platform via Dart FFI + FreeTDS (Windows/Android/iOS/macOS/Linux).
- Unified JSON response for reads/writes.
- Parameterized queries, transactions, and bulk insertion.

---

## 🔐 Binary Data Handling (`VARBINARY`, `BLOB`, `BINARY`)

This plugin automatically handles binary columns like `VARBINARY`, `BLOB`, and `BINARY` by **Base64 encoding** their contents in the JSON output.

### 🧪 Example

**SQL Query:**

```sql
INSERT INTO Files (FileName, Data)
VALUES ('example.txt', CAST('This is some binary data' AS VARBINARY(MAX)));
```

**Flutter Output:**

```json
{
  "columns": ["Id", "FileName", "Data"],
  "rows": [
    {"Id": 1, "FileName": "example.txt", "Data": "VGhpcyBpcyBzb21lIGJpbmFyeSBkYXRh"}
  ],
  "affected": 0
}
```

### 📥 Decoding in Flutter

You can decode this data like this:

```dart
import 'dart:convert';

final base64Str = "VGhpcyBpcyBzb21lIGJpbmFyeSBkYXRh";
final bytes = base64Decode(base64Str);

// If the binary is actually plain text, decode it further
final decodedText = utf8.decode(bytes);
print(decodedText); // Output: This is some binary data
```

> ⚠️ **Note**: Always decode the binary based on its original intent—whether it's a file, an image, or plain text.

---

## Contributing

Contributions to improve this plugin are welcome! To contribute:

1. Fork the repository.
2. Create a feature branch for your changes.
3. Commit your changes with clear, concise messages.
4. Push the branch and create a pull request.

For issues, suggestions, or feature requests, feel free to open an issue in the repository. Thank you for contributing to `mssql_connection`! 🚀

---