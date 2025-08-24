// High-level Dart API wrapping FreeTDS DB-Lib via FFI.
// Design:
// - MssqlClient manages a DBPROCESS handle and exposes:
//   - connect()/close() returning bool and ensuring cleanup
//   - query(sql) returning JSON list of rows
//   - execute(sql) returning JSON object with affected rows
//   - queryParams/executeParams via sp_executesql using DB-Lib RPC
//   - bulkInsert using DB-Lib BCP subset (row-wise binding)
// - All results are JSON-encoded for consistent app-layer consumption.

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'ffi/freetds_bindings.dart';

class MssqlClient {
  final String server;
  final String username;
  final String password;
  final DBLib _db = DBLib.load();

  Pointer<DBPROCESS> _dbproc = nullptr;
  bool _initialized = false;

  MssqlClient({
    required this.server,
    required this.username,
    required this.password,
  });

  Future<bool> connect() async {
    return Future(() {
      try {
        if (!_initialized) {
          _db.dbinit();
          _initialized = true;
        }
        final login = _db.dblogin();
        if (login == nullptr) return false;

        final u = username.toNativeUtf8();
        final p = password.toNativeUtf8();
        _db.DBSETLUSER(login, u);
        _db.DBSETLPWD(login, p);
        malloc.free(u);
        malloc.free(p);

        final srv = server.toNativeUtf8();
        _dbproc = _db.dbopen(login, srv);
        malloc.free(srv);
        // login rec is managed per DB-Lib; many builds auto-free after dbopen
        return _dbproc != nullptr;
      } catch (_) {
        return false;
      }
    });
  }

  Future<void> close() async {
    return Future(() {
      if (_dbproc != nullptr) {
        _db.dbclose(_dbproc);
        _dbproc = nullptr;
      }
      if (_initialized) {
        _db.dbexit();
        _initialized = false;
      }
    });
  }

  // Execute a SELECT and return JSON list of rows.
  Future<String> query(String sql) async {
    return Future(() {
      _ensureConnected();

      final cmd = sql.toNativeUtf8();
      final rc1 = _db.dbcmd(_dbproc, cmd);
      malloc.free(cmd);
      if (rc1 != SUCCEED) {
        return jsonEncode({"ok": false, "error": "dbcmd failed"});
      }
      final rc2 = _db.dbsqlexec(_dbproc);
      if (rc2 != SUCCEED) {
        return jsonEncode({"ok": false, "error": "dbsqlexec failed"});
      }

      final rows = <Map<String, dynamic>>[];
      while (true) {
        final res = _db.dbresults(_dbproc);
        if (res == NO_MORE_RESULTS) break;
        if (res == FAIL) {
          return jsonEncode({"ok": false, "error": "dbresults failed"});
        }

        final ncols = _db.dbnumcols(_dbproc);
        final colNames = <String>[];
        final colTypes = <int>[];
        for (var c = 1; c <= ncols; c++) {
          colNames.add(_db.dbcolname(_dbproc, c).toDartString());
          colTypes.add(_db.dbcoltype(_dbproc, c));
        }

        while (true) {
          final r = _db.dbnextrow(_dbproc);
          if (r == NO_MORE_RESULTS || r == FAIL) break;
          final row = <String, dynamic>{};
          for (var c = 1; c <= ncols; c++) {
            final len = _db.dbdatlen(_dbproc, c);
            final dataPtr = _db.dbdata(_dbproc, c);
            row[colNames[c - 1]] = decodeDbValueWithFallback(_db, _dbproc, colTypes[c - 1], dataPtr, len);
          }
          rows.add(row);
        }
      }

      return jsonEncode({"ok": true, "rows": rows});
    });
  }

  // Execute DML/DDL and return JSON with affected rows (if available).
  Future<String> execute(String sql) async {
    return Future(() {
      _ensureConnected();

      final cmd = sql.toNativeUtf8();
      final rc1 = _db.dbcmd(_dbproc, cmd);
      malloc.free(cmd);
      if (rc1 != SUCCEED) {
        return jsonEncode({"ok": false, "error": "dbcmd failed"});
      }
      final rc2 = _db.dbsqlexec(_dbproc);
      if (rc2 != SUCCEED) {
        return jsonEncode({"ok": false, "error": "dbsqlexec failed"});
      }

      // Consume results, track rows affected if driver reports them.
      int totalAffected = 0;
      while (true) {
        final res = _db.dbresults(_dbproc);
        if (res == NO_MORE_RESULTS) break;
        if (res == FAIL) {
          return jsonEncode({"ok": false, "error": "dbresults failed"});
        }
        // Some drivers expose rows affected as a rowset or status; FreeTDS typically
        // reports via a final status. For simplicity, ignore unless surfaced as rows.
        while (true) {
          final r = _db.dbnextrow(_dbproc);
          if (r == NO_MORE_RESULTS || r == FAIL) break;
          // Ignore row content here for mutations; alternatively collect status.
          totalAffected++; // heuristic if a status rowset returns 1 row
        }
      }
      return jsonEncode({"ok": true, "affected": totalAffected});
    });
  }

