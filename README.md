# MSSQL Connection Plugin

The `mssql_connection` plugin allows Flutter applications to connect to and interact with Microsoft SQL Server databases.

Easily connect and interact with Microsoft SQL Server databases on Android using the `mssql_connection` plugin. 🚀 This plugin offers seamless database operations, including querying and data manipulation. Connect securely with customizable timeouts and disconnect effortlessly. Simplify your database tasks and streamline Android app development with `mssql_connection`. 🔗


## Features

- 🔄 Seamless Microsoft SQL Server integration.\n
- 📊 Execute queries and fetch data effortlessly.
- ⏳ Customize connection timeouts for secure operations.
- 🚀 Simplified API for easy Android app development.
- 🧩 Android platform support.


## Installation


To use the MsSQL Connection plugin in your Flutter project, follow these simple steps:

1. **Open `pubspec.yaml`**: Add the following dependency to your project's `pubspec.yaml` file:

    ```yaml
    dependencies:
      mssql_connection: ^1.0.0
    ```

    Replace `^1.0.0` with the latest version available.

2. **Install Packages**: Run the following command in your terminal to fetch and install the plugin:

    ```bash
    flutter pub get
    ```

3. **Import in Dart Code**: Import the MsSQL Connection package in your Dart code:

    ```dart
    import 'package:mssql_connection/mssql_connection.dart';
    ```

4. **Initialize the Connection**: Create an instance of `MssqlConnection` to use the plugin:

    ```dart
    MssqlConnection mssqlConnection = MssqlConnection.getInstance();
    ```

5. **Use the Plugin**: Now you're ready to use the MsSQL Connection plugin to interact with your Microsoft SQL Server database.


## Usage/Examples
<img src="https://github.com/Hiteshdon/mssql_connection/blob/f58ae81722cd6472d2e574913b54230c0467f6e5/images/image1.png?raw=true" alt="Connection Establishing screen" width="300"/>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;
<img src="https://github.com/Hiteshdon/mssql_connection/blob/f58ae81722cd6472d2e574913b54230c0467f6e5/images/image2.png?raw=true" alt="Read & write Operations" width="300"/>


### Connect to Database

To establish a connection to the Microsoft SQL Server database, use the `connect` method. This method takes the server details, including IP, port, database name, username, and password.

```dart
// Example: Connect to the database
bool isConnected = await mssqlConnection.connect(
  ip: 'your_server_ip',
  port: 'your_server_port',
  databaseName: 'your_database_name',
  username: 'your_username',
  password: 'your_password',
  timeoutInSeconds: 15,
);

// Returns a boolean indicating the connection status.
```
### Get Data

Retrieve data from the connected database using the `getData` method. Pass the SQL query as parameter to `getData` method to fetch the desired information.

```dart
// Example: Fetch data from the database
String query = 'SELECT * FROM your_table';
String result = await mssqlConnection.getData(query);

// Returns a string containing the fetched data in JSON format.
```

### Write Data

Write data to the connected database using the `writeData` method. Pass the SQL query as parameter to `writeData` method for database modification.

```dart
// Example: Update data in the database
String query = 'UPDATE your_table SET column_name = "new_value" WHERE condition';
String result = await mssqlConnection.writeData(query);

// Returns a string containing information about the operation, e.g., affected rows.
```

### Disconnect

Terminate the database connection using the disconnect method.

```dart
// Example: Disconnect from the database
bool isDisconnected = await mssqlConnection.disconnect();

// Returns a boolean indicating the disconnection status.
```

These methods cover the basic functionalities provided by the MsSQL Connection plugin. Customize the SQL queries according to your database schema and requirements.
