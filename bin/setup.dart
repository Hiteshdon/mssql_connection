// Copies the native FreeTDS libraries bundled with this package into a
// consuming Flutter app's platform folders.
//
// mssql_connection is a pure Dart package (no `flutter:` plugin section) so
// it also works in plain Dart backend/CLI projects. That means Flutter's
// automatic native-library bundling (which only kicks in for registered
// Flutter plugins) does not apply here — Flutter apps need to run this
// script once after adding the dependency:
//
//   dart run mssql_connection:setup
//
// Run it from the root of your Flutter app (next to its pubspec.yaml).
// Re-run it after `flutter clean` or whenever you upgrade this package.
import 'dart:io';
import 'dart:isolate';

Future<void> main(List<String> args) async {
  final packageRoot = await _packageRoot();
  if (packageRoot == null) {
    stderr.writeln(
      'Could not locate the mssql_connection package directory. '
      'Run this from a project that depends on mssql_connection.',
    );
    exitCode = 1;
    return;
  }

  final appRoot = Directory.current;
  if (!File('${appRoot.path}/pubspec.yaml').existsSync()) {
    stderr.writeln(
      'No pubspec.yaml found in ${appRoot.path}.\n'
      'Run "dart run mssql_connection:setup" from the root of your '
      'Flutter app (the directory containing its pubspec.yaml).',
    );
    exitCode = 1;
    return;
  }

  print('mssql_connection setup');
  print('  package: $packageRoot');
  print('  app:     ${appRoot.path}\n');

  var didSomething = false;
  didSomething |= _setupAndroid(packageRoot, appRoot.path);
  didSomething |= _setupLinux(packageRoot, appRoot.path);
  didSomething |= _setupWindows(packageRoot, appRoot.path);
  didSomething |= _setupMacos(packageRoot, appRoot.path);
  didSomething |= _setupIos(packageRoot, appRoot.path);

  if (!didSomething) {
    print(
      'No android/, ios/, macos/, linux/, or windows/ folders found under '
      '${appRoot.path}.\nIf this is a Flutter app, run "flutter create ." '
      'first to generate the platform folders, then re-run this setup.',
    );
    return;
  }

  print('\nDone. Re-run "dart run mssql_connection:setup" after '
      '"flutter clean" or after upgrading mssql_connection.');
}

/// Copies [src] to [destPath], skipping the copy if they already resolve to
/// the same file (e.g. when this script is run from within the
/// mssql_connection repo itself, where packageRoot == appRoot). Without this
/// guard, File.copySync onto its own path truncates the source before the
/// copy finishes, corrupting it.
void _safeCopy(File src, String destPath) {
  final srcAbs = src.absolute.path;
  final destAbs = File(destPath).absolute.path;
  if (srcAbs == destAbs) return;
  src.copySync(destPath);
}

Future<String?> _packageRoot() async {
  try {
    // `dart run mssql_connection:setup` executes from a compiled snapshot
    // under the *consumer's* .dart_tool/pub/bin, so Platform.script does not
    // point at this package's source. Resolve the package: URI instead,
    // which the package_config.json maps back to the real package location
    // (pub cache, or a path/git dependency checkout).
    final packageUri = Uri.parse('package:mssql_connection/mssql_connection.dart');
    final resolved = await Isolate.resolvePackageUri(packageUri);
    if (resolved == null) return null;
    // resolved -> <packageRoot>/lib/mssql_connection.dart
    final libDir = File.fromUri(resolved).parent;
    return libDir.parent.path;
  } catch (_) {
    return null;
  }
}

bool _setupAndroid(String packageRoot, String appRoot) {
  final srcJniLibs = Directory('$packageRoot/android/src/main/jniLibs');
  final androidApp = Directory('$appRoot/android/app');
  if (!srcJniLibs.existsSync() || !androidApp.existsSync()) return false;

  print('[Android] Copying native libraries into android/app/src/main/jniLibs ...');
  final destJniLibs = Directory('${androidApp.path}/src/main/jniLibs');
  var copied = 0;
  for (final abiDir in srcJniLibs.listSync().whereType<Directory>()) {
    final abi = abiDir.uri.pathSegments.where((s) => s.isNotEmpty).last;
    final destAbiDir = Directory('${destJniLibs.path}/$abi');
    destAbiDir.createSync(recursive: true);
    for (final f in abiDir.listSync().whereType<File>()) {
      final name = f.uri.pathSegments.last;
      _safeCopy(f, '${destAbiDir.path}/$name');
      copied++;
    }
  }
  print('[Android] Copied $copied file(s).');
  print(
    '[Android] Reminder: restrict your app to the bundled ABIs '
    '(arm64-v8a, armeabi-v7a, x86_64) in android/app/build.gradle.kts:\n'
    '    ndk { abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86_64") }\n'
    '  This plugin ships no x86 (32-bit) binaries, so 32-bit emulators will '
    'still fail to load the library.',
  );
  return true;
}

