import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'ffi/freetds_bindings.dart';
import 'native_logger.dart';
import 'sql_exception.dart';

class MssqlClient {
  final String server;
  final String username;
  final String password;

  static final Map<String, String> _trustServerCertificateConfigCache =
      <String, String>{};

  /// When non-null, overrides the TDS protocol version used for this
  /// connection. Accepted values: `'7.0'`, `'7.1'`, `'7.2'`, `'7.3'`, `'7.4'`.
  /// Most modern hosted SQL Servers require `'7.4'` (SQL Server 2012+).
  /// If null, the FreeTDS compiled-in default is used.
  final String? tdsVersion;

  /// Controls TLS encryption negotiation with the server.
  ///
  /// - `true`  → require TLS (`DBSETENCRYPTION = 'require'`). Use when the
  ///   server mandates encryption (e.g., Azure, SmartASP, Site4Now).
  /// - `false` → disable TLS (`DBSETENCRYPTION = 'off'`).
  /// - `null`  → use the FreeTDS default (usually off unless freetds.conf says
  ///   otherwise).
  final bool? encrypt;

  /// When `true`, FreeTDS will not verify the server's SSL/TLS certificate
  /// hostname or certificate chain for this connection.
  ///
  /// This is implemented by pointing the process-wide `FREETDSCONF`
  /// environment variable at a cached override config during `dbopen()`. That
  /// override clears any inherited `ca file` / `crl file` settings and sets
  /// `check certificate hostname = no` for the target server while preserving
  /// the target host/port mapping so FreeTDS will accept any server
  /// certificate.
  ///
  /// Use this only when you explicitly trust the server endpoint and need to
  /// bypass TLS certificate validation.
  ///
  /// To avoid cross-connect races, all `dbopen()` calls are serialized through
  /// a package-level lock while this environment override is active.
  final bool trustServerCertificate;

  DBLib? _db;
  Pointer<DBPROCESS>? _dbproc;
  bool _connected = false;

