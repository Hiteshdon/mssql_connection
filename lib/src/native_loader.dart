import 'dart:ffi';
import 'dart:io' show Platform, File, Directory;

import 'package:ffi/ffi.dart';

import 'native_logger.dart';

class NativeLoader {
  static DynamicLibrary loadDBLib() {
    NativeLogger.i('loadDBLib: platform=${Platform.operatingSystem}');
    if (Platform.isAndroid) {
      NativeLogger.i('Android: opening libsybdb.so');
      return DynamicLibrary.open('libsybdb.so');
    } else if (Platform.isIOS) {
      // iOS links the XCFramework statically via CocoaPods; use process.
      NativeLogger.i('iOS: using DynamicLibrary.process()');
      return DynamicLibrary.process();
    } else if (Platform.isMacOS) {
      // Expect the dylib to be available on the system or bundled appropriately.
      // Try common names in order.
      NativeLogger.i('macOS: trying common sybdb dylib names');
      for (final name in ['libsybdb.dylib', 'libsybdb.5.dylib']) {
        try {
          NativeLogger.i('macOS: trying $name');
          final lib = DynamicLibrary.open(name);
          NativeLogger.i('macOS: opened $name');
          return lib;
        } catch (e) {
          NativeLogger.w('macOS: failed $name -> $e');
        }
      }
    } else if (Platform.isLinux) {
      // Prefer bundled linux/Libraries first
      NativeLogger.i('Linux[DB]: building candidate directories');
      final candidateDirs = <String>[];
      try {
        final scriptDir = File.fromUri(Platform.script).parent;
        final root = scriptDir.parent; // repo root when running from tool/
        final rootPath = root.path;
        candidateDirs.add('$rootPath/linux/Libraries');
      } catch (_) {}
      try {
        final cwd = Directory.current.path;
        candidateDirs.add('$cwd/linux/Libraries');
      } catch (_) {}
      NativeLogger.i('Linux[DB]: candidateDirs=${candidateDirs.join('; ')}');
      for (final dir in candidateDirs) {
        for (final name in [
          'libsybdb.so',
          'libsybdb.so.5',
          'libsybdb.so.5.1.0',
        ]) {
          final p = '$dir/$name';
          try {
            NativeLogger.i('Linux[DB]: trying $p');
            final lib = DynamicLibrary.open(p);
            NativeLogger.i('Linux[DB]: opened $p');
            return lib;
          } catch (e) {
            NativeLogger.w('Linux[DB]: failed $p -> $e');
          }
        }
      }
      // Fallback to default name resolution on the system
      NativeLogger.i('Linux[DB]: falling back to system names');
      for (final name in [
        'libsybdb.so',
        'libsybdb.so.5',
        'libsybdb.so.5.1.0',
      ]) {
        try {
          NativeLogger.i('Linux[DB]: trying $name');
          final lib = DynamicLibrary.open(name);
          NativeLogger.i('Linux[DB]: opened $name');
          return lib;
        } catch (e) {
          NativeLogger.w('Linux[DB]: failed $name -> $e');
        }
      }
    } else if (Platform.isWindows) {
      // Try name first (if PATH already set correctly)
      final tried = <String>[];
      Object? lastErr;
      // Configure modern DLL search behavior to include AddDllDirectory entries
      _setDefaultDllDirectories();
      try {
        NativeLogger.i('Windows[DB]: trying sybdb.dll by name');
        return DynamicLibrary.open('sybdb.dll');
      } catch (e) {
        lastErr = e;
        tried.add('sybdb.dll');
        NativeLogger.w('Windows[DB]: sybdb.dll by name failed -> $e');
      }

      // Build candidate directories (prefer bundled locations first)
      final candidateDirs = <String>[];
      try {
        final scriptDir = File.fromUri(Platform.script).parent;
        final root = scriptDir.parent; // repo root when running from tool/
        final rootPath = root.path;
        candidateDirs.addAll(['$rootPath\\windows\\Libraries\\bin']);
      } catch (_) {}
      // Also add fallbacks relative to the current working directory
      try {
        final cwd = Directory.current.path;
        candidateDirs.addAll(['$cwd\\windows\\Libraries\\bin', cwd]);
      } catch (_) {}
      NativeLogger.i('Windows[DB]: candidateDirs=${candidateDirs.join('; ')}');

      // Try to load from each candidate dir; ensure ct.dll first then sybdb.dll
      for (final dir in candidateDirs) {
        try {
          NativeLogger.i('Windows[DB]: trying dir=$dir');
          _setDllDirectory(dir);
          NativeLogger.i('Windows[DB]: SetDllDirectory($dir)');
          // Preload common dependencies if present (OpenSSL)
          final ssl = '$dir\\libssl-1_1-x64.dll';
          final crypto = '$dir\\libcrypto-1_1-x64.dll';
          if (File(crypto).existsSync()) {
            _preloadWithAlteredSearchPath(crypto);
            NativeLogger.i('Windows[DB]: preload $crypto');
          }
          if (File(ssl).existsSync()) {
            _preloadWithAlteredSearchPath(ssl);
            NativeLogger.i('Windows[DB]: preload $ssl');
          }
          final ct = '$dir\\ct.dll';
          final db = '$dir\\sybdb.dll';
          // Preload using LoadLibraryExW so dependencies resolve from same dir
          _preloadWithAlteredSearchPath(ct);
          NativeLogger.i('Windows[DB]: preload $ct');
          _preloadWithAlteredSearchPath(db);
          NativeLogger.i('Windows[DB]: preload $db');
          tried.add(ct + (File(ct).existsSync() ? ' (exists)' : ' (missing)'));
          tried.add(db + (File(db).existsSync() ? ' (exists)' : ' (missing)'));
          NativeLogger.i('Windows[DB]: opening $db');
          // Ensure ct.dll is fully loaded before sybdb.dll
          if (File(ct).existsSync()) {
            try {
              DynamicLibrary.open(ct);
              NativeLogger.i('Windows[DB]: opened $ct');
            } catch (e) {
              NativeLogger.w('Windows[DB]: open ct.dll failed -> $e');
            }
          }
          return DynamicLibrary.open(db);
        } catch (e) {
          NativeLogger.w('Windows[DB]: failed -> $e');
          lastErr = e; /* try next dir */
        }
      }
      throw UnsupportedError(
        'Could not load FreeTDS DB-Lib for this platform. Tried: ${tried.join('; ')}${lastErr != null ? ' | Last error: $lastErr' : ''}',
      );
    }
    throw UnsupportedError('Could not load FreeTDS DB-Lib for this platform.');
  }

