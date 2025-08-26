// Low-level FreeTDS DB-Lib bindings (subset) for:
// - init/login/open/close
// - simple SQL execute + results iteration
// - RPC (for parameterized queries via sp_executesql)
// - BCP bulk APIs
//
// Notes:
// - Signatures below are simplified to commonly-used shapes consistent with FreeTDS DB-Lib (sybdb.h).
// - For production, validate against your exact FreeTDS headers used to build the libs.
// - All pointers are treated as opaque; memory ownership must follow DB-Lib semantics.

// ignore_for_file: library_private_types_in_public_api, non_constant_identifier_names, deprecated_member_use, camel_case_types, constant_identifier_names

import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import '../native_loader.dart';

// Opaque types
base class DBPROCESS extends Opaque {}

// Minimal UTF-16LE decoder (assumes even-length input of UCS-2/UTF-16LE code units)
String _utf16leDecode(Uint8List bytes) {
  final n = bytes.length & ~1; // even length
  final codes = List<int>.filled(n >> 1, 0);
  for (int i = 0, j = 0; i < n; i += 2, j++) {
    codes[j] = bytes[i] | (bytes[i + 1] << 8);
  }
  return String.fromCharCodes(codes);
}
base class LOGINREC extends Opaque {}

// Common return codes
const int SUCCEED = 1;
const int FAIL = 0;
const int NO_MORE_RESULTS = 2; // dbresults may return NO_MORE_RESULTS

// Row fetch status (dbnextrow) as per FreeTDS sybdb.h
// REG_ROW and MORE_ROWS are -1 (a valid row is available)
// NO_MORE_ROWS is -2 (end of rows), BUF_FULL is -3 (driver buffer full; call again)
const int REG_ROW = -1;
const int MORE_ROWS = -1;
const int NO_MORE_ROWS = -2; // dbnextrow: no more rows
const int BUF_FULL = -3; 
// DB-Lib data types (expanded to align with FreeTDS sybdb.h)
const int SYBCHAR = 47;         // char
const int SYBVARCHAR = 39;      // varchar
const int SYBINTN = 38;         // int (variable length)
const int SYBINT1 = 48;         // tinyint
const int SYBINT2 = 52;         // smallint
const int SYBINT4 = 56;         // int
const int SYBINT8 = 127;        // bigint
const int SYBFLT8 = 62;         // float(53)
const int SYBREAL = 59;         // real (float(24))
const int SYBFLTN = 109;        // float (variable length)
const int SYBDATETIME = 61;     // datetime
const int SYBDATETIME4 = 58;    // smalldatetime
const int SYBDATETIMN = 111;    // datetime (nullable)
const int SYBMSDATE = 40;       // date
const int SYBMSTIME = 41;       // time
const int SYBMSDATETIME2 = 42;  // datetime2
const int SYBMSDATETIMEOFFSET = 43; // datetimeoffset
const int SYBBIGDATETIME = 187; // big datetime
const int SYBBIGTIME = 188;     // big time
const int SYBBIT = 50;          // bit
const int SYBBITN = 104;        // bit (nullable)
const int SYBMONEY = 60;        // money
const int SYBMONEY4 = 122;      // smallmoney
const int SYBMONEYN = 110;      // money (nullable)
const int SYBDECIMAL = 106;     // decimal
const int SYBNUMERIC = 108;     // numeric
const int SYBTEXT = 35;         // text
const int SYBNTEXT = 99;        // ntext
const int SYBNVARCHAR = 103;    // nvarchar
const int SYBBINARY = 45;       // binary
const int SYBVARBINARY = 37;    // varbinary
const int SYBIMAGE = 34;        // image
const int SYBDATE = 49;         // (sybase) date
const int SYBTIME = 51;         // (sybase) time

// BCP direction
const int DB_IN = 1;

// Typedefs
typedef _dbinitC = Void Function();
typedef _dbinitDart = void Function();

typedef _dbloginC = Pointer<LOGINREC> Function();
typedef _dbloginDart = Pointer<LOGINREC> Function();

typedef _dbsetluserC = Int32 Function(Pointer<LOGINREC>, Pointer<Utf8>);
typedef _dbsetluserDart = int Function(Pointer<LOGINREC>, Pointer<Utf8>);

typedef _dbsetlpwdC = Int32 Function(Pointer<LOGINREC>, Pointer<Utf8>);
typedef _dbsetlpwdDart = int Function(Pointer<LOGINREC>, Pointer<Utf8>);

typedef _dbopenC = Pointer<DBPROCESS> Function(Pointer<LOGINREC>, Pointer<Utf8>);
typedef _dbopenDart = Pointer<DBPROCESS> Function(Pointer<LOGINREC>, Pointer<Utf8>);

