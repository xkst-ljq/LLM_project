import 'ui_models.dart';

/// LinkerService（联动器服务）
/// MVP 阶段：支持最简单的 progress.current → text.text 联动
/// 
/// 后续会扩展为支持多端口、过滤规则、可视化接线等
class LinkerService {
  /// 全局元素快照（由外部传入）
  /// 目前采用简单 Map 结构：elementId → UIModule
  static final Map<String, UIModule> _elementModules = {};

  /// 更新元素快照（每次渲染前调用）
  static void updateElementSnapshot(List<UIElement> elements) {
    _elementModules.clear();
    for (final el in elements) {
      if (!el.isComposite && el.module != null) {
        _elementModules[el.id] = el.module!;
      }
    }
  }

  /// 解析 text 模块的联动值（MVP）
  /// 目前仅支持：progress.current → text.text
  static String? resolveLinkedTextValue(UIModule textModule) {
    // 查找是否有 linker 指向这个 textModule
    for (final entry in _elementModules.entries) {
      final module = entry.value;
      if (module.type != 'linker') continue;

      final linkerData = (module.properties['linker'] as Map?)?.cast<String, dynamic>();
      if (linkerData == null) continue;

      final targetModuleId = linkerData['targetModuleId']?.toString();
      final targetPort = linkerData['targetPort']?.toString();
      final scheme = linkerData['scheme']?.toString();

      // 匹配目标
      if (targetModuleId == null || targetPort != 'text') continue;

      // 查找源模块（progress）
      final sourceModuleId = linkerData['sourceModuleId']?.toString();
      if (sourceModuleId == null || !_elementModules.containsKey(sourceModuleId)) continue;

      final sourceModule = _elementModules[sourceModuleId]!;
      if (sourceModule.type != 'progress') continue;

      // 当前仅支持 current_to_text 方案
      if (scheme != 'current_to_text') continue;

      // 获取 progress 的 current 值
      final current = sourceModule.properties['current'];
      if (current == null) continue;

      // 返回联动后的字符串
      return current.toString();
    }

    return null;
  }

  /// 判断一个模块是否被 linker 链接（用于渲染优化）
  static bool isModuleLinked(String moduleId) {
    for (final module in _elementModules.values) {
      if (module.type != 'linker') continue;
      final linkerData = (module.properties['linker'] as Map?)?.cast<String, dynamic>();
      if (linkerData?['sourceModuleId'] == moduleId || 
          linkerData?['targetModuleId'] == moduleId) {
        return true;
      }
    }
    return false;
  }
}