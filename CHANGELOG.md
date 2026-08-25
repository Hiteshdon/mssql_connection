# Changelog

All notable changes to this project will be documented in this file.

## [3.1.1]

### Added
- One-time setup command to copy native SQL Server libraries into Flutter apps.
- Gradle task snippet for Android to run the setup command automatically on every build.

### Fixed
- Native library loading failures on Android and other platforms caused by missing Flutter plugin registration.
- Improved native library discovery on Linux for packaged desktop builds.
- Documented the Android internet permission required for the plugin to connect.

## [3.1.0]

### Added
- New `connect()` options for TLS encryption and TDS protocol version control.
- Batch execution methods for sending multiple SQL statements in a single round-trip.

### Changed
- Batched write operations are significantly faster, using far fewer network round-trips.

### Fixed
- Parameterized queries now handle NULL and Unicode values correctly on Azure SQL Edge.
- Improved error message diagnostics for DB-Lib failures.
- Large JSON payloads no longer get truncated on read.
- Fixed macOS library path detection for Homebrew installations.

## [3.0.0]

### Added
- Cross-platform support via Dart FFI and FreeTDS for Windows, Android, iOS, macOS, and Linux.
- Transaction helpers for beginning, committing, and rolling back transactions.
- Bulk insertion support for high-throughput inserts.
- Parameterized queries to reduce SQL injection risk.

### Changed
- Unified JSON response shape for all read and write operations.
- Replaced platform-specific method channels and ODBC paths with a single FFI pipeline for consistent behavior.

### Fixed
- More robust Unicode and large text handling, with consistent encoding for binary columns.

### Breaking
- Read and write operations now return a unified JSON object instead of an array-only payload. Update parsers accordingly.

## [2.0.2]

### Changed
* Improved handling of affected row count for UPDATE statements returning 0 rows on Windows.
* Enhanced type parsing in the default case for the Windows platform to support long text and binary fields.
* Suppressed warnings related to jcifs and org.ietf.jgss classes during build.
* Addressed R8 build issues, including missing classes and binary type resolution.
* Fixed UTF-8 decoding inconsistencies when reading large text fields on Windows.

## [2.0.1]

### Updated
- Adjusted environment configuration for improved compatibility with a broader range of Flutter projects.

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

[2.0.2]: https://github.com/Hiteshdon/mssql_connection.git
[3.0.0]: https://github.com/Hiteshdon/mssql_connection.git