  static DynamicLibrary loadCTLib() {
    NativeLogger.i('loadCTLib: platform=${Platform.operatingSystem}');
    if (Platform.isAndroid) {
      NativeLogger.i('Android: opening libct.so');
      return DynamicLibrary.open('libct.so');
    } else if (Platform.isIOS) {
      // iOS links the XCFramework statically via CocoaPods; use process.
      NativeLogger.i('iOS: using DynamicLibrary.process()');
      return DynamicLibrary.process();
    } else if (Platform.isMacOS) {
      for (final name in ['libct.dylib', 'libct.4.dylib']) {
        try {
          NativeLogger.i('macOS: trying $name');
          final lib = DynamicLibrary.open(name);
          NativeLogger.i('macOS: opened $name');
          return lib;
        } catch (e) {
          NativeLogger.w('macOS: failed $name -> $e');
        }
      }
    } else if (Platform.isLinux) {
      // Prefer bundled linux/Libraries first
      NativeLogger.i('Linux[CT]: building candidate directories');
      final candidateDirs = <String>[];
      try {
        final scriptDir = File.fromUri(Platform.script).parent;
        final root = scriptDir.parent; // repo root when running from tool/
        final rootPath = root.path;
        candidateDirs.add('$rootPath/linux/Libraries');
      } catch (_) {}
      try {
        final cwd = Directory.current.path;
        candidateDirs.add('$cwd/linux/Libraries');
      } catch (_) {}
      NativeLogger.i('Linux[CT]: candidateDirs=${candidateDirs.join('; ')}');
      for (final dir in candidateDirs) {
        for (final name in ['libct.so', 'libct.so.4', 'libct.so.4.0.0']) {
          final p = '$dir/$name';
          try {
            NativeLogger.i('Linux[CT]: trying $p');
            final lib = DynamicLibrary.open(p);
            NativeLogger.i('Linux[CT]: opened $p');
            return lib;
          } catch (e) {
            NativeLogger.w('Linux[CT]: failed $p -> $e');
          }
        }
      }
      // Fallback to default name resolution on the system
      NativeLogger.i('Linux[CT]: falling back to system names');
      for (final name in ['libct.so', 'libct.so.4', 'libct.so.4.0.0']) {
        try {
          NativeLogger.i('Linux[CT]: trying $name');
          final lib = DynamicLibrary.open(name);
          NativeLogger.i('Linux[CT]: opened $name');
          return lib;
        } catch (e) {
          NativeLogger.w('Linux[CT]: failed $name -> $e');
        }
      }
    } else if (Platform.isWindows) {
      // Try name first (if PATH already set)
      final tried = <String>[];
      Object? lastErr;
      try {
        NativeLogger.i('Windows[CT]: trying ct.dll by name');
        return DynamicLibrary.open('ct.dll');
      } catch (e) {
        lastErr = e;
        tried.add('ct.dll');
        NativeLogger.w('Windows[CT]: ct.dll by name failed -> $e');
      }
      try {
        final scriptDir = File.fromUri(Platform.script).parent;
        final root = scriptDir.parent;
        final rootPath = root.path;
        final candidateRootDirs = ['$rootPath\\windows\\Libraries'];
        NativeLogger.i(
          'Windows[CT]: candidateDirs(root)=${candidateRootDirs.join('; ')}',
        );
        for (final dir in candidateRootDirs) {
          final p = '$dir\\ct.dll';
          if (File(p).existsSync()) {
            _setDllDirectory(dir);
            NativeLogger.i('Windows[CT]: SetDllDirectory($dir)');
            _preloadWithAlteredSearchPath(p);
            NativeLogger.i('Windows[CT]: preload $p');
            return DynamicLibrary.open(p);
          }
        }
      } catch (_) {}
      // Also add fallbacks relative to the current working directory
      try {
        final cwd = Directory.current.path;
        final candidateCwdDirs = ['$cwd\\windows\\Libraries', cwd];
        NativeLogger.i(
          'Windows[CT]: candidateDirs(cwd)=${candidateCwdDirs.join('; ')}',
        );
        for (final dir in candidateCwdDirs) {
          final p = '$dir\\ct.dll';
          if (File(p).existsSync()) {
            _setDllDirectory(dir);
            NativeLogger.i('Windows[CT]: SetDllDirectory($dir)');
            _preloadWithAlteredSearchPath(p);
            NativeLogger.i('Windows[CT]: preload $p');
            return DynamicLibrary.open(p);
          }
        }
      } catch (_) {}
      try {
        final cwd = Directory.current.path;
        final p = '$cwd\\ct.dll';
        if (File(p).existsSync()) {
          _setDllDirectory(cwd);
          NativeLogger.i('Windows[CT]: SetDllDirectory($cwd)');
          _preloadWithAlteredSearchPath(p);
          NativeLogger.i('Windows[CT]: preload $p');
          return DynamicLibrary.open(p);
        }
      } catch (_) {}
      throw UnsupportedError(
        'Could not load FreeTDS CT-Lib for this platform. Tried: ${tried.join('; ')}${' | Last error: $lastErr'}',
      );
    }
    throw UnsupportedError('Could not load FreeTDS CT-Lib for this platform.');
  }


