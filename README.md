# MSSQL Connection Plugin

The `mssql_connection` plugin allows Flutter applications to seamlessly connect to and interact with Microsoft SQL Server databases, offering rich functionality for querying and data manipulation.

🚀 Now supports **Windows** along with Android for cross-platform development. Easily customize your database operations, ensure secure connections, and simplify app development with `mssql_connection`. 🔗

---

## Features

- 🔄 **Cross-Platform Support**: Seamless Microsoft SQL Server integration for Android and Windows.
- 📊 **Query Execution**: Execute SQL queries and retrieve data effortlessly in JSON format.
- ⏳ **Configurable Timeouts**: Set connection timeouts for secure and reliable operations.
- 🧩 **Simplified API**: Developer-friendly API for Flutter apps.
- 🔄 **Automatic Reconnection**: Robust connection handling during interruptions.
- 🚀 **Effortless Data Writing**: Perform insert, update, and delete operations with transaction support.

---

## Installation

To use the MsSQL Connection plugin in your Flutter project, follow these simple steps:

1. **Add Dependency**:
   Open your `pubspec.yaml` file and add the following:

   ```yaml
   dependencies:
     mssql_connection: ^2.0.0
   ```

   Replace `^2.0.0` with the latest version.

2. **Install Packages**:
   Run the following command to fetch the plugin:

   ```bash
   flutter pub get
   ```

3. **Import the Plugin**:
   Include the plugin in your Dart code:

   ```dart
   import 'package:mssql_connection/mssql_connection.dart';
   ```

4. **Initialize Connection**:
   Get an instance of `MssqlConnection`:

   ```dart
   MssqlConnection mssqlConnection = MssqlConnection.getInstance();
   ```

---

## Usage/Examples
<img src="https://github.com/Hiteshdon/mssql_connection/blob/f58ae81722cd6472d2e574913b54230c0467f6e5/images/image1.png?raw=true" alt="Connection Establishing screen" width="300"/>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;
<img src="https://github.com/Hiteshdon/mssql_connection/blob/f58ae81722cd6472d2e574913b54230c0467f6e5/images/image2.png?raw=true" alt="Read & write Operations" width="300"/>

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
);

// `isConnected` returns true if the connection is established.
```

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

### **Disconnect**

Close the database connection when it's no longer needed:

```dart
bool isDisconnected = await mssqlConnection.disconnect();

// `isDisconnected` returns true if the connection was successfully closed.
```

---

## 🔄 Version 2.0.2 Updates

### ✅ Android

Here's a clearer and more helpful version of that line for your changelog or README:

* ✅ Added a `proguard-rules.pro` file under `example/android/app/` to prevent *R8: Missing class* issues during APK builds.
> 🔧 If you encounter similar R8-related errors in your own project when using this plugin, you can [download this file](https://github.com/Hiteshdon/mssql_connection/blob/main/example/android/app/proguard-rules.pro) and place it in your project at `android/app/`.

* ✅ Improved JSON serialization support for special SQL types:

  * `Types.BINARY`, `VARBINARY`, `LONGVARBINARY`
  * `CLOB`, `ARRAY`, `STRUCT`, `DISTINCT`, `REF`, `JAVA_OBJECT`

### 🪟 Windows

* 🛠️ Fixed `INK : fatal error LNK1104` issue during Windows builds for smoother native compilation.

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
[
  {
    "Id": 1,
    "FileName": "example.txt",
    "Data": "VGhpcyBpcyBzb21lIGJpbmFyeSBkYXRh"
  }
]
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