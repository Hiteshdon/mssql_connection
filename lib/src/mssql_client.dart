import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'ffi/freetds_bindings.dart';
import 'native_logger.dart';

class MssqlClient {
  final String server;
  final String username;
  final String password;

  DBLib? _db;
  Pointer<DBPROCESS>? _dbproc;
  bool _connected = false;

  MssqlClient({
    required this.server,
    required this.username,
    required this.password,
  });

  bool get isConnected => _connected;

  /// Establish a DB-Lib connection to [server] using [username]/[password].
  ///
  /// Steps:
  /// 1) Load and initialize DB-Lib (dbinit)
  /// 1.1) Set login timeout via dbsetlogintime([loginTimeoutSeconds])
  /// 2) Allocate a LOGINREC (dblogin)
  /// 3) Set credentials (dbsetluser/dbsetlpwd)
  /// 4) Enable BCP option on the login (best-effort)
  /// 5) Open a DBPROCESS to the server (dbopen)
  ///
  /// Returns true on success; false if any step fails. All native buffers
  /// for username/password/server are freed after use.
  ///
  /// [loginTimeoutSeconds] controls how long DB-Lib waits to establish a socket
  /// connection/login before failing. Default is 15 seconds.
  ///
  /// Logging: emits lines in the form `connect | key=value | ...` for traceability.
  Future<bool> connect({int loginTimeoutSeconds = 15}) async {
    if (_connected) {
      MssqlLogger.i('connect | already-connected=true');
      return true;
    }
    try {
      MssqlLogger.i('connect | op=init | status=start');
      _db ??= DBLib.load();
      _db!.dbinit();

      // Configure login timeout (best set before attempting to connect)
      try {
        final rc = _db!.dbsetlogintime(loginTimeoutSeconds);
        MssqlLogger.i(
          'connect | op=dbsetlogintime | seconds=$loginTimeoutSeconds | rc=$rc',
        );
      } catch (e) {
        MssqlLogger.w('connect | op=dbsetlogintime | error=$e');
      }

      MssqlLogger.i('connect | op=dblogin');
      final login = _db!.dblogin();
      if (login == nullptr) {
        MssqlLogger.e('connect | op=dblogin | error=nullptr');
        return false;
      }

      final u = username.toNativeUtf8();
      final p = password.toNativeUtf8();
      try {
        MssqlLogger.i('connect | op=dbsetluser');
        final su = _db!.dbsetluser(login, u);
        MssqlLogger.i('connect | op=dbsetluser | rc=$su');

        MssqlLogger.i('connect | op=dbsetlpwd');
        final sp = _db!.dbsetlpwd(login, p);
        MssqlLogger.i('connect | op=dbsetlpwd | rc=$sp');

        if (su != SUCCEED || sp != SUCCEED) {
          MssqlLogger.e(
            'connect | op=credentials | su=$su | sp=$sp | error=fail',
          );
          return false;
        }

        // Enable BCP on this login so that bulk insert APIs are available on the session.
        try {
          final rcBcp = _db!.dbsetlbool(login, DBSETBCP, 1);
          MssqlLogger.i(
            'connect | op=dbsetlbool | option=DBSETBCP | value=1 | rc=$rcBcp',
          );
        } catch (e) {
          MssqlLogger.w(
            'connect | op=dbsetlbool | option=DBSETBCP | value=1 | error=$e',
          );
        }
      } finally {
        malloc.free(u);
        malloc.free(p);
      }

      final srv = server.toNativeUtf8();
      try {
        MssqlLogger.i('connect | op=dbopen | server=$server');
        _dbproc = _db!.dbopen(login, srv);
      } finally {
        malloc.free(srv);
      }

      if (_dbproc == nullptr) {
        MssqlLogger.e('connect | op=dbopen | server=$server | error=nullptr');
        return false;
      }

      _connected = true;
      MssqlLogger.i('connect | status=connected | server=$server');
      return true;
    } catch (e, st) {
      MssqlLogger.e('connect | exception=$e');
      MssqlLogger.w('connect | stacktrace=\n$st');
      return false;
    }
  }