  // Parameterized query via sp_executesql using DB-Lib RPC calls.
  // params: map of @name -> value (Dart types: int, double, bool, String, DateTime)
  // types: optional map of @name -> TDS type code (SYBINT4, SYBVARCHAR, ...)
  Future<String> queryParams(String sql, Map<String, dynamic> params, {Map<String, int>? types}) async {
    return _execSpExecuteSql(sql, params, types, isSelect: true);
  }

  Future<String> executeParams(String sql, Map<String, dynamic> params, {Map<String, int>? types}) async {
    return _execSpExecuteSql(sql, params, types, isSelect: false);
  }

  // Bulk insert: rows as list of arrays matching table column order and types list per column.
  Future<String> bulkInsert(String table, List<List<dynamic>> rows, List<int> tdsTypes) async {
    return Future(() {
      _ensureConnected();

      final tbl = table.toNativeUtf8();
      final rc = _db.bcp_init(_dbproc, tbl, nullptr, nullptr, DB_IN);
      malloc.free(tbl);
      if (rc != SUCCEED) {
        return jsonEncode({"ok": false, "error": "bcp_init failed"});
      }

      // Bind each column per ordinal (1-based in DB-Lib).
      for (var col = 0; col < tdsTypes.length; col++) {
        final type = tdsTypes[col];
        // We bind per row below by rebinding the pointer; FreeTDS allows row-wise bcp_bind with varaddr
        // Prefix/terminator disabled, variable length allowed.
      }

      int sent = 0;
      for (final row in rows) {
        final allocated = <Pointer<Uint8>>[];
        try {
          for (var col = 0; col < row.length; col++) {
            final v = row[col];
            final type = tdsTypes[col];
            // Encode value to bytes for the column
            final enc = _encodeValue(type, v);
            final ptr = malloc<Uint8>(enc.length);
            allocated.add(ptr);
            ptr.asTypedList(enc.length).setAll(0, enc);
            // varnum is 1-based column ordinal
            final rcBind = _db.bcp_bind(_dbproc, ptr, 0, enc.length, nullptr, 0, type, col + 1);
            if (rcBind != SUCCEED) {
              return jsonEncode({"ok": false, "error": "bcp_bind failed at col ${col + 1}"});
            }
          }
          final rcSend = _db.bcp_sendrow(_dbproc);
          if (rcSend != SUCCEED) {
            return jsonEncode({"ok": false, "error": "bcp_sendrow failed"});
          }
          sent++;
        } finally {
          for (final p in allocated) {
            malloc.free(p);
          }
        }
        // Optional: call bcp_batch() periodically for large batches
      }
      _db.bcp_batch(_dbproc); // finalize current batch
      final done = _db.bcp_done(_dbproc);
      return jsonEncode({"ok": true, "inserted": sent, "done": done});
    });
  }

  // Internal helpers

  void _ensureConnected() {
    if (_dbproc == nullptr) {
      throw StateError('Not connected');
    }
  }