  MssqlClient({
    required this.server,
    required this.username,
    required this.password,
    this.tdsVersion,
    this.encrypt,
    this.trustServerCertificate = false,
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
      // Preflight: if server string looks like host:port, try a quick TCP probe
      final hp = _splitHostPort(server);
      if (hp != null) {
        final ok = await _probeTcp(
          hp.$1,
          hp.$2,
          Duration(seconds: loginTimeoutSeconds),
        );
        if (!ok) {
          MssqlLogger.w(
            'connect | op=probe | host=${hp.$1} | port=${hp.$2} | reachable=false',
          );
          return false;
        }
        MssqlLogger.i(
          'connect | op=probe | host=${hp.$1} | port=${hp.$2} | reachable=true',
        );
      }
      _db ??= DBLib.load();
      _db!.dbinit();
      // Install handlers early so DB-Lib won't use its default fatal handler on errors in dbopen.
      try {
        _db!.dberrhandle(kErrHandlerPtr);
        _db!.dbmsghandle(kMsgHandlerPtr);
        MssqlLogger.i('connect | op=handlers | status=installed');
      } catch (e) {
        MssqlLogger.w('connect | op=handlers | error=$e');
      }

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

        if (hp != null) {
          final hostPtr = hp.$1.toNativeUtf8();
          try {
            final rcHost = _db!.dbsetlname(login, hostPtr, DBSETHOST);
            MssqlLogger.i(
              'connect | op=dbsetlname | option=DBSETHOST | value=${hp.$1} | rc=$rcHost',
            );
            final rcPort = _db!.dbsetlshort(login, hp.$2, DBSETPORT);
            MssqlLogger.i(
              'connect | op=dbsetlshort | option=DBSETPORT | value=${hp.$2} | rc=$rcPort',
            );
          } catch (e) {
            MssqlLogger.w(
              'connect | op=server-endpoint | host=${hp.$1} | port=${hp.$2} | error=$e',
            );
          } finally {
            malloc.free(hostPtr);
          }
        }

        // Enable BCP on this login so that bulk insert APIs are available on the session.
        try {
          final rcBcp = _db!.dbsetlbool(login, 1, DBSETBCP);
          MssqlLogger.i(
            'connect | op=dbsetlbool | option=DBSETBCP | value=1 | rc=$rcBcp',
          );
        } catch (e) {
          MssqlLogger.w(
            'connect | op=dbsetlbool | option=DBSETBCP | value=1 | error=$e',
          );
        }

        // Set TDS packet size to 4096 bytes for improved network throughput.
        // Default is often 512 bytes which causes excessive round-trips for large data.
        // SQL Server supports up to 32767; 4096 is a safe, high-throughput default.
        try {
          final rcPkt = _db!.dbsetllong(login, 4096, DBSETPACKET);
          MssqlLogger.i(
            'connect | op=dbsetllong | option=DBSETPACKET | value=4096 | rc=$rcPkt',
          );
        } catch (e) {
          MssqlLogger.w(
            'connect | op=dbsetllong | option=DBSETPACKET | value=4096 | error=$e',
          );
        }

        // TDS protocol version (e.g. '7.4' for SQL Server 2012+).
        // Most hosted providers require 7.1 or higher; 7.4 is ideal modern default.
        if (tdsVersion != null) {
          final ver = _parseTdsVersion(tdsVersion!);
          if (ver != null) {
            try {
              final rcVer = _db!.dbsetlversion(login, ver);
              MssqlLogger.i(
                'connect | op=dbsetlversion | version=$tdsVersion | rc=$rcVer',
              );
            } catch (e) {
              MssqlLogger.w(
                'connect | op=dbsetlversion | version=$tdsVersion | error=$e',
              );
            }
          } else {
            MssqlLogger.w(
              'connect | op=dbsetlversion | version=$tdsVersion | error=unknown_version (use 7.0/7.1/7.2/7.3/7.4)',
            );
          }
        }

        // Encryption mode via DBSETENCRYPTION (FreeTDS ext, via dbsetlname).
        // Note: DBSETENCRYPT (12) is unimplemented in FreeTDS dbsetlbool; use
        // DBSETENCRYPTION (1005) with dbsetlname instead.
        if (encrypt != null) {
          final encMode = encrypt! ? 'require' : 'off';
          final encPtr = encMode.toNativeUtf8();
          try {
            final rcEnc = _db!.dbsetlname(login, encPtr, DBSETENCRYPTION);
            MssqlLogger.i(
              'connect | op=dbsetlname | option=DBSETENCRYPTION | value=$encMode | rc=$rcEnc',
            );
          } catch (e) {
            MssqlLogger.w(
              'connect | op=dbsetlname | option=DBSETENCRYPTION | value=$encMode | error=$e',
            );
          } finally {
            malloc.free(encPtr);
          }
        }
      } finally {
        malloc.free(u);
        malloc.free(p);
      }

      final srv = server.toNativeUtf8();
      try {
        await _withDbOpenEnvironmentLock(() async {
          // trustServerCertificate: point FREETDSCONF at a cached override
          // config that disables hostname verification while preserving any
          // caller-supplied FREETDSCONF content.
          String? prevFreetdsConf;
          if (trustServerCertificate) {
            try {
              prevFreetdsConf = _nativeGetEnv('FREETDSCONF');
              final overrideConf = _trustServerCertificateConfigPath(
                prevFreetdsConf,
                server,
              );
              _nativeSetEnv('FREETDSCONF', overrideConf);
              MssqlLogger.i(
                'connect | op=trustServerCertificate | config=$overrideConf',
              );
            } catch (e) {
              MssqlLogger.w('connect | op=trustServerCertificate | error=$e');
            }
          }
          try {
            MssqlLogger.i('connect | op=dbopen | server=$server');
            _dbproc = _db!.dbopen(login, srv);
          } finally {
            if (trustServerCertificate) {
              try {
                _nativeSetEnv('FREETDSCONF', prevFreetdsConf);
              } catch (e) {
                MssqlLogger.w(
                  'connect | op=trustServerCertificate | cleanup-error=$e',
                );
              }
            }
          }
        });
      } finally {
        malloc.free(srv);
      }

      if (_dbproc == nullptr) {
        MssqlLogger.e('connect | op=dbopen | server=$server | error=nullptr');
        return false;
      }

      // Increase TEXT/NTEXT retrieval limit to avoid 4096-byte default truncation.
      // Use T-SQL SET TEXTSIZE to ensure compatibility across DB-Lib variants.
      try {
        const String cmdText = 'SET TEXTSIZE 2147483647';
        final setPtr = cmdText.toNativeUtf8();
        try {
          final rc1 = _db!.dbcmd(_dbproc!, setPtr);
          MssqlLogger.i('connect | op=dbcmd | sql=SET TEXTSIZE | rc=$rc1');
          if (rc1 == SUCCEED) {
            final rc2 = _db!.dbsqlexec(_dbproc!);
            MssqlLogger.i('connect | op=dbsqlexec | rc=$rc2');
            if (rc2 == SUCCEED) {
              // Drain the SET batch quietly
              _collectResults(_db!, _dbproc!);
            }
          }
        } finally {
          malloc.free(setPtr);
        }
      } catch (e) {
        MssqlLogger.w('connect | op=set-textsize | error=$e');
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

  /// Map a user-supplied TDS version string to the FreeTDS DBVERSION constant.
  /// Returns null for unrecognised values so callers can warn appropriately.
  static int? _parseTdsVersion(String v) {
    switch (v.trim()) {
      case '7.0':
        return DBVERSION_70;
      case '7.1':
        return DBVERSION_71;
      case '7.2':
        return DBVERSION_72;
      case '7.3':
        return DBVERSION_73;
      case '7.4':
        return DBVERSION_74;
      default:
        return null;
    }
  }

  static String _trustServerCertificateConfigPath(
    String? baseConfigPath,
    String server,
  ) {
    final baseKey = (baseConfigPath ?? '').trim();
    final cacheKey = '$baseKey\n$server';
    final cached = _trustServerCertificateConfigCache[cacheKey];
    if (cached != null && File(cached).existsSync()) {
      return cached;
    }

    var inheritedContent = '';
    if (baseKey.isNotEmpty) {
      try {
        final baseFile = File(baseKey);
        if (baseFile.existsSync()) {
          inheritedContent = baseFile.readAsStringSync();
        }
      } catch (e) {
        MssqlLogger.w(
          'trustServerCertificate | base-config-read-failed | path=$baseKey | error=$e',
        );
      }
    }

    final buffer = StringBuffer();
    if (inheritedContent.isNotEmpty) {
      buffer.write(inheritedContent);
      if (!inheritedContent.endsWith('\n')) {
        buffer.writeln();
      }
    }
    buffer.writeln('[global]');
    buffer.writeln('ca file =');
    buffer.writeln('crl file =');
    buffer.writeln('check certificate hostname = no');

    final serverTarget = _trustServerCertificateHostPort(server);
    for (final sectionName in _trustServerCertificateSectionNames(server)) {
      buffer.writeln();
      buffer.writeln('[$sectionName]');
      buffer.writeln('host = ${serverTarget.$1}');
      if (serverTarget.$2 != null) {
        buffer.writeln('port = ${serverTarget.$2}');
      }
      buffer.writeln('ca file =');
      buffer.writeln('crl file =');
      buffer.writeln('check certificate hostname = no');
    }

    final path =
        '${Directory.systemTemp.path}${Platform.pathSeparator}'
        'mssql_connection_trust_cert_${cacheKey.hashCode.abs()}.conf';
    File(path).writeAsStringSync(buffer.toString());
    _trustServerCertificateConfigCache[cacheKey] = path;
    return path;
  }

  static List<String> _trustServerCertificateSectionNames(String server) {
    final names = <String>[];
    final target = _trustServerCertificateHostPort(server);

    void add(String value) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return;
      if (trimmed.contains('[') || trimmed.contains(']')) return;
      if (trimmed.contains('\r') || trimmed.contains('\n')) return;
      if (!names.contains(trimmed)) {
        names.add(trimmed);
      }
    }

    add(server);
    if (target.$2 != null) {
      add(target.$1);
    }

    return names;
  }

  static (String, int?) _trustServerCertificateHostPort(String server) {
    final trimmed = server.trim();
    final idx = trimmed.lastIndexOf(':');
    if (idx > 0 && idx < trimmed.length - 1) {
      final port = int.tryParse(trimmed.substring(idx + 1));
      if (port != null) {
        return (trimmed.substring(0, idx), port);
      }
    }
    return (trimmed, null);
  }

  static Future<T> _withDbOpenEnvironmentLock<T>(
    Future<T> Function() action,
  ) async {
    final lockPath =
        '${Directory.systemTemp.path}${Platform.pathSeparator}'
        'mssql_connection_dbopen.lock';
    RandomAccessFile? raf;
    try {
      raf = await File(lockPath).open(mode: FileMode.append);
      await raf.lock(FileLock.blockingExclusive);
      return await action();
    } catch (e) {
      MssqlLogger.w('dbopen-lock | unavailable | error=$e');
      return await action();
    } finally {
      if (raf != null) {
        try {
          await raf.unlock();
        } catch (_) {}
        await raf.close();
      }
    }
  }

  static String? _nativeGetEnv(String name) {
    try {
      return _NativeProcessEnv.get(name);
    } catch (e) {
      MssqlLogger.w('_nativeGetEnv | name=$name | error=$e');
      return Platform.environment[name];
    }
  }

  /// Set (or unset when [value] is null) a process environment variable using
  /// the native OS API so that FreeTDS's `getenv()` calls (which happen inside
  /// `dbopen()` → `tds_read_config_info()`) see the updated value.
  ///
  /// Dart's [Platform.environment] is a snapshot taken at process start and
  /// cannot be written, so we call the C runtime directly via FFI.
  static void _nativeSetEnv(String name, String? value) {
    try {
      _NativeProcessEnv.set(name, value);
    } catch (e) {
      MssqlLogger.w('_nativeSetEnv | name=$name | error=$e');
    }
  }

  // Parse a host:port string into (host, port). Returns null if not in that form.
  (String, int)? _splitHostPort(String s) {
    final idx = s.lastIndexOf(':');
    if (idx <= 0 || idx == s.length - 1) return null;
    final host = s.substring(0, idx);
    final pStr = s.substring(idx + 1);
    final port = int.tryParse(pStr);
    if (port == null) return null;
    return (host, port);
  }

  // Attempt a TCP connection to host:port within [timeout].
  Future<bool> _probeTcp(String host, int port, Duration timeout) async {
    try {
      final sock = await Socket.connect(host, port, timeout: timeout);
      // Immediately dispose; this is a reachability probe only.
      await sock.close();
      return true;
    } catch (_) {
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

    // If inserting into a temp table (e.g., #tmp), fall back to parameterized INSERTs.
    // BCP into temp tables is not consistently supported and can cause instability.
    final tn = tableName.trim();
    if (tn.startsWith('#')) {
      final cols = (columns != null && columns.isNotEmpty)
          ? List<String>.from(columns)
          : rows.first.keys.toList(growable: false);
      int total = 0;
      for (final row in rows) {
        final colList = cols
            .map((c) => '[${c.replaceAll(']', ']]')}]')
            .join(', ');
        final placeholders = cols.map((c) => '@$c').join(', ');
        final sql = 'INSERT INTO $tableName ($colList) VALUES ($placeholders)';
        final pm = <String, dynamic>{};
        for (final c in cols) {
          pm['@$c'] = row[c];
        }
        final res = await executeParams(sql, pm);
        try {
          final j = jsonDecode(res);
          final affected = (j['affected'] is int) ? j['affected'] as int : 0;
          if (affected > 0) total += 1;
        } catch (_) {
          // On parse error, assume failure for that row
        }
      }
      return total;
    }