bool _setupLinux(String packageRoot, String appRoot) {
  final srcLib = Directory('$packageRoot/linux/Libraries/lib');
  final linuxDir = Directory('$appRoot/linux');
  if (!srcLib.existsSync() || !linuxDir.existsSync()) return false;

  print('[Linux] Copying native libraries into linux/Libraries/lib ...');
  final destLib = Directory('$appRoot/linux/Libraries/lib');
  destLib.createSync(recursive: true);
  var copied = 0;
  for (final f in srcLib.listSync().whereType<File>()) {
    final name = f.uri.pathSegments.last;
    if (name.endsWith('.la')) continue; // libtool metadata, not needed
    _safeCopy(f, '${destLib.path}/$name');
    copied++;
  }
  print('[Linux] Copied $copied file(s).');
  print(
    '[Linux] Reminder: this works for `flutter run -d linux` (relative-path '
    'lookup). For a packaged release build, also copy linux/Libraries/lib/* '
    'next to the built executable\'s lib/ folder '
    '(build/linux/x64/release/bundle/lib/) as a post-build step.',
  );
  return true;
}

bool _setupWindows(String packageRoot, String appRoot) {
  final srcBin = Directory('$packageRoot/windows/Libraries/bin');
  final windowsDir = Directory('$appRoot/windows');
  if (!srcBin.existsSync() || !windowsDir.existsSync()) return false;

  print('[Windows] Copying native libraries into windows/Libraries/bin ...');
  final destBin = Directory('$appRoot/windows/Libraries/bin');
  destBin.createSync(recursive: true);
  var copied = 0;
  for (final f in srcBin.listSync().whereType<File>()) {
    final name = f.uri.pathSegments.last;
    _safeCopy(f, '${destBin.path}/$name');
    copied++;
  }
  print('[Windows] Copied $copied file(s).');
  print(
    '[Windows] Reminder: this works for `flutter run -d windows` '
    '(relative-path lookup). For a packaged release build, also copy '
    'windows/Libraries/bin/*.dll next to the built .exe '
    '(build/windows/x64/runner/Release/) as a post-build step.',
  );
  return true;
}

bool _setupMacos(String packageRoot, String appRoot) {
  final srcLib = Directory('$packageRoot/macos/Libraries/lib');
  final macosDir = Directory('$appRoot/macos');
  if (!srcLib.existsSync() || !macosDir.existsSync()) return false;

  print('[macOS] Copying native libraries into macos/Libraries/lib ...');
  final destLib = Directory('$appRoot/macos/Libraries/lib');
  destLib.createSync(recursive: true);
  var copied = 0;
  for (final f in srcLib.listSync().whereType<File>()) {
    final name = f.uri.pathSegments.last;
    if (name.endsWith('.la')) continue;
    _safeCopy(f, '${destLib.path}/$name');
    copied++;
  }
  print('[macOS] Copied $copied file(s).');
  print(
    '[macOS] Reminder: for a packaged/signed app, add a "Run Script" build '
    'phase in Xcode that copies macos/Libraries/lib/*.dylib into the app '
    'bundle\'s Contents/Frameworks and codesigns them, or install FreeTDS '
    'via Homebrew on the target machine (brew install freetds).',
  );
  return true;
}

bool _setupIos(String packageRoot, String appRoot) {
  final srcFrameworks = Directory('$packageRoot/ios/FreeTDS');
  final iosDir = Directory('$appRoot/ios');
  if (!srcFrameworks.existsSync() || !iosDir.existsSync()) return false;

  print(
    '[iOS] Native libraries ship as static XCFrameworks at:\n'
    '  $packageRoot/ios/FreeTDS/FreeTDS-CT.xcframework\n'
    '  $packageRoot/ios/FreeTDS/FreeTDS-DB.xcframework\n'
    '[iOS] Manual step required: open ios/Runner.xcworkspace in Xcode, then '
    'drag both .xcframework folders into the Runner target under '
    '"Frameworks, Libraries, and Embedded Content" (Embed: "Do Not Embed", '
    'since these are static libraries linked directly into the app binary).',
  );
  return true;
}