  /// Close the active DBPROCESS if connected and mark the client disconnected.
  ///
  /// Behavior:
  /// - If no active connection exists, returns immediately (idempotent).
  /// - Calls dbclose(DBPROCESS*) and logs the return code.
  /// - Clears the internal DBPROCESS pointer and connected flag.
  ///
  /// Note: This does not call dbexit(); the library remains loaded for reuse.
  /// Logging: emits lines in the form `close | key=value | ...` for traceability.
  Future<void> close() async {
    MssqlLogger.i('close | requested=true');
    if (_dbproc == null || _dbproc == nullptr) {
      _connected = false;
      MssqlLogger.i('close | no-active=true | status=disconnected');
      return;
    }
    try {
      MssqlLogger.i('close | op=dbclose');
      final rc = _db!.dbclose(_dbproc!);
      MssqlLogger.i('close | op=dbclose | rc=$rc');
    } catch (e) {
      MssqlLogger.w('close | op=dbclose | error=$e');
    } finally {
      _dbproc = null;
      _connected = false;
      MssqlLogger.i('close | status=disconnected');
    }
  }

  /// Bulk insert rows into [tableName].
  ///
  /// [rows] should be a non-empty list of homogeneous maps.
  /// If [columns] is not provided, the keys of the first row (iteration order)
  /// are used as the column order.
  /// Returns the number of rows successfully copied.
  Future<int> bulkInsert(
    String tableName,
    List<Map<String, dynamic>> rows, {
    List<String>? columns,
    int batchSize = 1000,
  }) async {
    _ensureConnected();
    if (rows.isEmpty) return 0;
    final db = _db!;
    final dbproc = _dbproc!;

    // Determine columns
    final cols = (columns != null && columns.isNotEmpty)
        ? List<String>.from(columns)
        : rows.first.keys.toList(growable: false);

    // Initialize BCP
    final tbl = tableName.toNativeUtf8();
    try {
      final rcInit = db.bcp_init(dbproc, tbl, nullptr, nullptr, DB_IN);
      if (rcInit != SUCCEED) {
        throw StateError('bcp_init failed for $tableName');
      }

      // Bind columns with host types; varaddr NULL, varlen -1, no terminator
      final hostTypes = <int>[];
      for (var i = 0; i < cols.length; i++) {
        final sample = rows.first[cols[i]];
        final htype = _hostTypeFor(sample);
        hostTypes.add(htype);
        final rcBind = db.bcp_bind(
          dbproc,
          nullptr,
          0,
          -1,
          nullptr,
          0,
          htype,
          i + 1,
        );
        if (rcBind != SUCCEED) {
          throw StateError('bcp_bind failed for column ${i + 1}');
        }
      }

      int sent = 0;
      int total = 0;

      // Row buffers per column allocated per row (freed after send)
      for (final row in rows) {
        final allocs = <_TempBuf>[];
        try {
          // Set data pointers/lengths for this row
          for (var i = 0; i < cols.length; i++) {
            final v = row[cols[i]];
            if (v == null) {
              // Indicate NULL
              db.bcp_collen(dbproc, -1, i + 1);
              db.bcp_colptr(dbproc, nullptr, i + 1);
              continue;
            }
            final buf = _encodeForHost(hostTypes[i], v);
            allocs.add(buf);
            db.bcp_collen(dbproc, buf.length, i + 1);
            db.bcp_colptr(dbproc, buf.ptr.cast<Uint8>(), i + 1);
          }

          // Send the row
          final rcSend = db.bcp_sendrow(dbproc);
          if (rcSend != SUCCEED) {
            throw StateError('bcp_sendrow failed');
          }
          sent++;

          // Batch if needed
          if (batchSize > 0 && (sent % batchSize == 0)) {
            final b = db.bcp_batch(dbproc);
            if (b < 0) {
              throw StateError('bcp_batch failed');
            }
            total += b;
          }
        } finally {
          // Free allocated buffers for this row
          for (final a in allocs) {
            malloc.free(a.ptr);
          }
        }
      }

      // Finalize
      final done = db.bcp_done(dbproc);
      if (done < 0) {
        throw StateError('bcp_done failed');
      }
      total += done;
      return total;
    } finally {
      malloc.free(tbl);
    }
  }