  static void _setDllDirectory(String dir) {
    try {
      final k32 = DynamicLibrary.open('kernel32.dll');
      final setDllDir = k32
          .lookupFunction<
            Int32 Function(Pointer<Utf16>),
            int Function(Pointer<Utf16>)
          >('SetDllDirectoryW');
      final p = dir.toNativeUtf16();
      setDllDir(p);
      malloc.free(p);
    } catch (_) {}
  }

  // Configure default DLL directory search behavior for Windows.
  // Uses SetDefaultDllDirectories to restrict search to SAFE directories and
  // adds the current working directory using AddDllDirectory.
  static void _setDefaultDllDirectories() {
    try {
      final k32 = DynamicLibrary.open('kernel32.dll');
      final setDefault = k32
          .lookupFunction<Int32 Function(Uint32), int Function(int)>(
            'SetDefaultDllDirectories',
          );
      // LOAD_LIBRARY_SEARCH_DEFAULT_DIRS = 0x00001000
      setDefault(0x00001000);
      final addDir = k32
          .lookupFunction<
            Pointer<Void> Function(Pointer<Utf16>),
            Pointer<Void> Function(Pointer<Utf16>)
          >('AddDllDirectory');
      final cwd = Directory.current.path.toNativeUtf16();
      addDir(cwd);
      malloc.free(cwd);
    } catch (_) {
      // Ignore if not supported (older OS); best-effort only.
    }
  }

  // Best-effort: Preload a DLL with altered search path so its dependencies are
  // resolved relative to the DLL's own directory. Only used on Windows.
  static void _preloadWithAlteredSearchPath(String dllPath) {
    try {
      final k32 = DynamicLibrary.open('kernel32.dll');
      final loadLibraryEx = k32
          .lookupFunction<
            Pointer<Void> Function(Pointer<Utf16>, Pointer<Void>, Uint32),
            Pointer<Void> Function(Pointer<Utf16>, Pointer<Void>, int)
          >('LoadLibraryExW');
      final p = dllPath.toNativeUtf16();
      // 0x00000008 = LOAD_WITH_ALTERED_SEARCH_PATH
      loadLibraryEx(p, nullptr, 0x00000008);
      malloc.free(p);
      // If h is null, ignore; DynamicLibrary.open will throw a useful error later.
    } catch (_) {
      // Ignore: not fatal; used as a hint only.
    }
  }
}
