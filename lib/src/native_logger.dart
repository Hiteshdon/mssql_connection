class NativeLogger {
  static bool enabled = false;

  static void i(String message) {
    if (!enabled) return;
    final ts = DateTime.now().toIso8601String();
    // ignore: avoid_print
    print('[NativeLoader][INFO ][$ts] $message');
  }

  static void w(String message) {
    if (!enabled) return;
    final ts = DateTime.now().toIso8601String();
    // ignore: avoid_print
    print('[NativeLoader][WARN ][$ts] $message');
  }

  static void e(String message) {
    if (!enabled) return;
    final ts = DateTime.now().toIso8601String();
    // ignore: avoid_print
    print('[NativeLoader][ERROR][$ts] $message');
  }
}

class MssqlLogger {
  static bool enabled = false;

  static void i(String message) {
    if (!enabled) return;
    final ts = DateTime.now().toIso8601String();
    // ignore: avoid_print
    print('[MssqlClient][INFO ][$ts] $message');
  }

  static void w(String message) {
    if (!enabled) return;
    final ts = DateTime.now().toIso8601String();
    // ignore: avoid_print
    print('[MssqlClient][WARN ][$ts] $message');
  }

  static void e(String message) {
    if (!enabled) return;
    final ts = DateTime.now().toIso8601String();
    // ignore: avoid_print
    print('[MssqlClient][ERROR][$ts] $message');
  }
}