  /// Execute a plain SQL text command and return a JSON payload.
  ///
  /// Returns a JSON String of the form:
  /// { columns: [..], rows: [ {col:val,..}, ..], affected: (int), error?: (string) }
  ///
  /// Logging: emits lines in the form `execute | key=value | ...`.
  Future<String> execute(String sql) async {
    _ensureConnected();
    final db = _db!;
    final dbproc = _dbproc!;

    final cmd = sql.toNativeUtf8();
    try {
      MssqlLogger.i('execute | op=dbcmd | sqlLen=${sql.length}');
      final rc1 = db.dbcmd(dbproc, cmd);
      if (rc1 != SUCCEED) {
        MssqlLogger.e('execute | op=dbcmd | rc=$rc1 | error=fail');
        return jsonEncode({
          'rows': <dynamic>[],
          'affected': 0,
          'error': 'dbcmd failed',
        });
      }
      MssqlLogger.i('execute | op=dbsqlexec');
      final rc2 = db.dbsqlexec(dbproc);
      if (rc2 != SUCCEED) {
        MssqlLogger.e('execute | op=dbsqlexec | rc=$rc2 | error=fail');
        return jsonEncode({
          'rows': <dynamic>[],
          'affected': 0,
          'error': 'dbsqlexec failed',
        });
      }

      return _collectResults(db, dbproc);
    } finally {
      malloc.free(cmd);
    }
  }

  /// Execute parameterized SQL via DB-Lib RPC to sp_executesql and return JSON.
  ///
  /// - [sql]: text with @param placeholders (e.g., SELECT * FROM T WHERE c=@p)
  /// - [params]: map of parameterName -> value (name can include or omit leading @)
  ///
  /// This uses the DB-Lib RPC path:
  /// 1) dbrpcinit(dbproc, 'sp_executesql', 0)
  /// 2) dbrpcparam for @stmt (NVARCHAR) and @params (NVARCHAR)
  /// 3) dbrpcparam for each user parameter (typed, binary-safe)
  /// 4) dbrpcsend + dbsqlok, then results are collected via [_collectResults].
  ///
  /// Benefits: avoids string concatenation and quoting, preserves types, and
  /// leverages the server to plan/execute with true parameters.
  ///
  /// Logging: emits lines in the form `executeParams | key=value | ...`.
  Future<String> executeParams(String sql, Map<String, dynamic> params) async {
    _ensureConnected();
    final db = _db!;
    final dbproc = _dbproc!;

    // Normalize param names to include '@'
    final norm = <String, dynamic>{};
    params.forEach((k, v) => norm[_normalizeParamName(k)] = v);
    MssqlLogger.i('executeParams | op=normalize | count=${norm.length}');

    // Build parameter declaration string (e.g., "@p1 int, @p2 nvarchar(max)")
    final decls = <String>[];
    for (final e in norm.entries) {
      final declType = _inferSqlType(e.value);
      decls.add('${e.key} $declType');
    }
    final declStr = decls.join(', ');

    // Prepare RPC call: sp_executesql(@stmt NVARCHAR(MAX), @params NVARCHAR(MAX), <params...>)
    final rpcName = 'sp_executesql'.toNativeUtf8();
    final stmtUtf16 = _utf16leEncode(sql);
    final paramsUtf16 = _utf16leEncode(declStr);

    // Allocate native buffers for @stmt and @params
    Pointer<Uint8>? stmtPtr;
    Pointer<Uint8>? paramsPtr;
    final tempAllocations = <_TempBuf>[]; // values for user params

    try {
      MssqlLogger.i('executeParams | op=dbrpcinit | rpc=sp_executesql');
      final rcInit = db.dbrpcinit(dbproc, rpcName, 0);
      if (rcInit != SUCCEED) {
        MssqlLogger.e('executeParams | op=dbrpcinit | rc=$rcInit | error=fail');
        return jsonEncode({
          'rows': <dynamic>[],
          'affected': 0,
          'error': 'dbrpcinit failed',
        });
      }

      // @stmt NVARCHAR
      stmtPtr = malloc<Uint8>(stmtUtf16.length);
      stmtPtr.asTypedList(stmtUtf16.length).setAll(0, stmtUtf16);
      final nameStmt = '@stmt'.toNativeUtf8();
      final rcP1 = db.dbrpcparam(
        dbproc,
        nameStmt,
        0,
        SYBNVARCHAR,
        stmtUtf16.length,
        stmtUtf16.length,
        stmtPtr,
      );
      malloc.free(nameStmt);
      if (rcP1 != SUCCEED) {
        MssqlLogger.e(
          'executeParams | op=dbrpcparam | name=@stmt | rc=$rcP1 | error=fail',
        );
        return jsonEncode({
          'rows': <dynamic>[],
          'affected': 0,
          'error': 'dbrpcparam @stmt failed',
        });
      }

      // @params NVARCHAR (can be empty)
      paramsPtr = malloc<Uint8>(paramsUtf16.length);
      paramsPtr.asTypedList(paramsUtf16.length).setAll(0, paramsUtf16);
      final nameParams = '@params'.toNativeUtf8();
      final rcP2 = db.dbrpcparam(
        dbproc,
        nameParams,
        0,
        SYBNVARCHAR,
        paramsUtf16.length,
        paramsUtf16.length,
        paramsPtr,
      );
      malloc.free(nameParams);
      if (rcP2 != SUCCEED) {
        MssqlLogger.e(
          'executeParams | op=dbrpcparam | name=@params | rc=$rcP2 | error=fail',
        );
        return jsonEncode({
          'rows': <dynamic>[],
          'affected': 0,
          'error': 'dbrpcparam @params failed',
        });
      }

      // User parameters: add in the same order as declarations
      for (final e in norm.entries) {
        final name = e.key; // includes @
        final value = e.value;
        final rpcVal = _encodeForRpc(value);
        tempAllocations.add(rpcVal.buf);
        final cname = name.toNativeUtf8();
        final rcPi = db.dbrpcparam(
          dbproc,
          cname,
          0, // input param
          rpcVal.type,
          rpcVal.buf.length,
          rpcVal.buf.length,
          rpcVal.buf.ptr,
        );
        malloc.free(cname);
        if (rcPi != SUCCEED) {
          MssqlLogger.e(
            'executeParams | op=dbrpcparam | name=$name | rc=$rcPi | error=fail',
          );
          return jsonEncode({
            'rows': <dynamic>[],
            'affected': 0,
            'error': 'dbrpcparam failed',
          });
        }
      }

      MssqlLogger.i('executeParams | op=dbrpcsend');
      final rcSend = db.dbrpcsend(dbproc);
      if (rcSend != SUCCEED) {
        MssqlLogger.e('executeParams | op=dbrpcsend | rc=$rcSend | error=fail');
        return jsonEncode({
          'rows': <dynamic>[],
          'affected': 0,
          'error': 'dbrpcsend failed',
        });
      }

      MssqlLogger.i('executeParams | op=dbsqlok');
      final rcOk = db.dbsqlok(dbproc);
      if (rcOk != SUCCEED) {
        MssqlLogger.e('executeParams | op=dbsqlok | rc=$rcOk | error=fail');
        return jsonEncode({
          'rows': <dynamic>[],
          'affected': 0,
          'error': 'dbsqlok failed',
        });
      }

      // Read results via shared collector
      return _collectResults(db, dbproc);
    } finally {
      // Free buffers for @stmt/@params and user param values
      if (stmtPtr != null) malloc.free(stmtPtr);
      if (paramsPtr != null) malloc.free(paramsPtr);
      for (final t in tempAllocations) {
        malloc.free(t.ptr);
      }
      malloc.free(rpcName);
    }
  }
  // --- Internals ---

