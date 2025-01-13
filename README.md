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

## What's New in v2.0.0?

- **Windows Support**: Added ODBC-based connectivity for Windows.
- **Improved Compatibility**: Updated to support Gradle 8.
- **Enhanced Error Handling**: Simplified custom exception handling for consistent debugging.
- **Optimized Operations**: Performance enhancements across querying, connection, and disconnection mechanisms.

---

## Contributing

Contributions to improve this plugin are welcome! To contribute:

1. Fork the repository.
2. Create a feature branch for your changes.
3. Commit your changes with clear, concise messages.
4. Push the branch and create a pull request.

For issues, suggestions, or feature requests, feel free to open an issue in the repository. Thank you for contributing to `mssql_connection`! 🚀

---