    // Determine columns
    final cols = (columns != null && columns.isNotEmpty)
        ? List<String>.from(columns)
        : rows.first.keys.toList(growable: false);

    // Initialize BCP
    final tbl = tableName.toNativeUtf8();
    try {
      final rcInit = db.bcp_init(dbproc, tbl, nullptr, nullptr, DB_IN);
      if (rcInit != SUCCEED) {
        throw SQLException('bcp_init failed for $tableName');
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
          throw SQLException('bcp_bind failed for column ${i + 1}');
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
            throw SQLException('bcp_sendrow failed');
          }
          sent++;

          // Batch if needed
          if (batchSize > 0 && (sent % batchSize == 0)) {
            final b = db.bcp_batch(dbproc);
            if (b < 0) {
              throw SQLException('bcp_batch failed');
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
        throw SQLException('bcp_done failed');
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
    // Detect if we should enable strict SET options for this statement
    final _SetPlan plan = _analyzeSetNeeds(sql);
    if (plan.needsSet) {
      // 1) Enable options in their own batch
      final setCmd = plan.setPrefix.toNativeUtf8();
      try {
        MssqlLogger.i('execute | op=dbcmd | sqlLen=${plan.setPrefix.length}');
        final rc1 = db.dbcmd(dbproc, setCmd);
        if (rc1 != SUCCEED) {
          MssqlLogger.e('execute | op=dbcmd | rc=$rc1 | error=fail');
          final em =
              DBLib.takeLastMessage(dbproc) ?? DBLib.takeLastError(dbproc);
          throw SQLException(em ?? 'dbcmd failed (SET options)');
        }
        MssqlLogger.i('execute | op=dbsqlexec');
        final rc2 = db.dbsqlexec(dbproc);
        if (rc2 != SUCCEED) {
          MssqlLogger.e('execute | op=dbsqlexec | rc=$rc2 | error=fail');
          final em =
              DBLib.takeLastMessage(dbproc) ?? DBLib.takeLastError(dbproc);
          throw SQLException(em ?? 'dbsqlexec failed (SET options)');
        }
        // Drain results for SET batch
        _collectResults(db, dbproc);
      } finally {
        malloc.free(setCmd);
      }

      // 2) Execute the original SQL in its own batch (ensuring CREATE VIEW is first)
      final cmd = sql.toNativeUtf8();
      try {
        MssqlLogger.i('execute | op=dbcmd | sqlLen=${sql.length}');
        final rc1 = db.dbcmd(dbproc, cmd);
        if (rc1 != SUCCEED) {
          MssqlLogger.e('execute | op=dbcmd | rc=$rc1 | error=fail');
          final em =
              DBLib.takeLastMessage(dbproc) ?? DBLib.takeLastError(dbproc);
          throw SQLException(em ?? 'dbcmd failed');
        }
        MssqlLogger.i('execute | op=dbsqlexec');
        final rc2 = db.dbsqlexec(dbproc);
        if (rc2 != SUCCEED) {
          MssqlLogger.e('execute | op=dbsqlexec | rc=$rc2 | error=fail');
          final em =
              DBLib.takeLastMessage(dbproc) ?? DBLib.takeLastError(dbproc);
          throw SQLException(em ?? 'dbsqlexec failed');
        }
        return _collectResults(db, dbproc);
      } finally {
        malloc.free(cmd);
      }
    } else {
      // Regular path
      final cmd = sql.toNativeUtf8();
      try {
        MssqlLogger.i('execute | op=dbcmd | sqlLen=${sql.length}');
        final rc1 = db.dbcmd(dbproc, cmd);
        if (rc1 != SUCCEED) {
          MssqlLogger.e('execute | op=dbcmd | rc=$rc1 | error=fail');
          final em =
              DBLib.takeLastMessage(dbproc) ?? DBLib.takeLastError(dbproc);
          throw SQLException(em ?? 'dbcmd failed');
        }
        MssqlLogger.i('execute | op=dbsqlexec');
        final rc2 = db.dbsqlexec(dbproc);
        if (rc2 != SUCCEED) {
          MssqlLogger.e('execute | op=dbsqlexec | rc=$rc2 | error=fail');
          final em =
              DBLib.takeLastMessage(dbproc) ?? DBLib.takeLastError(dbproc);
          throw SQLException(em ?? 'dbsqlexec failed');
        }
        return _collectResults(db, dbproc);
      } finally {
        malloc.free(cmd);
      }
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

    // Prepare RPC call: sp_executesql(@stmt, @params, <params...>) with dynamic string encoding
    final rpcName = 'sp_executesql'.toNativeUtf8();
    final _StringDbBuf stmtBuf = _encodeStringSmart(sql);
    final _StringDbBuf paramsBuf = _encodeStringSmart(declStr);

    // We'll pass Utf8 pointers directly; no extra copies
    final tempAllocations = <_TempBuf>[]; // values for user params

    try {
      MssqlLogger.i('executeParams | op=dbrpcinit | rpc=sp_executesql');
      final rcInit = db.dbrpcinit(dbproc, rpcName, 0);
      if (rcInit != SUCCEED) {
        MssqlLogger.e('executeParams | op=dbrpcinit | rc=$rcInit | error=fail');
        // In case previous RPC left state dirty, attempt a reset
        try {
          final empty = ''.toNativeUtf8();
          db.dbrpcinit(dbproc, empty, DBRPCRESET);
          malloc.free(empty);
        } catch (_) {}
        final em = DBLib.takeLastMessage(dbproc) ?? DBLib.takeLastError(dbproc);
        throw SQLException(em ?? 'dbrpcinit failed');
      }

      // @stmt (VARCHAR or NVARCHAR based on content)
      final nameStmt = '@stmt'.toNativeUtf8();
      final rcP1 = db.dbrpcparam(
        dbproc,
        nameStmt,
        0,
        stmtBuf.type,
        -1, // maxlen: -1 for non-OUTPUT
        // datalen: NVARCHAR expects character count; VARCHAR expects bytes
        (stmtBuf.type == SYBNVARCHAR)
            ? (stmtBuf.buf.length >> 1)
            : stmtBuf.buf.length,
        stmtBuf.buf.ptr,
      );
      malloc.free(nameStmt);
      if (rcP1 != SUCCEED) {
        MssqlLogger.e(
          'executeParams | op=dbrpcparam | name=@stmt | rc=$rcP1 | error=fail',
        );
        // Reset RPC state to allow future dbrpcinit calls
        try {
          final z = ''.toNativeUtf8();
          db.dbrpcinit(dbproc, z, DBRPCRESET);
          malloc.free(z);
        } catch (_) {}
        final em = DBLib.takeLastMessage(dbproc) ?? DBLib.takeLastError(dbproc);
        throw SQLException(em ?? 'dbrpcparam @stmt failed');
      }

      // @params (can be empty) as VARCHAR or NVARCHAR based on content
      final nameParams = '@params'.toNativeUtf8();
      final rcP2 = db.dbrpcparam(
        dbproc,
        nameParams,
        0,
        paramsBuf.type,
        -1, // maxlen: -1 for non-OUTPUT
        // datalen: NVARCHAR expects character count; VARCHAR expects bytes
        (paramsBuf.type == SYBNVARCHAR)
            ? (paramsBuf.buf.length >> 1)
            : paramsBuf.buf.length,
        paramsBuf.buf.ptr,
      );
      malloc.free(nameParams);
      if (rcP2 != SUCCEED) {
        MssqlLogger.e(
          'executeParams | op=dbrpcparam | name=@params | rc=$rcP2 | error=fail',
        );
        try {
          final z = ''.toNativeUtf8();
          db.dbrpcinit(dbproc, z, DBRPCRESET);
          malloc.free(z);
        } catch (_) {}
        final em = DBLib.takeLastMessage(dbproc) ?? DBLib.takeLastError(dbproc);
        throw SQLException(em ?? 'dbrpcparam @params failed');
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
          -1, // maxlen: -1 for non-OUTPUT
          (rpcVal.type == SYBNVARCHAR)
              ? (rpcVal.buf.length << 1)
              : rpcVal
                    .buf
                    .length, // datalen: for NVARCHAR pass character count; for others, bytes
          rpcVal.buf.ptr,
        );
        malloc.free(cname);
        if (rcPi != SUCCEED) {
          MssqlLogger.e(
            'executeParams | op=dbrpcparam | name=$name | rc=$rcPi | error=fail',
          );
          try {
            final z = ''.toNativeUtf8();
            db.dbrpcinit(dbproc, z, DBRPCRESET);
            malloc.free(z);
          } catch (_) {}
          final em =
              DBLib.takeLastMessage(dbproc) ?? DBLib.takeLastError(dbproc);
          throw SQLException(em ?? 'dbrpcparam failed');
        }
      }

      MssqlLogger.i('executeParams | op=dbrpcsend');
      final rcSend = db.dbrpcsend(dbproc);
      if (rcSend != SUCCEED) {
        MssqlLogger.e('executeParams | op=dbrpcsend | rc=$rcSend | error=fail');
        final em = DBLib.takeLastMessage(dbproc) ?? DBLib.takeLastError(dbproc);
        throw SQLException(em ?? 'dbrpcsend failed');
      }

      MssqlLogger.i('executeParams | op=dbsqlok');
      final rcOk = db.dbsqlok(dbproc);
      if (rcOk != SUCCEED) {
        MssqlLogger.e('executeParams | op=dbsqlok | rc=$rcOk | error=fail');
        final em = DBLib.takeLastMessage(dbproc) ?? DBLib.takeLastError(dbproc);
        throw SQLException(em ?? 'dbsqlok failed');
      }

      // Read results via shared collector
      return _collectResults(db, dbproc);
    } finally {
      // Free buffers for @stmt/@params and user param values
      malloc.free(stmtBuf.buf.ptr);
      malloc.free(paramsBuf.buf.ptr);
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
          if (nr == BUF_FULL) {
            MssqlLogger.i(
              'collectResults | op=dbnextrow | rc=$nr | status=retry',
            );
            continue;
          }
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
          if (nr == BUF_FULL) {
            MssqlLogger.i(
              'collectResults | op=dbnextrow | rc=$nr | status=retry-skip',
            );
            continue;
          }
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
      throw SQLException('Not connected. Call connect() first.');
    }
  }

  static String _normalizeParamName(String name) =>
      name.startsWith('@') ? name : '@$name';

  static String _inferSqlType(dynamic v) {
    // Use VARCHAR(MAX) + SYBVARCHAR RPC encoding so NULL and Unicode bind
    // safely on Azure SQL Edge and modern SQL Server (avoids SYBNVARCHAR 0x67).
    if (v == null) return 'varchar(max)';
    if (v is bool) return 'bit';
    if (v is int) {
      // choose bigint if outside 32-bit range
      if (v < -2147483648 || v > 2147483647) return 'bigint';
      return 'int';
    }
    if (v is double) return 'float';
    if (v is String) return 'varchar(max)';
    // Declare DateTime parameters as NVARCHAR and let SQL convert explicitly
    // (e.g., CONVERT(datetime2, @when)). This avoids binary TDS packing.
    if (v is DateTime) return 'nvarchar(50)';
    if (v is Uint8List) return 'varbinary(max)';
    // Fallback to VARCHAR
    return 'varchar(max)';
  }

  // Analyze whether strict SET options are needed and generate the SET batch.
  _SetPlan _analyzeSetNeeds(String sql) {
    final trimmed = sql.trimLeft();
    if (trimmed.isEmpty) return const _SetPlan(false, '');
    final up = trimmed.toUpperCase();
    final isDdl =
        up.startsWith('CREATE ') ||
        up.startsWith('ALTER ') ||
        up.startsWith('DROP ');
    final targetsStrict =
        up.startsWith('CREATE VIEW ') ||
        up.startsWith('ALTER VIEW ') ||
        up.startsWith('CREATE TABLE ') ||
        up.startsWith('ALTER TABLE ') ||
        up.startsWith('CREATE INDEX ') ||
        up.startsWith('ALTER INDEX ') ||
        up.startsWith('CREATE FUNCTION ') ||
        up.startsWith('ALTER FUNCTION ') ||
        up.startsWith('CREATE PROCEDURE ') ||
        up.startsWith('ALTER PROCEDURE ') ||
        up.startsWith('CREATE TRIGGER ') ||
        up.startsWith('ALTER TRIGGER ');
    if (!(isDdl || targetsStrict)) return const _SetPlan(false, '');
    const setPrefix =
        'SET ANSI_NULLS ON; '
        'SET QUOTED_IDENTIFIER ON; '
        'SET ANSI_PADDING ON; '
        'SET ANSI_WARNINGS ON; '
        'SET CONCAT_NULL_YIELDS_NULL ON; '
        'SET ARITHABORT ON; '
        'SET NUMERIC_ROUNDABORT OFF;';
    return const _SetPlan(true, setPrefix);
  }
}

class _SetPlan {
  final bool needsSet;
  final String setPrefix;
  const _SetPlan(this.needsSet, this.setPrefix);
}

final class _NativeProcessEnv {
  static final DynamicLibrary _processLib = DynamicLibrary.process();
  static final DynamicLibrary _windowsKernel32 = Platform.isWindows
      ? DynamicLibrary.open('kernel32.dll')
      : _processLib;

  static final int Function(Pointer<Utf16>, Pointer<Utf16>, int)?
  _getEnvWindows = Platform.isWindows
      ? _windowsKernel32.lookupFunction<
          Uint32 Function(Pointer<Utf16>, Pointer<Utf16>, Uint32),
          int Function(Pointer<Utf16>, Pointer<Utf16>, int)
        >('GetEnvironmentVariableW')
      : null;

  static final int Function(Pointer<Utf16>, Pointer<Utf16>)? _setEnvWindows =
      Platform.isWindows
      ? _windowsKernel32.lookupFunction<
          Int32 Function(Pointer<Utf16>, Pointer<Utf16>),
          int Function(Pointer<Utf16>, Pointer<Utf16>)
        >('SetEnvironmentVariableW')
      : null;

  static final Pointer<Utf8> Function(Pointer<Utf8>)? _getenvPosix =
      Platform.isWindows
      ? null
      : _processLib.lookupFunction<
          Pointer<Utf8> Function(Pointer<Utf8>),
          Pointer<Utf8> Function(Pointer<Utf8>)
        >('getenv');

  static final int Function(Pointer<Utf8>)? _unsetenvPosix = Platform.isWindows
      ? null
      : _processLib.lookupFunction<
          Int32 Function(Pointer<Utf8>),
          int Function(Pointer<Utf8>)
        >('unsetenv');

  static final int Function(Pointer<Utf8>, Pointer<Utf8>, int)? _setenvPosix =
      Platform.isWindows
      ? null
      : _processLib.lookupFunction<
          Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Int32),
          int Function(Pointer<Utf8>, Pointer<Utf8>, int)
        >('setenv');

  static String? get(String name) {
    if (Platform.isWindows) {
      final getEnv = _getEnvWindows!;

      final namePtr = name.toNativeUtf16();
      try {
        final required = getEnv(namePtr, nullptr.cast<Utf16>(), 0);
        if (required <= 0) return null;
        final buffer = calloc<Uint16>(required);
        try {
          final written = getEnv(namePtr, buffer.cast<Utf16>(), required);
          if (written <= 0) return null;
          return buffer.cast<Utf16>().toDartString();
        } finally {
          calloc.free(buffer);
        }
      } finally {
        malloc.free(namePtr);
      }
    }

    final namePtr = name.toNativeUtf8();
    try {
      final valuePtr = _getenvPosix!(namePtr);
      if (valuePtr == nullptr) return null;
      return valuePtr.toDartString();
    } finally {
      malloc.free(namePtr);
    }
  }

  static void set(String name, String? value) {
    if (Platform.isWindows) {
      final namePtr = name.toNativeUtf16();
      final valuePtr = value?.toNativeUtf16();
      try {
        _setEnvWindows!(namePtr, valuePtr ?? nullptr.cast<Utf16>());
      } finally {
        malloc.free(namePtr);
        if (valuePtr != null) malloc.free(valuePtr);
      }
      return;
    }

    if (value == null) {
      final namePtr = name.toNativeUtf8();
      try {
        _unsetenvPosix!(namePtr);
      } finally {
        malloc.free(namePtr);
      }
      return;
    }

    final namePtr = name.toNativeUtf8();
    final valuePtr = value.toNativeUtf8();
    try {
      _setenvPosix!(namePtr, valuePtr, 1);
    } finally {
      malloc.free(namePtr);
      malloc.free(valuePtr);
    }
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
  // Default to NVARCHAR for textual data to preserve Unicode and align with SQL Server
  return SYBNVARCHAR;
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
        // Encode as UTF-16LE for NVARCHAR host type; if type is actually SYBVARCHAR, SQL Server will convert.
        final s = (v is String)
            ? v
            : (v is DateTime)
            ? v.toIso8601String()
            : v.toString();
        final codeUnits = s.codeUnits;
        // Each code unit to 2 bytes LE
        final len = codeUnits.length * 2;
        final p = malloc<Uint8>(len);
        final view = p.asTypedList(len);
        for (int i = 0, j = 0; i < codeUnits.length; i++, j += 2) {
          final cu = codeUnits[i];
          view[j] = cu & 0xFF;
          view[j + 1] = (cu >> 8) & 0xFF;
        }
        return _TempBuf(p, len);
      }
  }
}