  /// Collect rows and counts from the DB-Lib results pipeline.
  ///
  /// Behavior and design:
  /// - Iterates dbresults() until NO_MORE_RESULTS.
  /// - Captures column metadata from the first result set with columns only;
  ///   subsequent row-bearing result sets are ignored to keep the return shape
  ///   stable (single columns + rows list). Row counts from all sets are
  ///   aggregated via dbcount().
  /// - Decodes each value using decodeDbValueWithFallback() for safety.
  ///
  /// Logging: emits standardized lines prefixed with `collectResults`.
  ///
  /// Returns JSON: { columns: [...], rows: [...], affected: (int), error?: (string) }
  String _collectResults(DBLib db, Pointer<DBPROCESS> dbproc) {
    final rows = <Map<String, dynamic>>[];
    final columns = <String>[];
    int affectedTotal = 0;
    bool capturedFirstSet = false;
    String? error;

    MssqlLogger.i('collectResults | op=start');
    int setIndex = 0;
    while (true) {
      final r = db.dbresults(dbproc);
      if (r == NO_MORE_RESULTS) {
        MssqlLogger.i('collectResults | op=dbresults | result=$r | status=end');
        break;
      }
      if (r != SUCCEED) {
        error = 'dbresults failed (rc=$r)';
        MssqlLogger.e('collectResults | op=dbresults | rc=$r | error=fail');
        break;
      }
      setIndex++;
      final ncols = db.dbnumcols(dbproc);
      MssqlLogger.i('collectResults | op=set | index=$setIndex | ncols=$ncols');
      final types = List<int>.filled(ncols, 0);
      // Cache column names and types for efficiency
      if (ncols > 0 && !capturedFirstSet) {
        for (var i = 1; i <= ncols; i++) {
          final cptr = db.dbcolname(dbproc, i);
          types[i - 1] = db.dbcoltype(dbproc, i);
          final name = cptr == nullptr ? 'col$i' : cptr.toDartString();
          columns.add(name);
        }
        capturedFirstSet = true;
        MssqlLogger.i('collectResults | op=columns | count=${columns.length}');
      }

      // Fetch rows only for the first schema-bearing result set
      int fetched = 0;
      if (ncols > 0 && capturedFirstSet && columns.isNotEmpty) {

        while (true) {
          final nr = db.dbnextrow(dbproc);
          if (nr == NO_MORE_ROWS) break;
          if (nr != REG_ROW && nr != MORE_ROWS) {
            MssqlLogger.w(
              'collectResults | op=dbnextrow | rc=$nr | warning=unexpected',
            );
            break;
          }
          final row = <String, dynamic>{};
          for (var i = 1; i <= ncols; i++) {
            final name = i <= columns.length ? columns[i - 1] : 'col$i';
            final t = types[i - 1];
            final len = db.dbdatlen(dbproc, i);
            final ptr = db.dbdata(dbproc, i);
            final v = decodeDbValueWithFallback(db, dbproc, t, ptr, len);
            row[name] = v;
          }
          rows.add(row);
          fetched++;
        }
        MssqlLogger.i(
          'collectResults | op=rows | set=$setIndex | fetched=$fetched',
        );
      } else if (ncols > 0) {
        // If this is a second schema-bearing set, skip its rows for shape stability
        MssqlLogger.w(
          'collectResults | op=skip-rows | set=$setIndex | reason=secondary-schema',
        );
        // Drain rows without collecting
        while (true) {
          final nr = db.dbnextrow(dbproc);
          if (nr == NO_MORE_ROWS) break;
          if (nr != REG_ROW && nr != MORE_ROWS) break;
        }
      }

      // Accumulate affected rows for this set
      try {
        final c = db.dbcount(dbproc);
        affectedTotal += c;
        MssqlLogger.i(
          'collectResults | op=dbcount | set=$setIndex | value=$c | total=$affectedTotal',
        );
      } catch (e) {
        MssqlLogger.w('collectResults | op=dbcount | set=$setIndex | error=$e');
      }
    }

    final result = <String, dynamic>{
      'columns': columns,
      'rows': rows,
      'affected': affectedTotal,
    };
    if (error != null) result['error'] = error;
    MssqlLogger.i(
      'collectResults | status=done | rows=${rows.length} | affected=$affectedTotal',
    );
    return jsonEncode(result);
  }