typedef _dbcloseC = Int32 Function(Pointer<DBPROCESS>);
typedef _dbcloseDart = int Function(Pointer<DBPROCESS>);

typedef _dbexitC = Void Function();
typedef _dbexitDart = void Function();

typedef _dbcmdC = Int32 Function(Pointer<DBPROCESS>, Pointer<Utf8>);
typedef _dbcmdDart = int Function(Pointer<DBPROCESS>, Pointer<Utf8>);

typedef _dbsqlexecC = Int32 Function(Pointer<DBPROCESS>);
typedef _dbsqlexecDart = int Function(Pointer<DBPROCESS>);

typedef _dbresultsC = Int32 Function(Pointer<DBPROCESS>);
typedef _dbresultsDart = int Function(Pointer<DBPROCESS>);

typedef _dbnextrowC = Int32 Function(Pointer<DBPROCESS>);
typedef _dbnextrowDart = int Function(Pointer<DBPROCESS>);

typedef _dbnumcolsC = Int32 Function(Pointer<DBPROCESS>);
typedef _dbnumcolsDart = int Function(Pointer<DBPROCESS>);

typedef _dbcolnameC = Pointer<Utf8> Function(Pointer<DBPROCESS>, Int32);
typedef _dbcolnameDart = Pointer<Utf8> Function(Pointer<DBPROCESS>, int);

typedef _dbcoltypeC = Int32 Function(Pointer<DBPROCESS>, Int32);
typedef _dbcoltypeDart = int Function(Pointer<DBPROCESS>, int);

typedef _dbdatlenC = Int32 Function(Pointer<DBPROCESS>, Int32);
typedef _dbdatlenDart = int Function(Pointer<DBPROCESS>, int);

typedef _dbdataC = Pointer<Uint8> Function(Pointer<DBPROCESS>, Int32);
typedef _dbdataDart = Pointer<Uint8> Function(Pointer<DBPROCESS>, int);

// RPC for parameterized queries (sp_executesql)
typedef _dbrpcinitC = Int32 Function(Pointer<DBPROCESS>, Pointer<Utf8>, Uint16);
typedef _dbrpcinitDart = int Function(Pointer<DBPROCESS>, Pointer<Utf8>, int);

typedef _dbrpcparamC = Int32 Function(
  Pointer<DBPROCESS>,
  Pointer<Utf8> /*name*/, Uint8 /*status*/,
  Int32 /*type*/, Int32 /*maxlen*/,
  Int32 /*datalen*/, Pointer<Uint8> /*value*/);
typedef _dbrpcparamDart = int Function(
  Pointer<DBPROCESS>, Pointer<Utf8>, int, int, int, int, Pointer<Uint8>);

typedef _dbrpcsendC = Int32 Function(Pointer<DBPROCESS>);
typedef _dbrpcsendDart = int Function(Pointer<DBPROCESS>);

typedef _dbsqlokC = Int32 Function(Pointer<DBPROCESS>);
typedef _dbsqlokDart = int Function(Pointer<DBPROCESS>);

// BCP (bulk copy)
typedef _bcp_initC = Int32 Function(Pointer<DBPROCESS>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Int32);
typedef _bcp_initDart = int Function(Pointer<DBPROCESS>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, int);

typedef _bcp_bindC = Int32 Function(
  Pointer<DBPROCESS>,
  Pointer<Uint8> /*varaddr*/, Int32 /*prefixlen*/, Int32 /*varlen*/,
  Pointer<Uint8> /*terminator*/, Int32 /*termlen*/,
  Int32 /*type*/, Int32 /*varnum*/);
typedef _bcp_bindDart = int Function(Pointer<DBPROCESS>, Pointer<Uint8>, int, int, Pointer<Uint8>, int, int, int);

typedef _bcp_sendrowC = Int32 Function(Pointer<DBPROCESS>);
typedef _bcp_sendrowDart = int Function(Pointer<DBPROCESS>);

typedef _bcp_batchC = Int32 Function(Pointer<DBPROCESS>);
typedef _bcp_batchDart = int Function(Pointer<DBPROCESS>);

typedef _bcp_doneC = Int32 Function(Pointer<DBPROCESS>);
typedef _bcp_doneDart = int Function(Pointer<DBPROCESS>);

// dbconvert: convert any src type to another (we'll use to stringify unknown types)
typedef _dbconvertC = Int32 Function(
  Pointer<DBPROCESS>,
  Int32 /*srctype*/, Pointer<Uint8> /*src*/, Int32 /*srclen*/,
  Int32 /*desttype*/, Pointer<Uint8> /*dest*/, Int32 /*destlen*/);
