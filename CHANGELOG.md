# Changelog

All notable changes to this project will be documented in this file.

## [2.0.0]

### Added
- Gradle 8 support for improved compatibility with the latest Android tools.
- Windows support using ODBC for seamless database connectivity on Windows platforms.

### Updated
- Enhanced error handling with a custom exception mechanism for better debugging and user feedback.
- Performance optimization and memory improvements.

### Fixed
- Resolved issues with error message parsing to ensure consistent error details in logs.

## [1.1.3]

### Fixed
- Bug fixes related to the execution of stored procedures, improving reliability.

## [1.1.2]

### Updated
- Changed the `bit` SQL type handling to `Integer` for improved type compatibility and consistency.

## [1.1.1]

### Updated
- Modified the timestamp format from milliseconds to a date string for better readability and interoperability.

## [1.1.0]

### Optimized
- Plugin refactoring: Converted codebase from Java to Kotlin, resulting in significant performance enhancements and cleaner code structure.

## [1.0.3]

### Updated
- Improved code documentation for better developer understanding and usage guidelines.

## [1.0.2]

### Updated
- Enhanced project documentation to include detailed setup and usage instructions.

## [1.0.1]

### Added
- Initial release of the Flutter plugin for connecting to Microsoft SQL Server databases.
- Support for customizable database connection parameters.
- Functionality to execute SQL queries and retrieve results in JSON format.
- Support for database write operations (insert, update, delete) with transaction management.
- Automatic reconnection handling for robust connectivity during connection interruptions.
- Configurable timeout settings for managing database connection response times.

[2.0.0]: https://github.com/Hiteshdon/mssql_connection.git
