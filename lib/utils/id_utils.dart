class IdUtils {
  static int _lastId = 0;

  static String timestampId([int offset = 0]) {
    final now = DateTime.now().microsecondsSinceEpoch + offset;

    if (now <= _lastId) {
      _lastId += 1;
    } else {
      _lastId = now;
    }

    return _lastId.toString();
  }
}