typedef _dbconvertDart = int Function(
  Pointer<DBPROCESS>, int, Pointer<Uint8>, int, int, Pointer<Uint8>, int);

// Loader of symbols from libsybdb
class DBLib {
  final DynamicLibrary _lib;
  late final _dbinitDart dbinit;
  late final _dbloginDart dblogin;
  late final _dbsetluserDart DBSETLUSER;
  late final _dbsetlpwdDart DBSETLPWD;
  late final _dbopenDart dbopen;
  late final _dbcloseDart dbclose;
  late final _dbexitDart dbexit;

  late final _dbcmdDart dbcmd;
  late final _dbsqlexecDart dbsqlexec;
  late final _dbresultsDart dbresults;
  late final _dbnextrowDart dbnextrow;
  late final _dbnumcolsDart dbnumcols;
  late final _dbcolnameDart dbcolname;
  late final _dbcoltypeDart dbcoltype;
  late final _dbdatlenDart dbdatlen;
  late final _dbdataDart dbdata;

  late final _dbrpcinitDart dbrpcinit;
  late final _dbrpcparamDart dbrpcparam;
  late final _dbrpcsendDart dbrpcsend;
  late final _dbsqlokDart dbsqlok;

  late final _bcp_initDart bcp_init;
  late final _bcp_bindDart bcp_bind;
  late final _bcp_sendrowDart bcp_sendrow;
  late final _bcp_batchDart bcp_batch;
  late final _bcp_doneDart bcp_done;
  late final _dbconvertDart dbconvert;

  DBLib(this._lib) {
    dbinit = _lib.lookupFunction<_dbinitC, _dbinitDart>('dbinit');
    dblogin = _lib.lookupFunction<_dbloginC, _dbloginDart>('dblogin');
    DBSETLUSER = _lib.lookupFunction<_dbsetluserC, _dbsetluserDart>('DBSETLUSER');
    DBSETLPWD = _lib.lookupFunction<_dbsetlpwdC, _dbsetlpwdDart>('DBSETLPWD');
    dbopen = _lib.lookupFunction<_dbopenC, _dbopenDart>('dbopen');
    dbclose = _lib.lookupFunction<_dbcloseC, _dbcloseDart>('dbclose');
    dbexit = _lib.lookupFunction<_dbexitC, _dbexitDart>('dbexit');

    dbcmd = _lib.lookupFunction<_dbcmdC, _dbcmdDart>('dbcmd');
    dbsqlexec = _lib.lookupFunction<_dbsqlexecC, _dbsqlexecDart>('dbsqlexec');
    dbresults = _lib.lookupFunction<_dbresultsC, _dbresultsDart>('dbresults');
    dbnextrow = _lib.lookupFunction<_dbnextrowC, _dbnextrowDart>('dbnextrow');
    dbnumcols = _lib.lookupFunction<_dbnumcolsC, _dbnumcolsDart>('dbnumcols');
    dbcolname = _lib.lookupFunction<_dbcolnameC, _dbcolnameDart>('dbcolname');
    dbcoltype = _lib.lookupFunction<_dbcoltypeC, _dbcoltypeDart>('dbcoltype');
    dbdatlen = _lib.lookupFunction<_dbdatlenC, _dbdatlenDart>('dbdatlen');
    dbdata = _lib.lookupFunction<_dbdataC, _dbdataDart>('dbdata');

    dbrpcinit = _lib.lookupFunction<_dbrpcinitC, _dbrpcinitDart>('dbrpcinit');
    dbrpcparam = _lib.lookupFunction<_dbrpcparamC, _dbrpcparamDart>('dbrpcparam');
    dbrpcsend = _lib.lookupFunction<_dbrpcsendC, _dbrpcsendDart>('dbrpcsend');
    dbsqlok = _lib.lookupFunction<_dbsqlokC, _dbsqlokDart>('dbsqlok');

    bcp_init = _lib.lookupFunction<_bcp_initC, _bcp_initDart>('bcp_init');
    bcp_bind = _lib.lookupFunction<_bcp_bindC, _bcp_bindDart>('bcp_bind');
    bcp_sendrow = _lib.lookupFunction<_bcp_sendrowC, _bcp_sendrowDart>('bcp_sendrow');
    bcp_batch = _lib.lookupFunction<_bcp_batchC, _bcp_batchDart>('bcp_batch');
    bcp_done = _lib.lookupFunction<_bcp_doneC, _bcp_doneDart>('bcp_done');

    // Optional but widely available in DB-Lib
    dbconvert = _lib.lookupFunction<_dbconvertC, _dbconvertDart>('dbconvert');
  }

