enum ModulePerformanceLevel {
  full,
  light,
  dormant,
}

abstract class AppModule {
  String get id;
  String get name;
  void initialize();
  void dispose();
  void setPerformanceLevel(ModulePerformanceLevel level);
}


class ModuleManager {
  final List<AppModule> _modules = [];
  void register(AppModule module) => _modules.add(module);
  void initAll() {
    for (var m in _modules) {
      m.initialize();
    }
  }
}