  void _ensureConnected() {
    if (!_connected || _dbproc == null || _dbproc == nullptr) {
      throw StateError('Not connected. Call connect() first.');
    }
  }

  static String _normalizeParamName(String name) =>
      name.startsWith('@') ? name : '@$name';

  static String _inferSqlType(dynamic v) {
    if (v == null) return 'sql_variant'; // value will be NULL
    if (v is bool) return 'bit';
    if (v is int) {
      // choose bigint if outside 32-bit range
      if (v < -2147483648 || v > 2147483647) return 'bigint';
      return 'int';
    }
    if (v is double) return 'float';
    if (v is String) return 'nvarchar(max)';
    if (v is DateTime) return 'datetime2';
    if (v is Uint8List) return 'varbinary(max)';
    // Fallback to NVARCHAR
    return 'nvarchar(max)';
  }
}

class _TempBuf {
  final Pointer<Uint8> ptr;
  final int length;
  _TempBuf(this.ptr, this.length);
}

class _RpcVal {
  final int type; // DB-Lib type code for dbrpcparam
  final _TempBuf buf;
  _RpcVal(this.type, this.buf);
}

int _hostTypeFor(dynamic v) {
  if (v is int) {
    if (v < -2147483648 || v > 2147483647) return SYBINT8;
    return SYBINT4;
  }
  if (v is double) return SYBFLT8;
  if (v is bool) return SYBBIT;
  if (v is Uint8List) return SYBVARBINARY;
  // Default to varchar for everything else (String/DateTime/etc.)
  return SYBVARCHAR;
}