  static DBLib load() => DBLib(NativeLoader.loadDBLib());
}

// Helpers to marshal bytes for dbdata()
dynamic decodeDbValue(int type, Pointer<Uint8> ptr, int len) {
  if (ptr == nullptr || len <= 0) return null;
  switch (type) {
    case SYBINT1:
      return ptr.cast<Uint8>().value;
    case SYBINT2:
      return ptr.cast<Int16>().value;
    case SYBINT4:
      return ptr.cast<Int32>().value;
    case SYBINT8:
      return ptr.cast<Int64>().value;
    case SYBREAL:
      return ptr.cast<Float>().value;
    case SYBFLT8:
      return ptr.cast<Double>().value;
    case SYBFLTN:
      // infer by length
      if (len == 4) return ptr.cast<Float>().value;
      if (len == 8) return ptr.cast<Double>().value;
      return ptr.asTypedList(len);
    case SYBBIT:
      return ptr.cast<Uint8>().value != 0;
    case SYBBITN:
      return len == 0 ? null : (ptr.cast<Uint8>().value != 0);
    case SYBMONEY: {
      // 8-byte money: high 32 bits signed, low 32 bits unsigned, scaled by 10000
      final high = ptr.cast<Int32>().value;
      final low = ptr.elementAt(4).cast<Uint32>().value;
      final int64 = (high.toInt() << 32) + low;
      return int64 / 10000.0;
    }
    case SYBMONEY4: {
      final v = ptr.cast<Int32>().value; // scaled by 10000
      return v / 10000.0;
    }
    case SYBDATETIME: {
      // DBDATETIME: days since 1900-01-01, time in 1/300 sec units
      final days = ptr.cast<Int32>().value;
      final time300 = ptr.elementAt(4).cast<Int32>().value;
      final base = DateTime(1900, 1, 1);
      final date = base.add(Duration(days: days));
      final micros = (time300 * 1000000) ~/ 300;
      final dt = date.add(Duration(microseconds: micros));
      return dt.toIso8601String();
    }
    case SYBDATETIME4: {
      // DBDATETIME4: USMALLINT days since 1900-01-01, USMALLINT minutes since midnight
      final days = ptr.cast<Uint16>().value;
      final minutes = ptr.elementAt(2).cast<Uint16>().value;
      final base = DateTime(1900, 1, 1);
      final dt = base.add(Duration(days: days, minutes: minutes));
      return dt.toIso8601String();
    }
    case SYBBINARY:
    case SYBVARBINARY:
    case SYBIMAGE: {
      final bytes = ptr.asTypedList(len);
      return base64.encode(bytes);
    }
    case SYBCHAR:
    case SYBVARCHAR:
    case SYBTEXT: {
      final bytes = ptr.asTypedList(len);
      return utf8.decode(bytes, allowMalformed: true);
    }
    case SYBNTEXT:
    case SYBNVARCHAR: {
      final bytes = ptr.asTypedList(len);
      return _utf16leDecode(bytes);
    }
    // For DECIMAL/NUMERIC/DATETIME, you may need proper conversion against TDS metadata.
    default:
      return ptr.asTypedList(len); // fallback raw bytes
  }
}

// Decode with dbconvert fallback: for any unhandled type, try to stringify to SYBVARCHAR.
dynamic decodeDbValueWithFallback(
  DBLib db,
  Pointer<DBPROCESS> dbproc,
  int type,
  Pointer<Uint8> ptr,
  int len,
) {
  final v = decodeDbValue(type, ptr, len);
  if (v is Uint8List) {
    final s = tryConvertToString(db, dbproc, type, ptr, len);
    if (s != null) return s;
    // Last resort: base64 the raw bytes for JSON-safety
    return base64.encode(v);
  }
  return v;
}

// Attempt to stringify a value of any type using dbconvert -> SYBVARCHAR.
// Returns null if conversion fails.
String? tryConvertToString(
  DBLib db,
  Pointer<DBPROCESS> dbproc,
  int srcType,
  Pointer<Uint8> src,
  int srcLen,
) {
  if (src == nullptr || srcLen <= 0) return null;
  // Heuristic buffer size: up to 4x source length plus headroom, capped.
  final int maxLen = (srcLen * 4 + 64).clamp(128, 65536);
  final dest = malloc<Uint8>(maxLen);
  try {
    final outLen = db.dbconvert(dbproc, srcType, src, srcLen, SYBVARCHAR, dest, maxLen);
    if (outLen <= 0) return null;
    final bytes = dest.asTypedList(outLen);
    return utf8.decode(bytes, allowMalformed: true);
  } catch (_) {
    return null;
  } finally {
    malloc.free(dest);
  }
}