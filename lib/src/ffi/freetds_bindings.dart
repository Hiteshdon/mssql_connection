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

// Heuristic: detect if a byte array likely contains UTF-16LE encoded text mistakenly
// tagged as VARCHAR (i.e., ASCII bytes with 0x00 interleaved). We check for even length
// and a high ratio of zero bytes in odd positions.
bool _looksUtf16LeText(Uint8List bytes) {
  if (bytes.length < 2 || (bytes.length & 1) == 1) return false;
  // If any odd index contains 0x00, it's likely UTF-16LE (for ASCII-range chars)
  // Allow odd-length inputs; the last trailing byte will be ignored by the decoder.
  for (int i = 1; i < bytes.length; i += 2) {
    if (bytes[i] == 0) return true;
  }
  return false;
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
const int SYBCHAR = 47; // char
const int SYBVARCHAR = 39; // varchar
const int SYBINTN = 38; // int (variable length)
const int SYBINT1 = 48; // tinyint
const int SYBINT2 = 52; // smallint
const int SYBINT4 = 56; // int
const int SYBINT8 = 127; // bigint
const int SYBFLT8 = 62; // float(53)
const int SYBREAL = 59; // real (float(24))
const int SYBFLTN = 109; // float (variable length)
const int SYBDATETIME = 61; // datetime
const int SYBDATETIME4 = 58; // smalldatetime
const int SYBDATETIMN = 111; // datetime (nullable)
const int SYBMSDATE = 40; // date
const int SYBMSTIME = 41; // time
const int SYBMSDATETIME2 = 42; // datetime2
const int SYBMSDATETIMEOFFSET = 43; // datetimeoffset
const int SYBBIGDATETIME = 187; // big datetime
const int SYBBIGTIME = 188; // big time
const int SYBBIT = 50; // bit
const int SYBBITN = 104; // bit (nullable)
const int SYBMONEY = 60; // money
const int SYBMONEY4 = 122; // smallmoney
const int SYBMONEYN = 110; // money (nullable)
const int SYBDECIMAL = 106; // decimal
const int SYBNUMERIC = 108; // numeric
const int SYBTEXT = 35; // text
const int SYBNTEXT = 99; // ntext
const int SYBNVARCHAR = 103; // nvarchar
const int SYBBINARY = 45; // binary
const int SYBVARBINARY = 37; // varbinary
const int SYBIMAGE = 34; // image
const int SYBDATE = 49; // (sybase) date
const int SYBTIME = 51; // (sybase) time

// BCP direction
const int DB_IN = 1;
// Login option selector (subset)
const int DBSETBCP = 6; // enable BCP on LOGINREC
// dbsetopt option IDs (subset)
const int DBTEXTSIZE = 17; // set text size for large text retrieval
// Per sybdb.h, DBSETUSER and DBSETPWD constants used with dbsetlname()
const int DBSETUSER = 2;
const int DBSETPWD = 3;

// RPC options (per sybdb.h)
// DBRPCRECOMPILE causes the stored procedure to be recompiled before executing.
// DBRPCRESET cancels any pending RPC(s) and resets the internal RPC state.
const int DBRPCRECOMPILE = 0x0001;
const int DBRPCRESET = 0x0002;

// Typedefs
//
// Group: Connection lifecycle (init/login/open/close)
// These map to DB-Lib primitives to initialize the library, create a LOGINREC,
// set credentials, open a DBPROCESS (connection), and cleanly close/exit.
/// C: void dbinit(void) — Initialize DB-Lib (call once in process before using DB-Lib)
typedef _dbinitC = Void Function();
typedef _dbinitDart = void Function();

/// C: LOGINREC* dblogin(void) — Allocate a login record handle
typedef _dbloginC = Pointer<LOGINREC> Function();
typedef _dbloginDart = Pointer<LOGINREC> Function();

// Note: DBSETLUSER/DBSETLPWD are macros in sybdb.h that call dbsetlname()
// with selectors DBSETUSER/DBSETPWD. We bind dbsetlname and add thin wrappers
// below on the DBLib class to keep a 2-arg Dart API.

/// C: RETCODE dbsetlname(LOGINREC*, const char* value, int which)
/// Use with which=DBSETUSER or DBSETPWD; DBSETLUSER/DBSETLPWD are macros.
typedef _dbsetlnameC = Int32 Function(Pointer<LOGINREC>, Pointer<Utf8>, Int32);
typedef _dbsetlnameDart = int Function(Pointer<LOGINREC>, Pointer<Utf8>, int);

/// C: DBPROCESS* dbopen(LOGINREC*, const char* server) — Open connection
typedef _dbopenC =
    Pointer<DBPROCESS> Function(Pointer<LOGINREC>, Pointer<Utf8>);
typedef _dbopenDart =
    Pointer<DBPROCESS> Function(Pointer<LOGINREC>, Pointer<Utf8>);

/// C: int dbclose(DBPROCESS*) — Close connection (DBPROCESS)
typedef _dbcloseC = Int32 Function(Pointer<DBPROCESS>);
typedef _dbcloseDart = int Function(Pointer<DBPROCESS>);

/// C: void dbexit(void) — Shutdown DB-Lib (call when done with all DB work)
typedef _dbexitC = Void Function();
typedef _dbexitDart = void Function();

// Group: Command execution and result processing (DML/DDL and row retrieval)
/// C: int dbcmd(DBPROCESS*, const char* sql) — Queue an SQL command string
typedef _dbcmdC = Int32 Function(Pointer<DBPROCESS>, Pointer<Utf8>);
typedef _dbcmdDart = int Function(Pointer<DBPROCESS>, Pointer<Utf8>);

/// C: int dbsqlexec(DBPROCESS*) — Execute previously queued command(s)
typedef _dbsqlexecC = Int32 Function(Pointer<DBPROCESS>);
typedef _dbsqlexecDart = int Function(Pointer<DBPROCESS>);

/// C: int dbresults(DBPROCESS*) — Step through result sets (SUCCEED/NO_MORE_RESULTS)
typedef _dbresultsC = Int32 Function(Pointer<DBPROCESS>);
typedef _dbresultsDart = int Function(Pointer<DBPROCESS>);

/// C: int dbnextrow(DBPROCESS*) — Fetch next row (REG_ROW/-1 for row, NO_MORE_ROWS/-2 end)
typedef _dbnextrowC = Int32 Function(Pointer<DBPROCESS>);
typedef _dbnextrowDart = int Function(Pointer<DBPROCESS>);

/// C: int dbnumcols(DBPROCESS*) — Column count for current result set
typedef _dbnumcolsC = Int32 Function(Pointer<DBPROCESS>);
typedef _dbnumcolsDart = int Function(Pointer<DBPROCESS>);

/// C: const char* dbcolname(DBPROCESS*, int col) — Column name (1-based index)
typedef _dbcolnameC = Pointer<Utf8> Function(Pointer<DBPROCESS>, Int32);
typedef _dbcolnameDart = Pointer<Utf8> Function(Pointer<DBPROCESS>, int);

/// C: int dbcoltype(DBPROCESS*, int col) — Column DB-Lib type code
typedef _dbcoltypeC = Int32 Function(Pointer<DBPROCESS>, Int32);
typedef _dbcoltypeDart = int Function(Pointer<DBPROCESS>, int);

/// C: int dbdatlen(DBPROCESS*, int col) — Byte length of current row’s column value
typedef _dbdatlenC = Int32 Function(Pointer<DBPROCESS>, Int32);
typedef _dbdatlenDart = int Function(Pointer<DBPROCESS>, int);

/// C: BYTE* dbdata(DBPROCESS*, int col) — Pointer to current row’s column bytes
typedef _dbdataC = Pointer<Uint8> Function(Pointer<DBPROCESS>, Int32);
typedef _dbdataDart = Pointer<Uint8> Function(Pointer<DBPROCESS>, int);

/// C: int dbcount(DBPROCESS*) — Rows affected by last DML/DDL
typedef _dbcountC = Int32 Function(Pointer<DBPROCESS>);
typedef _dbcountDart = int Function(Pointer<DBPROCESS>);

// Group: Timeouts and database selection
/// C: int dbsetlogintime(int seconds) — Login/connect timeout
typedef _dbsetlogintimeC = Int32 Function(Int32);
typedef _dbsetlogintimeDart = int Function(int);

/// C: int dbsettime(int seconds) — Query/statement timeout
typedef _dbsettimeC = Int32 Function(Int32);
typedef _dbsettimeDart = int Function(int);

/// C: int dbuse(DBPROCESS*, const char* db) — Change current database
typedef _dbuseC = Int32 Function(Pointer<DBPROCESS>, Pointer<Utf8>);
typedef _dbuseDart = int Function(Pointer<DBPROCESS>, Pointer<Utf8>);

// Group: LOGINREC options (e.g., enable BCP using DBSETBCP)
/// C: int dbsetlbool(LOGINREC*, int option, int value) — Toggle login options
typedef _dbsetlboolC = Int32 Function(Pointer<LOGINREC>, Int32, Int32);
typedef _dbsetlboolDart = int Function(Pointer<LOGINREC>, int, int);

/// C: int dbsetopt(DBPROCESS*, int option, const char* char_param, int int_param)
typedef _dbsetoptC =
    Int32 Function(Pointer<DBPROCESS>, Int32, Pointer<Utf8>, Int32);
typedef _dbsetoptDart =
    int Function(Pointer<DBPROCESS>, int, Pointer<Utf8>, int);

// Group: RPC for parameterized queries (e.g., sp_executesql)
/// C: int dbrpcinit(DBPROCESS*, const char* rpcname, uint16_t options)
typedef _dbrpcinitC = Int32 Function(Pointer<DBPROCESS>, Pointer<Utf8>, Uint16);
typedef _dbrpcinitDart = int Function(Pointer<DBPROCESS>, Pointer<Utf8>, int);

/// C: int dbrpcparam(DBPROCESS*, const char* name, uint8 status,
///                   int type, int maxlen, int datalen, BYTE* value)
typedef _dbrpcparamC =
    Int32 Function(
      Pointer<DBPROCESS>,
      Pointer<Utf8> /*name*/,
      Uint8 /*status*/,
      Int32 /*type*/,
      Int32 /*maxlen*/,
      Int32 /*datalen*/,
      Pointer<Uint8> /*value*/,
    );
typedef _dbrpcparamDart =
    int Function(
      Pointer<DBPROCESS>,
      Pointer<Utf8>,
      int,
      int,
      int,
      int,
      Pointer<Uint8>,
    );

/// C: int dbrpcsend(DBPROCESS*) — Send RPC call with parameters
typedef _dbrpcsendC = Int32 Function(Pointer<DBPROCESS>);
typedef _dbrpcsendDart = int Function(Pointer<DBPROCESS>);

/// C: int dbsqlok(DBPROCESS*) — Finalize send; proceed to dbresults/dbnextrow
typedef _dbsqlokC = Int32 Function(Pointer<DBPROCESS>);
typedef _dbsqlokDart = int Function(Pointer<DBPROCESS>);

// Group: Error and message handlers
/// C: EHANDLEFUNC dberrhandle(EHANDLEFUNC handler)
typedef _errHandlerSigC =
    Int32 Function(
      Pointer<DBPROCESS>,
      Int32 /*severity*/,
      Int32 /*dberr*/,
      Int32 /*oserr*/,
      Pointer<Utf8> /*dberrstr*/,
      Pointer<Utf8> /*oserrstr*/,
    );
typedef _dberrhandleC =
    Pointer<NativeFunction<_errHandlerSigC>> Function(
      Pointer<NativeFunction<_errHandlerSigC>>,
    );
typedef _dberrhandleDart =
    Pointer<NativeFunction<_errHandlerSigC>> Function(
      Pointer<NativeFunction<_errHandlerSigC>>,
    );

/// C: MHANDLEFUNC dbmsghandle(MHANDLEFUNC handler)
typedef _msgHandlerSigC =
    Int32 Function(
      Pointer<DBPROCESS>,
      Int32 /*msgno*/,
      Int32 /*msgstate*/,
      Int32 /*severity*/,
      Pointer<Utf8> /*msgtext*/,
      Pointer<Utf8> /*server*/,
      Pointer<Utf8> /*proc*/,
      Int32 /*line*/,
    );
typedef _dbmsghandleC =
    Pointer<NativeFunction<_msgHandlerSigC>> Function(
      Pointer<NativeFunction<_msgHandlerSigC>>,
    );
typedef _dbmsghandleDart =
    Pointer<NativeFunction<_msgHandlerSigC>> Function(
      Pointer<NativeFunction<_msgHandlerSigC>>,
    );

// Group: BCP (bulk copy) — high-throughput inserts
/// C: int bcp_init(DBPROCESS*, const char* table, const char* datafile,
///                 const char* errorfile, int direction)
typedef _bcp_initC =
    Int32 Function(
      Pointer<DBPROCESS>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Int32,
    );
typedef _bcp_initDart =
    int Function(
      Pointer<DBPROCESS>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      int,
    );

/// C: int bcp_bind(DBPROCESS*, BYTE* varaddr, int prefixlen, int varlen,
///                 BYTE* terminator, int termlen, int type, int varnum)
typedef _bcp_bindC =
    Int32 Function(
      Pointer<DBPROCESS>,
      Pointer<Uint8> /*varaddr*/,
      Int32 /*prefixlen*/,
      Int32 /*varlen*/,
      Pointer<Uint8> /*terminator*/,
      Int32 /*termlen*/,
      Int32 /*type*/,
      Int32 /*varnum*/,
    );
typedef _bcp_bindDart =
    int Function(
      Pointer<DBPROCESS>,
      Pointer<Uint8>,
      int,
      int,
      Pointer<Uint8>,
      int,
      int,
      int,
    );

/// C: int bcp_sendrow(DBPROCESS*) — Send a single bound row
typedef _bcp_sendrowC = Int32 Function(Pointer<DBPROCESS>);
typedef _bcp_sendrowDart = int Function(Pointer<DBPROCESS>);

/// C: int bcp_batch(DBPROCESS*) — Commit current batch; returns rows copied in batch
typedef _bcp_batchC = Int32 Function(Pointer<DBPROCESS>);
typedef _bcp_batchDart = int Function(Pointer<DBPROCESS>);

/// C: int bcp_done(DBPROCESS*) — Finalize BCP; returns total rows copied
typedef _bcp_doneC = Int32 Function(Pointer<DBPROCESS>);
typedef _bcp_doneDart = int Function(Pointer<DBPROCESS>);

// BCP per-row helpers
/// C: int bcp_collen(DBPROCESS*, int newlen, int col) — Set data length for a column
typedef _bcp_collenC = Int32 Function(Pointer<DBPROCESS>, Int32, Int32);
typedef _bcp_collenDart = int Function(Pointer<DBPROCESS>, int, int);

/// C: int bcp_colptr(DBPROCESS*, BYTE* data, int col) — Attach data pointer for a column
typedef _bcp_colptrC =
    Int32 Function(Pointer<DBPROCESS>, Pointer<Uint8>, Int32);
typedef _bcp_colptrDart = int Function(Pointer<DBPROCESS>, Pointer<Uint8>, int);

// Group: Type conversion helper
/// C: int dbconvert(DBPROCESS*, int srctype, BYTE* src, int srclen,
///                  int desttype, BYTE* dest, int destlen)
// Used as a fallback to stringify or coerce DECIMAL/NUMERIC/etc.
typedef _dbconvertC =
    Int32 Function(
      Pointer<DBPROCESS>,
      Int32 /*srctype*/,
      Pointer<Uint8> /*src*/,
      Int32 /*srclen*/,
      Int32 /*desttype*/,
      Pointer<Uint8> /*dest*/,
      Int32 /*destlen*/,
    );
typedef _dbconvertDart =
    int Function(
      Pointer<DBPROCESS>,
      int,
      Pointer<Uint8>,
      int,
      int,
      Pointer<Uint8>,
      int,
    );

// Loader of symbols from libsybdb
class DBLib {
  /*
  DBLib
  
  A thin, low-level loader and holder of FreeTDS DB-Lib (libsybdb) symbols.
  
  Summary:
  - Provides typed Dart FFI entry points for connection lifecycle, SQL exec/result
    iteration, RPC (parameterized queries), BCP bulk copy, and value conversion.
  - Exposes thin wrappers (dbsetluser/dbsetlpwd) that map to dbsetlname with
    DBSETUSER/DBSETPWD selectors to keep a simple 2-arg API for credentials.
  
  Contract (conventions):
  - Return codes mirror DB-Lib (SUCCEED=1, FAIL=0). Some functions use special
    codes (e.g., dbresults may return NO_MORE_RESULTS=2; dbnextrow returns
    REG_ROW=-1, NO_MORE_ROWS=-2, etc.).
  - All pointers are opaque; the caller owns higher-level resource semantics
    (create LOGINREC with dblogin, open DBPROCESS with dbopen, close with dbclose,
    and shut down library with dbexit when done).
  
  Typical lifecycle:
  1) dbinit()
  2) final login = dblogin(); dbsetluser(login, user), dbsetlpwd(login, pass);
  3) final dbproc = dbopen(login, server);
  4) dbcmd/dbsqlexec -> dbresults loop -> dbnextrow iteration -> dbcount, etc.
  5) dbclose(dbproc); dbexit();
  
  Notes:
  - DBSETLUSER/DBSETLPWD are macros in sybdb.h; use dbsetlname under the hood.
  - Use dbsetlogintime/dbsettime for timeouts and dbuse to change database.
  - For high-throughput inserts, use BCP APIs (bcp_init/bind/sendrow/batch/done).
  */
  final DynamicLibrary _lib;
  late final _dbinitDart dbinit;
  late final _dbloginDart dblogin;
  late final _dbsetlnameDart dbsetlname;
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
  late final _dbcountDart dbcount;

  late final _dbsetlogintimeDart dbsetlogintime;
  late final _dbsettimeDart dbsettime;
  late final _dbuseDart dbuse;
  late final _dbsetlboolDart dbsetlbool;
  late final _dbsetoptDart dbsetopt;

  late final _dbrpcinitDart dbrpcinit;
  late final _dbrpcparamDart dbrpcparam;
  late final _dbrpcsendDart dbrpcsend;
  late final _dbsqlokDart dbsqlok;
  late final _dberrhandleDart dberrhandle;
  late final _dbmsghandleDart dbmsghandle;

  late final _bcp_initDart bcp_init;
  late final _bcp_bindDart bcp_bind;
  late final _bcp_sendrowDart bcp_sendrow;
  late final _bcp_batchDart bcp_batch;
  late final _bcp_doneDart bcp_done;
  late final _bcp_collenDart bcp_collen;
  late final _bcp_colptrDart bcp_colptr;
  late final _dbconvertDart dbconvert;

  DBLib(this._lib) {
    // Lookups: Connection lifecycle (init/login/open/close)
    dbinit = _lib.lookupFunction<_dbinitC, _dbinitDart>(
      'dbinit',
    ); // Initialize DB-Lib
    dblogin = _lib.lookupFunction<_dbloginC, _dbloginDart>(
      'dblogin',
    ); // Create LOGINREC
    // DBSETLUSER/DBSETLPWD are macros -> bind the underlying function dbsetlname
    dbsetlname = _lib.lookupFunction<_dbsetlnameC, _dbsetlnameDart>(
      'dbsetlname',
    ); // Set LOGINREC field by selector
    dbopen = _lib.lookupFunction<_dbopenC, _dbopenDart>(
      'dbopen',
    ); // Open DBPROCESS connection
    dbclose = _lib.lookupFunction<_dbcloseC, _dbcloseDart>(
      'dbclose',
    ); // Close DBPROCESS
    dbexit = _lib.lookupFunction<_dbexitC, _dbexitDart>(
      'dbexit',
    ); // Shutdown DB-Lib

    // Lookups: Command execution and results iteration (DML/DDL + rows)
    dbcmd = _lib.lookupFunction<_dbcmdC, _dbcmdDart>('dbcmd'); // Queue SQL text
    dbsqlexec = _lib.lookupFunction<_dbsqlexecC, _dbsqlexecDart>(
      'dbsqlexec',
    ); // Execute queued SQL
    dbresults = _lib.lookupFunction<_dbresultsC, _dbresultsDart>(
      'dbresults',
    ); // Iterate result sets
    dbnextrow = _lib.lookupFunction<_dbnextrowC, _dbnextrowDart>(
      'dbnextrow',
    ); // Fetch next row
    dbnumcols = _lib.lookupFunction<_dbnumcolsC, _dbnumcolsDart>(
      'dbnumcols',
    ); // Column count
    dbcolname = _lib.lookupFunction<_dbcolnameC, _dbcolnameDart>(
      'dbcolname',
    ); // Column name
    dbcoltype = _lib.lookupFunction<_dbcoltypeC, _dbcoltypeDart>(
      'dbcoltype',
    ); // Column type code
    dbdatlen = _lib.lookupFunction<_dbdatlenC, _dbdatlenDart>(
      'dbdatlen',
    ); // Current value byte length
    dbdata = _lib.lookupFunction<_dbdataC, _dbdataDart>(
      'dbdata',
    ); // Current value pointer
    dbcount = _lib.lookupFunction<_dbcountC, _dbcountDart>(
      'dbcount',
    ); // Rows affected

    // Lookups: Timeouts and database selection
    dbsetlogintime = _lib.lookupFunction<_dbsetlogintimeC, _dbsetlogintimeDart>(
      'dbsetlogintime',
    ); // Login timeout
    dbsettime = _lib.lookupFunction<_dbsettimeC, _dbsettimeDart>(
      'dbsettime',
    ); // Statement timeout
    dbuse = _lib.lookupFunction<_dbuseC, _dbuseDart>(
      'dbuse',
    ); // Change database
    dbsetlbool = _lib.lookupFunction<_dbsetlboolC, _dbsetlboolDart>(
      'dbsetlbool',
    ); // Toggle login options (e.g., BCP)
    dbsetopt = _lib.lookupFunction<_dbsetoptC, _dbsetoptDart>(
      'dbsetopt',
    ); // Set session options (e.g., DBTEXTSIZE)

    // Lookups: RPC for parameterized queries
    dbrpcinit = _lib.lookupFunction<_dbrpcinitC, _dbrpcinitDart>(
      'dbrpcinit',
    ); // Start RPC (e.g., sp_executesql)
    dbrpcparam = _lib.lookupFunction<_dbrpcparamC, _dbrpcparamDart>(
      'dbrpcparam',
    ); // Add RPC parameter
    dbrpcsend = _lib.lookupFunction<_dbrpcsendC, _dbrpcsendDart>(
      'dbrpcsend',
    ); // Send RPC
    dbsqlok = _lib.lookupFunction<_dbsqlokC, _dbsqlokDart>(
      'dbsqlok',
    ); // Finalize send

    // Lookups: error and message handlers
    dberrhandle = _lib.lookupFunction<_dberrhandleC, _dberrhandleDart>(
      'dberrhandle',
    );
    dbmsghandle = _lib.lookupFunction<_dbmsghandleC, _dbmsghandleDart>(
      'dbmsghandle',
    );

    // Lookups: BCP (bulk copy) high-throughput inserts
    bcp_init = _lib.lookupFunction<_bcp_initC, _bcp_initDart>(
      'bcp_init',
    ); // Init bulk copy
    bcp_bind = _lib.lookupFunction<_bcp_bindC, _bcp_bindDart>(
      'bcp_bind',
    ); // Bind program variables
    bcp_sendrow = _lib.lookupFunction<_bcp_sendrowC, _bcp_sendrowDart>(
      'bcp_sendrow',
    ); // Send row
    bcp_batch = _lib.lookupFunction<_bcp_batchC, _bcp_batchDart>(
      'bcp_batch',
    ); // Commit batch
    bcp_done = _lib.lookupFunction<_bcp_doneC, _bcp_doneDart>(
      'bcp_done',
    ); // Finalize bulk copy
    bcp_collen = _lib.lookupFunction<_bcp_collenC, _bcp_collenDart>(
      'bcp_collen',
    ); // Set column length
    bcp_colptr = _lib.lookupFunction<_bcp_colptrC, _bcp_colptrDart>(
      'bcp_colptr',
    ); // Set column pointer

    // Lookup: Type conversion helper
    dbconvert = _lib.lookupFunction<_dbconvertC, _dbconvertDart>(
      'dbconvert',
    ); // Convert values (fallback)
  }

  /// Set the username on a LOGINREC using the DBSETUSER selector.
  ///
  /// Parameters:
  /// - login: LOGINREC* obtained from [dblogin]. Must be non-null.
  /// - username: UTF-8 pointer to the username string (null-terminated).
  ///
  /// Returns: SUCCEED (1) on success, FAIL (0) on error.
  ///
  /// Notes:
  /// - This is a convenience wrapper over [dbsetlname] with `which=DBSETUSER`.
  /// - The underlying C function is `dbsetlname(LOGINREC*, const char*, int)`.
  int dbsetluser(Pointer<LOGINREC> login, Pointer<Utf8> username) =>
      dbsetlname(login, username, DBSETUSER);

  /// Set the password on a LOGINREC using the DBSETPWD selector.
  ///
  /// Parameters:
  /// - login: LOGINREC* obtained from [dblogin]. Must be non-null.
  /// - password: UTF-8 pointer to the password string (null-terminated).
  ///
  /// Returns: SUCCEED (1) on success, FAIL (0) on error.
  ///
  /// Notes:
  /// - This is a convenience wrapper over [dbsetlname] with `which=DBSETPWD`.
  /// - The underlying C function is `dbsetlname(LOGINREC*, const char*, int)`.
  int dbsetlpwd(Pointer<LOGINREC> login, Pointer<Utf8> password) =>
      dbsetlname(login, password, DBSETPWD);

  static DBLib load() => DBLib(NativeLoader.loadDBLib());

  // Expose latest DB-Lib error/message captured by installed handlers.
  // These are per-DBPROCESS (or 0 for library-level) and are cleared on read.
  static String? takeLastError(Pointer<DBPROCESS>? dbproc) =>
      _DbLibErrorStore.takeLastError(dbproc);
  static String? takeLastMessage(Pointer<DBPROCESS>? dbproc) =>
      _DbLibErrorStore.takeLastMessage(dbproc);
}

// Simple global store for the latest error/message per DBPROCESS.
class _DbLibErrorStore {
  static final Map<int, String> _lastError = <int, String>{};
  static final Map<int, String> _lastMessage = <int, String>{};
  static String? takeLastError(Pointer<DBPROCESS>? dbproc) {
    final k = dbproc == null || dbproc == nullptr ? 0 : dbproc.address;
    return _lastError.remove(k);
  }

  static void setLastError(Pointer<DBPROCESS>? dbproc, String msg) {
    final k = dbproc == null || dbproc == nullptr ? 0 : dbproc.address;
    _lastError[k] = msg;
  }

  static String? takeLastMessage(Pointer<DBPROCESS>? dbproc) {
    final k = dbproc == null || dbproc == nullptr ? 0 : dbproc.address;
    return _lastMessage.remove(k);
  }

  static void setLastMessage(Pointer<DBPROCESS>? dbproc, String msg) {
    final k = dbproc == null || dbproc == nullptr ? 0 : dbproc.address;
    _lastMessage[k] = msg;
  }
}

// Dart-side error handlers (installed via dberrhandle/dbmsghandle).
int _dartDbErrHandler(
  Pointer<DBPROCESS> dbproc,
  int severity,
  int dberr,
  int oserr,
  Pointer<Utf8> dberrstr,
  Pointer<Utf8> oserrstr,
) {
  // Be extremely defensive: message buffers may not be valid UTF-8.
  String safeFromUtf8(Pointer<Utf8> p) {
    if (p == nullptr) return '';
    try {
      return p.toDartString();
    } catch (_) {
      // Fallback: read up to 4KB, stop at NUL, and decode as latin1 to avoid throws.
      try {
        final bytes = <int>[];
        for (int i = 0; i < 4096; i++) {
          final b = p.cast<Uint8>().elementAt(i).value;
          if (b == 0) break;
          bytes.add(b);
        }
        return const Latin1Codec(allowInvalid: true).decode(bytes);
      } catch (_) {
        return '';
      }
    }
  }

  final msg =
      '[severity=$severity dberr=$dberr oserr=$oserr] '
      '${safeFromUtf8(dberrstr)}'
      '${oserrstr == nullptr ? '' : ' | ${safeFromUtf8(oserrstr)}'}';
  _DbLibErrorStore.setLastError(dbproc, msg);
  return 0; // per DB-Lib docs, return value ignored
}

int _dartDbMsgHandler(
  Pointer<DBPROCESS> dbproc,
  int msgno,
  int msgstate,
  int severity,
  Pointer<Utf8> msgtext,
  Pointer<Utf8> server,
  Pointer<Utf8> proc,
  int line,
) {
  String safeFromUtf8(Pointer<Utf8> p) {
    if (p == nullptr) return '';
    try {
      return p.toDartString();
    } catch (_) {
      try {
        final bytes = <int>[];
        for (int i = 0; i < 4096; i++) {
          final b = p.cast<Uint8>().elementAt(i).value;
          if (b == 0) break;
          bytes.add(b);
        }
        return const Latin1Codec(allowInvalid: true).decode(bytes);
      } catch (_) {
        return '';
      }
    }
  }

  final msg =
      '[msgno=$msgno state=$msgstate severity=$severity line=$line] '
      '${safeFromUtf8(msgtext)}';
  _DbLibErrorStore.setLastMessage(dbproc, msg);
  return 0;
}

// Exposed pointers for installation; keep them alive for the process lifetime.
final Pointer<NativeFunction<_errHandlerSigC>> kErrHandlerPtr =
    Pointer.fromFunction<_errHandlerSigC>(_dartDbErrHandler, 0);
final Pointer<NativeFunction<_msgHandlerSigC>> kMsgHandlerPtr =
    Pointer.fromFunction<_msgHandlerSigC>(_dartDbMsgHandler, 0);

// Helpers to marshal bytes for dbdata()

/// Returns an int value clamped within [min]..[max].
int _clampInt(int v, int min, int max) => v < min ? min : (v > max ? max : v);

/// Cheap ByteData view over the foreign memory pointed to by [ptr] for [len] bytes.
/// Creates a Uint8List view first, then wraps it with ByteData for endian-safe reads.
ByteData _asByteData(Pointer<Uint8> ptr, int len) {
  final bytes = ptr.asTypedList(len);
  return ByteData.view(bytes.buffer, bytes.offsetInBytes, len);
}

/// Decode a DB-Lib value pointed by [ptr]/[len] given its DB-Lib [type].
///
/// - This performs pragmatic, alignment-safe decoding for common scalar types
///   (integers, floats, money, datetime), basic text (char/varchar/ntext/nvarchar),
///   and binary (base64-string).
/// - For complex types (DECIMAL/NUMERIC and newer SQL Server date/time types),
///   prefer [decodeDbValueWithFallback] which can call `dbconvert` to produce
///   strings or doubles.
/// - Returns null if [ptr] is null or [len] <= 0.
dynamic decodeDbValue(int type, Pointer<Uint8> ptr, int len) {
  if (ptr == nullptr || len <= 0) return null;
  final bd =
      (type == SYBINT1 ||
          type == SYBCHAR ||
          type == SYBVARCHAR ||
          type == SYBTEXT ||
          type == SYBNTEXT ||
          type == SYBNVARCHAR)
      ? null
      : _asByteData(
          ptr,
          len,
        ); // avoid ByteData for simple 1-byte or string types
  switch (type) {
    case SYBINTN:
      // Variable-length int: length tells the actual width (1,2,4,8)
      switch (len) {
        case 1:
          return ptr.cast<Uint8>().value;
        case 2:
          return _asByteData(ptr, 2).getInt16(0, Endian.little);
        case 4:
          return _asByteData(ptr, 4).getInt32(0, Endian.little);
        case 8:
          return _asByteData(ptr, 8).getInt64(0, Endian.little);
        default:
          return ptr.asTypedList(len);
      }
    case SYBINT1:
      return ptr.cast<Uint8>().value;
    case SYBINT2:
      return bd!.getInt16(0, Endian.little);
    case SYBINT4:
      return bd!.getInt32(0, Endian.little);
    case SYBINT8:
      return bd!.getInt64(0, Endian.little);
    case SYBREAL:
      return bd!.getFloat32(0, Endian.little);
    case SYBFLT8:
      return bd!.getFloat64(0, Endian.little);
    case SYBFLTN:
      // infer by length
      if (len == 4) return _asByteData(ptr, 4).getFloat32(0, Endian.little);
      if (len == 8) return _asByteData(ptr, 8).getFloat64(0, Endian.little);
      return ptr.asTypedList(len);
    case SYBBIT:
      return ptr.cast<Uint8>().value != 0;
    case SYBBITN:
      return len == 0 ? null : (ptr.cast<Uint8>().value != 0);
    case SYBMONEY:
      {
        // 8-byte money: signed 64-bit scaled by 10000 (SQL Server MONEY)
        final i64 = _asByteData(ptr, 8).getInt64(0, Endian.little);
        return i64 / 10000.0;
      }
    case SYBMONEY4:
      {
        final v = bd!.getInt32(0, Endian.little); // scaled by 10000
        return v / 10000.0;
      }
    case SYBDATETIME:
      {
        // DBDATETIME: days since 1900-01-01, time in 1/300 sec units
        final days = bd!.getInt32(0, Endian.little);
        final time300 = bd.getInt32(4, Endian.little);
        final base = DateTime(1900, 1, 1);
        final date = base.add(Duration(days: days));
        final micros = (time300 * 1000000) ~/ 300;
        final dt = date.add(Duration(microseconds: micros));
        return dt.toIso8601String();
      }
    case SYBDATETIME4:
      {
        // DBDATETIME4: USMALLINT days since 1900-01-01, USMALLINT minutes since midnight
        final days = bd!.getUint16(0, Endian.little);
        final minutes = bd.getUint16(2, Endian.little);
        final base = DateTime(1900, 1, 1);
        final dt = base.add(Duration(days: days, minutes: minutes));
        return dt.toIso8601String();
      }
    case SYBBINARY:
    case SYBVARBINARY:
    case SYBIMAGE:
      {
        final bytes = ptr.asTypedList(len);
        return base64.encode(bytes);
      }
    case SYBCHAR:
    case SYBVARCHAR:
    case SYBTEXT:
      {
        final bytes = ptr.asTypedList(len);
        if (_looksUtf16LeText(bytes)) return _utf16leDecode(bytes);
        return utf8.decode(bytes, allowMalformed: true);
      }
    case SYBNTEXT:
    case SYBNVARCHAR:
      {
        // NVARCHAR/NTEXT are UTF-16LE; dbdatlen returns the byte length.
        // Decode exactly [len] bytes as UTF-16LE.
        final bytes = ptr.asTypedList(len);
        return _utf16leDecode(bytes);
      }
    // For DECIMAL/NUMERIC/DATETIME, you may need proper conversion against TDS metadata.
    default:
      return ptr.asTypedList(len); // fallback raw bytes
  }
}

/// Decode with dbconvert fallback: for any unhandled type, try to stringify to SYBVARCHAR.
///
/// Strategy:
/// - First, call [decodeDbValue] for fast-path common types.
/// - If the result is raw bytes (Uint8List), attempt to convert to a readable string
///   via `dbconvert(..., SYBVARCHAR, ...)`.
/// - For DECIMAL/NUMERIC specifically, try to coerce directly to double using
///   `SYBFLT8` before falling back to string. This yields a native number shape.
/// - As a last resort, base64-encode raw bytes for JSON-safety.
dynamic decodeDbValueWithFallback(
  DBLib db,
  Pointer<DBPROCESS> dbproc,
  int type,
  Pointer<Uint8> ptr,
  int len,
) {
  // Prefer native decode first
  final v = decodeDbValue(type, ptr, len);
  // Directly convert DECIMAL/NUMERIC to double if undecoded
  if ((type == SYBDECIMAL || type == SYBNUMERIC) &&
      v is Uint8List &&
      ptr != nullptr &&
      len > 0) {
    final dest = malloc<Uint8>(8);
    try {
      final outLen = db.dbconvert(dbproc, type, ptr, len, SYBFLT8, dest, 8);
      if (outLen == 8) {
        return dest.cast<Double>().value;
      }
    } catch (_) {
      // ignore and fall back to string
    } finally {
      malloc.free(dest);
    }
  }
  if (v is Uint8List) {
    final s = tryConvertToString(db, dbproc, type, ptr, len);
    if (s != null) return s;
    // Last resort: base64 the raw bytes for JSON-safety
    return base64.encode(v);
  }
  return v;
}

/// Attempt to stringify a value of any DB-Lib type using `dbconvert -> SYBVARCHAR`.
///
/// - Useful for complex/driver-specific encodings (e.g., DECIMAL/NUMERIC, DATE/TIME/DT2/OFFSET)
///   where manual decoding would require TDS metadata (scale/precision).
/// - Returns a UTF-8 Dart String on success; null if conversion fails.
String? tryConvertToString(
  DBLib db,
  Pointer<DBPROCESS> dbproc,
  int srcType,
  Pointer<Uint8> src,
  int srcLen,
) {
  if (src == nullptr || srcLen <= 0) return null;
  // Heuristic buffer size: up to 4x source length plus headroom, capped.
  final int maxLen = _clampInt(srcLen * 4 + 64, 128, 65536);
  final dest = malloc<Uint8>(maxLen);
  try {
    final outLen = db.dbconvert(
      dbproc,
      srcType,
      src,
      srcLen,
      SYBVARCHAR,
      dest,
      maxLen,
    );
    if (outLen <= 0) return null;
    final bytes = dest.asTypedList(outLen);
    return utf8.decode(bytes, allowMalformed: true);
  } catch (_) {
    return null;
  } finally {
    malloc.free(dest);
  }
}
