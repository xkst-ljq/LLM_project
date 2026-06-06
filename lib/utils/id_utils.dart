class IdUtils {
  /// 生成用于数据库主键的纯数字时间戳 ID。
  ///
  /// 使用 microsecondsSinceEpoch，避免同一毫秒内连续创建多个资源时 ID 冲突。
  /// offset 用于同一次导入中批量创建多个依赖资源，仍保持纯数字，方便按 ID 推断创建顺序。
  static String timestampId([int offset = 0]) {
    return (DateTime.now().microsecondsSinceEpoch + offset).toString();
  }
}
