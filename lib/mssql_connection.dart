/// Support for doing something awesome.
///
/// More dartdocs go here.
library;

export 'src/mssql_client.dart';
export 'src/native_loader.dart';
export 'src/ffi/freetds_bindings.dart' show
  // Export SYB* constants for consumers specifying types explicitly
  SYBCHAR,
  SYBVARCHAR,
  SYBINTN,
  SYBINT1,
  SYBINT2,
  SYBINT4,
  SYBINT8,
  SYBFLT8,
  SYBREAL,
  SYBFLTN,
  SYBDATETIME,
  SYBDATETIME4,
  SYBDATETIMN,
  SYBMSDATE,
  SYBMSTIME,
  SYBMSDATETIME2,
  SYBMSDATETIMEOFFSET,
  SYBBIGDATETIME,
  SYBBIGTIME,
  SYBBIT,
  SYBBITN,
  SYBMONEY,
  SYBMONEY4,
  SYBMONEYN,
  SYBDECIMAL,
  SYBNUMERIC,
  SYBTEXT,
  SYBNTEXT,
  SYBNVARCHAR,
  SYBBINARY,
  SYBVARBINARY,
  SYBIMAGE;

// TODO: Export any libraries intended for clients of this package.
