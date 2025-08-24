class NativeLogger {
  static void i(String message) {
    final ts = DateTime.now().toIso8601String();
    // ignore: avoid_print
    print('[NativeLoader][INFO ][${ts}] $message');
  }

  static void w(String message) {
    final ts = DateTime.now().toIso8601String();
    // ignore: avoid_print
    print('[NativeLoader][WARN ][${ts}] $message');
  }

  static void e(String message) {
    final ts = DateTime.now().toIso8601String();
    // ignore: avoid_print
    print('[NativeLoader][ERROR][${ts}] $message');
  }
}
