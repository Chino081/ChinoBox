class AppLogger {
  const AppLogger._();

  static void info(String message) {
    assert(() {
      // Avoid logging headers, cookies, proxy credentials, or request bodies.
      // ignore: avoid_print
      print('[ChinoBox] $message');
      return true;
    }());
  }

  static void warn(String message) {
    assert(() {
      // ignore: avoid_print
      print('[ChinoBox][warn] $message');
      return true;
    }());
  }
}