_TempBuf _encodeForHost(int hostType, dynamic v) {
  switch (hostType) {
    case SYBINT4:
      {
        final p = malloc<Int32>();
        p.value = (v as int);
        return _TempBuf(p.cast<Uint8>(), 4);
      }
    case SYBINT8:
      {
        final p = malloc<Int64>();
        p.value = (v as int);
        return _TempBuf(p.cast<Uint8>(), 8);
      }
    case SYBFLT8:
      {
        final p = malloc<Double>();
        p.value = (v as double);
        return _TempBuf(p.cast<Uint8>(), 8);
      }
    case SYBBIT:
      {
        final p = malloc<Uint8>();
        p.value = (v as bool) ? 1 : 0;
        return _TempBuf(p.cast<Uint8>(), 1);
      }
    case SYBVARBINARY:
      {
        final bytes = (v as Uint8List);
        final p = malloc<Uint8>(bytes.length);
        p.asTypedList(bytes.length).setAll(0, bytes);
        return _TempBuf(p, bytes.length);
      }
    case SYBVARCHAR:
    default:
      {
        final s = (v is String)
            ? v
            : (v is DateTime)
            ? v.toIso8601String()
            : v.toString();
        final bytes = utf8.encode(s);
        final p = malloc<Uint8>(bytes.length);
        p.asTypedList(bytes.length).setAll(0, bytes);
        return _TempBuf(p, bytes.length);
      }
  }
}

// --- RPC encoding helpers ---

// Encode a Dart String into UTF-16LE bytes (no terminator).
Uint8List _utf16leEncode(String s) {
  final codes = s.codeUnits; // UTF-16 code units
  final out = Uint8List(codes.length * 2);
  for (var i = 0; i < codes.length; i++) {
    final c = codes[i];
    out[i * 2] = c & 0xFF;
    out[i * 2 + 1] = (c >> 8) & 0xFF;
  }
  return out;
}

// Map a Dart value to a DB-Lib type code and native buffer suitable for dbrpcparam.
// For safety and simplicity, most complex types are passed as NVARCHAR and
// converted server-side according to the declared SQL type in sp_executesql.
_RpcVal _encodeForRpc(dynamic v) {
  if (v == null) {
    // Represent NULL by zero-length buffer of any type; server will see NULL
    // when dbrpcparam datalen is 0.
    final p = malloc<Uint8>(0);
    return _RpcVal(SYBNVARCHAR, _TempBuf(p, 0));
  }
  if (v is bool) {
    final p = malloc<Uint8>();
    p.value = v ? 1 : 0;
    return _RpcVal(SYBBIT, _TempBuf(p, 1));
  }
  if (v is int) {
    if (v < -2147483648 || v > 2147483647) {
      final p = malloc<Int64>();
      p.value = v;
      return _RpcVal(SYBINT8, _TempBuf(p.cast<Uint8>(), 8));
    } else {
      final p = malloc<Int32>();
      p.value = v;
      return _RpcVal(SYBINT4, _TempBuf(p.cast<Uint8>(), 4));
    }
  }
  if (v is double) {
    final p = malloc<Double>();
    p.value = v;
    return _RpcVal(SYBFLT8, _TempBuf(p.cast<Uint8>(), 8));
  }
  if (v is Uint8List) {
    final p = malloc<Uint8>(v.length);
    p.asTypedList(v.length).setAll(0, v);
    return _RpcVal(SYBVARBINARY, _TempBuf(p, v.length));
  }
  // Strings, DateTime, and other objects -> NVARCHAR
  final s = (v is String)
      ? v
      : (v is DateTime)
      ? v.toUtc().toIso8601String()
      : v.toString();
  final bytes = _utf16leEncode(s);
  final p = malloc<Uint8>(bytes.length);
  p.asTypedList(bytes.length).setAll(0, bytes);
  return _RpcVal(SYBNVARCHAR, _TempBuf(p, bytes.length));
}