// Map a Dart value to a DB-Lib type code and native buffer suitable for dbrpcparam.
// For safety and simplicity, most complex types are passed as NVARCHAR and
// converted server-side according to the declared SQL type in sp_executesql.
_RpcVal _encodeForRpc(dynamic v) {
  if (v == null) {
    // Represent NULL by zero-length buffer; server sees NULL when datalen is 0.
    final p = malloc<Uint8>(0);
    return _RpcVal(SYBVARCHAR, _TempBuf(p, 0));
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
  // Strings, DateTime, and other objects -> choose VARCHAR/UTF-16 NVARCHAR based on content
  if (v is String) {
    final sb = _encodeStringSmart(v);
    return _RpcVal(sb.type, sb.buf);
  }
  if (v is DateTime) {
    final s = _formatDateTimeForSql(v); // ASCII only
    final bytes = utf8.encode(s);
    final p = malloc<Uint8>(bytes.length);
    p.asTypedList(bytes.length).setAll(0, bytes);
    return _RpcVal(SYBVARCHAR, _TempBuf(p, bytes.length));
  }
  final s = v.toString();
  final sb = _encodeStringSmart(s);
  return _RpcVal(sb.type, sb.buf);
}

// Format DateTime in an ISO-like pattern accepted by SQL Server, without 'Z'.
// Example: 2025-08-28T02:34:56
String _formatDateTimeForSql(DateTime dt) {
  final d = dt.toUtc();
  String two(int n) => n < 10 ? '0$n' : '$n';
  return '${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)}T${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
}

class _StringDbBuf {
  final int type; // SYBVARCHAR or SYBNVARCHAR
  final _TempBuf buf;
  _StringDbBuf(this.type, this.buf);
}

// Encode strings as UTF-8 SYBVARCHAR for RPC. Azure SQL Edge rejects SYBNVARCHAR
// (0x67) over sp_executesql; UTF-8 VARCHAR works across SQL Server variants.
_StringDbBuf _encodeStringSmart(String s) {
  final bytes = utf8.encode(s);
  final p = malloc<Uint8>(bytes.length);
  p.asTypedList(bytes.length).setAll(0, bytes);
  return _StringDbBuf(SYBVARCHAR, _TempBuf(p, bytes.length));
}