  Uint8List _encodeValue(int tdsType, dynamic v) {
    if (v == null) return Uint8List(0);
    switch (tdsType) {
      case SYBINT1:
        return Uint8List.fromList([(v as num).toInt() & 0xFF]);
      case SYBINT2: {
        final b = malloc<Int16>(); b.value = (v as num).toInt();
        final out = b.cast<Uint8>().asTypedList(2).toList();
        malloc.free(b);
        return Uint8List.fromList(out);
      }
      case SYBINT4:
        final b = malloc<Int32>(); b.value = v as int;
        final out = b.cast<Uint8>().asTypedList(4).toList();
        malloc.free(b);
        return Uint8List.fromList(out);
      case SYBINT8:
        final b = malloc<Int64>(); b.value = v as int;
        final out = b.cast<Uint8>().asTypedList(8).toList();
        malloc.free(b);
        return Uint8List.fromList(out);
      case SYBREAL: {
        final b = malloc<Float>(); b.value = (v as num).toDouble();
        final out = b.cast<Uint8>().asTypedList(4).toList();
        malloc.free(b);
        return Uint8List.fromList(out);
      }
      case SYBFLT8:
        final b = malloc<Double>(); b.value = (v as num).toDouble();
        final out = b.cast<Uint8>().asTypedList(8).toList();
        malloc.free(b);
        return Uint8List.fromList(out);
      case SYBBIT:
        return Uint8List.fromList([(v as bool) ? 1 : 0]);
      case SYBMONEY4: {
        // value scaled by 10000 and stored in 4-byte signed int
        final scaled = ((v as num).toDouble() * 10000.0).round();
        final b = malloc<Int32>(); b.value = scaled;
        final out = b.cast<Uint8>().asTypedList(4).toList();
        malloc.free(b);
        return Uint8List.fromList(out);
      }
      case SYBMONEY: {
        // 8-byte money: high 32 bits signed, low 32 bits unsigned, scaled by 10000
        final scaled = ((v as num).toDouble() * 10000.0).round();
        final high = (scaled >> 32);
        final low = scaled & 0xFFFFFFFF;
        final bh = malloc<Int32>(); bh.value = high;
        final bl = malloc<Uint32>(); bl.value = low;
        final out = <int>[];
        out.addAll(bh.cast<Uint8>().asTypedList(4));
        out.addAll(bl.cast<Uint8>().asTypedList(4));
        malloc.free(bh); malloc.free(bl);
        return Uint8List.fromList(out);
      }
      case SYBDATETIME: {
        // Encode DateTime to DBDATETIME structure
        final dt = (v is DateTime) ? v.toUtc() : DateTime.tryParse(v.toString())?.toUtc();
        if (dt == null) return Uint8List(0);
        final base = DateTime.utc(1900, 1, 1);
        final days = dt.difference(base).inDays;
        final microsInDay = dt.difference(DateTime.utc(dt.year, dt.month, dt.day)).inMicroseconds;
        final ticks300 = ((microsInDay * 300) ~/ 1000000);
        final bDays = malloc<Int32>(); bDays.value = days;
        final bTime = malloc<Int32>(); bTime.value = ticks300;
        final out = <int>[];
        out.addAll(bDays.cast<Uint8>().asTypedList(4));
        out.addAll(bTime.cast<Uint8>().asTypedList(4));
        malloc.free(bDays); malloc.free(bTime);
        return Uint8List.fromList(out);
      }
      case SYBBINARY:
      case SYBVARBINARY: {
        if (v is Uint8List) return v;
        if (v is List<int>) return Uint8List.fromList(v);
        // fallback: string bytes
        return Uint8List.fromList(utf8.encode(v.toString()));
      }
      case SYBNVARCHAR:
      case SYBNTEXT: {
        // NVARCHAR/NTEXT are UCS-2/UTF-16LE on the wire
        final s = v as String;
        return _encodeUtf16le(s);
      }
      case SYBVARCHAR:
      case SYBCHAR:
      case SYBTEXT:
        return Uint8List.fromList(utf8.encode(v as String));
      default:
        // Implement DECIMAL/NUMERIC/DATETIME as needed.
        final s = utf8.encode(v.toString());
        return Uint8List.fromList(s);
    }
  }

