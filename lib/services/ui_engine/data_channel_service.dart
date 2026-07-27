import '../../models/session_state.dart';
import '../../models/status_bar_field.dart';
import 'ui_models.dart';

/// 一条已解析的数据通道写入意图。
///
/// 由 UI 原子的 `module.properties['dataChannel']` 解析而来，
/// 记录「写到哪里」「写什么值」「语义名是什么」。
class DataChannelWrite {
  /// 语义名称，例如「好感度」。用于 vars 键名与 Prompt 展示。
  final String semanticLabel;

  /// 'local_ui_state' | 'session_var' | 'status_field'
  final String targetKind;

  /// 状态字段命中时的内部 id；未命中或非状态字段时为空。
  final String targetId;

  /// 状态字段未命中时记录的待创建名称。
  final String pendingName;

  /// 'string' | 'number' | 'bool'
  final String fieldType;

  /// 组件当前值（已转成字符串）。
  final String value;

  /// 来源元素 id，便于调试定位。
  final String sourceElementId;

  const DataChannelWrite({
    required this.semanticLabel,
    required this.targetKind,
    required this.targetId,
    required this.pendingName,
    required this.fieldType,
    required this.value,
    required this.sourceElementId,
  });

  bool get isSessionVar => targetKind == 'session_var';
  bool get isStatusField => targetKind == 'status_field';

  /// 状态字段通道但没有匹配到角色卡字段，本轮不写入。
  bool get isPendingStatus => isStatusField && targetId.trim().isEmpty;

  /// 只作用于 UI 内部，不进会话副本。
  bool get isLocalOnly => targetKind == 'local_ui_state';
}

/// A9.6-2：UI 运行时 → SessionState 单向写入。
///
/// 职责边界（见 ASSEMBLY_IMPLEMENTATION_TRACKER A9.6 章节）：
///   - 只负责把已配置数据通道的输入原子的当前值写进会话副本。
///   - 不负责 Prompt 注入（A9.6-3），不负责 LLM 回写（A9.6-4）。
///   - `local_ui_state` 通道永不进入 SessionState。
///   - 状态字段未匹配到角色卡定义（pendingName）时跳过，不凭空造字段。
class DataChannelService {
  /// 目前支持作为「输入源」写入会话副本的原子类型。
  ///
  /// progress 是显示型，不作为用户输入源，因此不在此列。
  static const Set<String> writableTypes = {
    'input',
    'select',
    'switch',
    'slider',
  };

  /// 读取原子的当前值并统一转为字符串。
  ///
  /// 与 `_sourcePortForModule` 的取值口径保持一致。
  static String? readModuleValue(UIModule module) {
    final props = module.properties;
    switch (module.type) {
      case 'input':
        final committed = props['committedValue'];
        final text = committed ?? props['text'] ?? props['value'];
        return text?.toString();
      case 'select':
        return (props['current'] ?? props['defaultValue'])?.toString();
      case 'switch':
        return (props['value'] != false).toString();
      case 'slider':
        final committed = props['committedValue'] ?? props['current'];
        if (committed is num) return _trimNumber(committed.toDouble());
        return committed?.toString();
      case 'progress':
        final current = props['current'];
        if (current is num) return _trimNumber(current.toDouble());
        return current?.toString();
      default:
        return (props['value'] ?? props['current'] ?? props['text'])
            ?.toString();
    }
  }

  static String _trimNumber(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toString();
  }

  /// 从元素树里收集所有可写数据通道（含复合组件内部子元素）。
  ///
  /// [overrideChannels] 用于复合组件暴露项：
  /// 键为子元素 id，值为 `PropertyOverride.overrides['dataChannel']`。
  static List<DataChannelWrite> collectWrites(
    List<UIElement> elements, {
    Map<String, Map<String, dynamic>> overrideChannels =
        const <String, Map<String, dynamic>>{},
  }) {
    final writes = <DataChannelWrite>[];

    void visit(List<UIElement> nodes) {
      for (final node in nodes) {
        final module = node.module;
        if (module != null) {
          final raw = overrideChannels[node.id] ??
              (module.properties['dataChannel'] is Map
                  ? Map<String, dynamic>.from(
                      module.properties['dataChannel'] as Map,
                    )
                  : null);
          if (raw != null) {
            final write = _parse(raw, module, node.id);
            if (write != null) writes.add(write);
          }
        }
        if (node.isComposite && node.composite != null) {
          visit(node.composite!.children);
        }
      }
    }

    visit(elements);
    return writes;
  }

  static DataChannelWrite? _parse(
    Map<String, dynamic> channel,
    UIModule module,
    String elementId,
  ) {
    if (!writableTypes.contains(module.type)) return null;
    final label = channel['semanticLabel']?.toString().trim() ?? '';
    if (label.isEmpty) return null;
    final value = readModuleValue(module);
    if (value == null) return null;

    return DataChannelWrite(
      semanticLabel: label,
      targetKind: channel['targetKind']?.toString() ?? 'local_ui_state',
      targetId: channel['targetId']?.toString() ?? '',
      pendingName: channel['pendingName']?.toString() ?? '',
      fieldType: channel['fieldType']?.toString() ?? 'string',
      value: value,
      sourceElementId: elementId,
    );
  }

  /// 把收集到的写入意图应用到会话副本。
  ///
  /// 返回 true 表示 [session] 实际发生了变化，调用方据此决定是否落盘。
  /// 数值型状态字段会按角色卡定义执行 clamp，避免 UI 端写出越界值。
  static bool applyWrites(
    SessionState session,
    List<DataChannelWrite> writes, {
    List<StatusBarField> statusFields = const <StatusBarField>[],
  }) {
    var changed = false;

    for (final write in writes) {
      if (write.isLocalOnly || write.isPendingStatus) continue;

      if (write.isSessionVar) {
        if (session.vars[write.semanticLabel] != write.value) {
          session.vars[write.semanticLabel] = write.value;
          changed = true;
        }
        continue;
      }

      if (write.isStatusField) {
        final field = _fieldById(statusFields, write.targetId);
        final next = field != null && field.isNumber
            ? _clampNumber(write.value, field)
            : write.value;
        if (session.statusValues[write.targetId] != next) {
          session.statusValues[write.targetId] = next;
          changed = true;
        }
      }
    }

    return changed;
  }

  static StatusBarField? _fieldById(
    List<StatusBarField> fields,
    String id,
  ) {
    for (final field in fields) {
      if (field.id == id) return field;
    }
    return null;
  }

  static String _clampNumber(String raw, StatusBarField field) {
    final parsed = double.tryParse(raw.trim());
    if (parsed == null) return raw;
    var value = parsed;
    final min = field.minValue;
    final max = field.maxValue;
    if (min != null && value < min) value = min;
    if (max != null && value > max) value = max;
    return _trimNumber(value);
  }

  /// 调试摘要：用于运行时预览的 HUD，展示本轮实际写入了什么。
  static List<String> describeWrites(List<DataChannelWrite> writes) {
    return writes.map((write) {
      final target = switch (write.targetKind) {
        'session_var' => '变量',
        'status_field' => write.isPendingStatus ? '状态待建' : '状态',
        _ => 'UI',
      };
      return '$target · ${write.semanticLabel} = ${write.value}';
    }).toList();
  }
}
