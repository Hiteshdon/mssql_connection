# Copilot instructions for `mssql_connection`

## Repository purpose
- This is a Flutter/Dart plugin that connects to Microsoft SQL Server through Dart FFI and FreeTDS.
- The public package entrypoint is `lib/mssql_connection.dart`.
- The main high-level API is the singleton `MssqlConnection` in `lib/src/mssql_connection.dart`; the low-level FreeTDS wrapper is `MssqlClient` in `lib/src/mssql_client.dart`.

## Important architecture
- `MssqlConnection.getInstance()` is a singleton and stores reconnect credentials internally. Be careful about shared state in tests and examples.
- Query methods return JSON strings, not Dart objects. The expected shape is `{"columns":[...],"rows":[...],"affected":N}`.
- Parameterized queries go through `sp_executesql` helpers (`getDataWithParams` / `writeDataWithParams`) and should be preferred over string interpolation.
- Bulk insert support lives in `MssqlClient.bulkInsert()`. Temp tables such as `#tmp` intentionally fall back to parameterized inserts instead of BCP.
- Binary SQL data is base64-encoded before being returned in JSON.

## Native/FFI expectations
- FreeTDS dynamic loading is centralized in `lib/src/native_loader.dart`.
- Platform-specific native library locations matter:
  - Linux: `linux/Libraries`
  - Windows: `windows/Libraries/bin`
  - Android: `android/src/main/jniLibs/<abi>`
- On Windows, `ct.dll` is intentionally preloaded before `sybdb.dll`; preserve that order if you change native loading.
- When editing FFI code, keep explicit native allocation/free patterns intact (`toNativeUtf8()` + `malloc.free()`).

## Tests, analysis, and validation
- Dart analysis is configured by `analysis_options.yaml` and uses `package:lints/recommended.yaml`.
- Run `dart analyze` for static checks.
- Run `dart test` for tests.
- Tests are intentionally serial because FFI callbacks cannot cross isolates; keep `dart_test.yaml` at `concurrency: 1`.
- Many tests expect a reachable SQL Server and use environment variables such as `MSSQL_SERVER`, `MSSQL_USER`, `MSSQL_PASS` / `MSSQL_PASSWORD`, and sometimes `MSSQL_DB`, `MSSQL_IP`, `MSSQL_PORT`.
- The reusable DB test harness is in `test/test_utils.dart`; tests commonly create and drop temporary databases.

## Build and platform scripts
- FreeTDS build helpers live in `scripts/`:
  - `build-posix.sh`
  - `build-android.sh`
  - `build-ios.sh`
  - `build-windows.ps1`
- CI for native builds is defined in `.github/workflows/freetds-multi.yml`.

## Editing guidance
- Keep changes small and localized; most logic lives under `lib/src/`.
- Preserve the existing public API unless the task explicitly requires a breaking change.
- When touching connection logic, review both `MssqlConnection` and `MssqlClient` because reconnect, transactions, and validation are split across them.
- When touching native loading or cross-platform behavior, inspect the workflow and script files as well as `native_loader.dart`.
- Update `README.md` if user-facing behavior or setup steps change.

## Onboarding validation caveat
- If the agent sandbox does not have the Dart SDK installed, Dart commands may fail with `dart: command not found`.
- In that case, use static inspection of `pubspec.yaml`, `README.md`, `dart_test.yaml`, tests, source files, and GitHub workflows to understand the repository first, then run `dart analyze` / `dart test` once a Dart-capable environment is available.