  Future<String> _execSpExecuteSql(
    String sql,
    Map<String, dynamic> params,
    Map<String, int>? types, {
    required bool isSelect,
  }) async {
    return Future(() {
      _ensureConnected();

      // 1) dbrpcinit('sp_executesql', 0)
      final proc = 'sp_executesql'.toNativeUtf8();
      final initRc = _db.dbrpcinit(_dbproc, proc, 0);
      malloc.free(proc);
      if (initRc != SUCCEED) {
        return jsonEncode({"ok": false, "error": "dbrpcinit failed"});
      }

      // 2) Add @stmt (NVARCHAR): SQL text as UTF-16LE
      final stmtBytes = _encodeUtf16le(sql);
      final stmtPtr = malloc<Uint8>(stmtBytes.length);
      stmtPtr.asTypedList(stmtBytes.length).setAll(0, stmtBytes);
      final pNameStmt = '@stmt'.toNativeUtf8();
      final rcStmt = _db.dbrpcparam(
        _dbproc, pNameStmt, 0, SYBNVARCHAR, stmtBytes.length, stmtBytes.length, stmtPtr);
      malloc.free(pNameStmt);
      malloc.free(stmtPtr);
      if (rcStmt != SUCCEED) {
        return jsonEncode({"ok": false, "error": "dbrpcparam @stmt failed"});
      }

      // 3) Build @params declaration, e.g. N'@id int, @name nvarchar(100)'
      final declParts = <String>[];
      for (final e in params.entries) {
        final t = (types != null && types.containsKey(e.key)) ? types[e.key]! : _inferType(e.value);
        declParts.add('${e.key} ${_typeName(t)}');
      }
      final decl = declParts.join(', ');
      final declBytes = _encodeUtf16le(decl);
      final declPtr = malloc<Uint8>(declBytes.length);
      declPtr.asTypedList(declBytes.length).setAll(0, declBytes);
      final pNameDecl = '@params'.toNativeUtf8();
      final rcDecl = _db.dbrpcparam(
        _dbproc, pNameDecl, 0, SYBNVARCHAR, declBytes.length, declBytes.length, declPtr);
      malloc.free(pNameDecl);
      malloc.free(declPtr);
      if (rcDecl != SUCCEED) {
        return jsonEncode({"ok": false, "error": "dbrpcparam @params failed"});
      }

      // 4) Bind each parameter in correct order; sp_executesql expects them by name.
      for (final e in params.entries) {
        final t = (types != null && types.containsKey(e.key)) ? types[e.key]! : _inferType(e.value);
        final valBytes = _encodeValue(t, e.value);
        final valPtr = malloc<Uint8>(valBytes.length);
        valPtr.asTypedList(valBytes.length).setAll(0, valBytes);

        final pName = e.key.toNativeUtf8();
        final rc = _db.dbrpcparam(_dbproc, pName, 0, t, valBytes.length, valBytes.length, valPtr);
        malloc.free(pName);
        malloc.free(valPtr);
        if (rc != SUCCEED) {
          return jsonEncode({"ok": false, "error": "dbrpcparam ${e.key} failed"});
        }
      }

      // 5) Send RPC
      if (_db.dbrpcsend(_dbproc) != SUCCEED) {
        return jsonEncode({"ok": false, "error": "dbrpcsend failed"});
      }
      if (_db.dbsqlok(_dbproc) != SUCCEED) {
        return jsonEncode({"ok": false, "error": "dbsqlok failed"});
      }

      // 6) Read result sets like query()
      final rows = <Map<String, dynamic>>[];
      while (true) {
        final res = _db.dbresults(_dbproc);
        if (res == NO_MORE_RESULTS) break;
        if (res == FAIL) {
          return jsonEncode({"ok": false, "error": "dbresults failed"});
        }
        final ncols = _db.dbnumcols(_dbproc);
        final colNames = <String>[];
        final colTypes = <int>[];
        for (var c = 1; c <= ncols; c++) {
          colNames.add(_db.dbcolname(_dbproc, c).toDartString());
          colTypes.add(_db.dbcoltype(_dbproc, c));
        }
        while (true) {
          final r = _db.dbnextrow(_dbproc);
          if (r == NO_MORE_RESULTS || r == FAIL) break;
          final row = <String, dynamic>{};
          for (var c = 1; c <= ncols; c++) {
            final len = _db.dbdatlen(_dbproc, c);
            final dataPtr = _db.dbdata(_dbproc, c);
            row[colNames[c - 1]] = decodeDbValueWithFallback(_db, _dbproc, colTypes[c - 1], dataPtr, len);
          }
          rows.add(row);
        }
      }
      return jsonEncode({"ok": true, "rows": rows});
    });
  }

  int _inferType(dynamic v) {
    if (v == null) return SYBVARCHAR;
    if (v is int) return SYBINT4; // allow override in types if smaller width needed
    if (v is double || v is num) return SYBFLT8;
    if (v is bool) return SYBBIT;
    if (v is String) return SYBVARCHAR;
    if (v is DateTime) return SYBDATETIME;
    if (v is Uint8List || v is List<int>) return SYBVARBINARY;
    // Decimal: pass as nvarchar by default unless explicit type provided
    return SYBVARCHAR;
  }

  String _typeName(int t) {
    switch (t) {
      case SYBINT1: return 'tinyint';
      case SYBINT2: return 'smallint';
      case SYBINT4: return 'int';
      case SYBINT8: return 'bigint';
      case SYBREAL: return 'real';
      case SYBFLT8: return 'float';
      case SYBBIT: return 'bit';
      case SYBMONEY: return 'money';
      case SYBMONEY4: return 'smallmoney';
      case SYBDATETIME: return 'datetime';
      case SYBDATETIME4: return 'smalldatetime';
      case SYBMSDATE: return 'date';
      case SYBMSTIME: return 'time';
      case SYBMSDATETIME2: return 'datetime2';
      case SYBMSDATETIMEOFFSET: return 'datetimeoffset';
      case SYBBINARY: return 'binary(8000)';
      case SYBVARBINARY: return 'varbinary(max)';
      case SYBVARCHAR: return 'varchar(max)';
      case SYBCHAR: return 'char(8000)';
      case SYBTEXT: return 'varchar(max)';
      case SYBNVARCHAR: return 'nvarchar(max)';
      case SYBNTEXT: return 'nvarchar(max)';
      default: return 'nvarchar(max)';
    }
  }

  // Encode Dart String to UTF-16LE bytes (UCS-2 for BMP code points)
  Uint8List _encodeUtf16le(String s) {
    final codes = s.codeUnits; // 16-bit code units
    final out = Uint8List(codes.length * 2);
    var j = 0;
    for (final cu in codes) {
      out[j++] = cu & 0xFF;
      out[j++] = (cu >> 8) & 0xFF;
    }
    return out;
  }
}