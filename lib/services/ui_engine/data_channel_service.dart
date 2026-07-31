import '../../models/card_entry_target.dart';
import '../../models/session_state.dart';
import '../../models/status_bar_field.dart';
import 'ui_models.dart';

/// 一条「预绑定」：UI 里写了状态字段名，但角色卡里还没有该字段。
///
/// 状态栏编辑页据此提示作者——他在 UI 里写下「生命值」之后，
/// 去建字段时不该还得自己回忆当时打的是什么名字。
class PendingStatusBinding {
  const PendingStatusBinding({
    required this.name,
    required this.initialValue,
    required this.fieldType,
    required this.sourceComponent,
  });

  /// 通道里记的字段名（pendingName）。
  final String name;

  /// 组件当前的值。字段被创建时用它做初始值——
  /// 这个方向是用户明确的：状态栏还没有该字段时，以 UI 为准。
  final String initialValue;

  /// 'number' | 'text'，来自通道的 fieldType。
  final String fieldType;

  /// 来源组件名，仅用于在提示里标明出处。
  final String sourceComponent;

  bool get isNumber => fieldType != 'text';
}

/// 一条已解析的数据通道写入意图。
///
/// 由 UI 原子的 `module.properties['dataChannel']` 解析而来，
/// 记录「写到哪里」「写什么值」「语义名是什么」。
class DataChannelWrite {
  /// 语义名称，例如「好感度」。用于 vars 键名与 Prompt 展示。
  final String semanticLabel;

  /// 'local_ui_state' | 'session_var' | 'status_field'
  final String targetKind;

  /// A13-2：角色卡设定条目的三级定位；其余情况为 null。
  final CardEntryTarget? cardTarget;

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
    this.cardTarget,
    required this.targetId,
    required this.pendingName,
    required this.fieldType,
    required this.value,
    required this.sourceElementId,
  });

  bool get isSessionVar => targetKind == 'session_var';
  bool get isStatusField => targetKind == 'status_field';

  /// A13-2：写入角色卡设定条目（实际落在会话副本的专属键上）。
  bool get isCardEntry => targetKind == 'card_entry';

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

  /// 可以显示会话副本数值的原子类型。
  ///
  /// 比 [writableTypes] 多了 progress、text——它们不作为输入源，
  /// 但很适合展示状态（如好感度进度条、状态文本）。
  static const Set<String> readableTypes = {
    'input',
    'select',
    'switch',
    'slider',
    'progress',
    'text',
  };

  /// 把会话副本的值写回组件属性。
  ///
  /// 与 [readModuleValue] 互为逆操作，取值口径必须保持一致，
  /// 否则会出现「写进去的和读出来的不是同一个字段」。
  ///
  /// 返回 true 表示该组件的属性确实被改动了。
  static bool applyValueToModule(UIModule module, String value) {
    final props = module.properties;

    bool setIfChanged(String key, dynamic next) {
      if (props[key] == next) return false;
      props[key] = next;
      return true;
    }

    switch (module.type) {
      case 'input':
        var changed = setIfChanged('text', value);
        changed = setIfChanged('value', value) || changed;
        changed = setIfChanged('committedValue', value) || changed;
        return changed;
      case 'select':
        return setIfChanged('current', value);
      case 'switch':
        final on = value == 'true' || value == '1' || value == '开启';
        return setIfChanged('value', on);
      case 'slider':
      case 'progress':
        final parsed = double.tryParse(value.trim());
        if (parsed == null) return false;
        // 尊重组件自身的量程，避免把滑块推到轨道外。
        final min = (props['min'] as num?)?.toDouble() ?? 0.0;
        final max = (props['max'] as num?)?.toDouble() ?? 100.0;
        final clamped = parsed.clamp(min, max).toDouble();
        var changed = setIfChanged('current', clamped);
        if (module.type == 'slider') {
          changed = setIfChanged('committedValue', clamped) || changed;
        }
        return changed;
      case 'text':
        return setIfChanged('text', value);
      default:
        return false;
    }
  }

  /// 反向同步：把会话副本的值回填到配置了数据通道的组件上。
  ///
  /// 只回填 `session_var` / `status_field` 通道——`local_ui_state`
  /// 本就只活在 UI 内部，没有外部数据源。
  ///
  /// 返回 true 表示至少有一个组件被更新，调用方据此决定是否重建。
  static bool applySessionToElements(
    List<UIElement> elements,
    SessionState session, {
    Map<String, Map<String, dynamic>> overrideChannels =
        const <String, Map<String, dynamic>>{},
  }) {
    var changed = false;

    void visit(List<UIElement> nodes) {
      for (final node in nodes) {
        final module = node.module;
        if (module != null && readableTypes.contains(module.type)) {
          final raw = overrideChannels[node.id] ??
              (module.properties['dataChannel'] is Map
                  ? Map<String, dynamic>.from(
                      module.properties['dataChannel'] as Map,
                    )
                  : null);
          if (raw != null) {
            final value = _resolveSessionValue(raw, session);
            if (value != null && applyValueToModule(module, value)) {
              changed = true;
            }
          }
        }
        if (node.isComposite && node.composite != null) {
          visit(node.composite!.children);
        }
      }
    }

    visit(elements);
    return changed;
  }

  // ==========================================================================
  // 编辑期初始值同步（UI 组装页 ⇄ 状态栏编辑页）
  // ==========================================================================
  //
  // 与运行时的 `applySessionToElements` 是**两回事**：
  // 那个同步的是会话里的实时值，只在运行时预览生效；
  // 这里同步的是**初始值**，让作者在两个编辑页之间看到一致的数据。
  //
  // 方向规则（用户明确）：
  //
  // | 场景 | 源 |
  // |---|---|
  // | 状态栏已有该字段，UI 绑定它 | 状态栏 → UI |
  // | UI 有预绑定、状态栏还没建，此时新建字段 | UI → 状态栏 |
  // | 绑定成立后改任一侧初始值 | 双向，以最后保存的一侧为准 |
  //
  // 「预绑定」= 通道写了状态字段名但角色卡里还没有同名字段，
  // 此时 targetId 为空、pendingName 记着那个名字。

  /// 把状态栏字段的**初始值**回填到绑定它的组件上（编辑期）。
  ///
  /// 只处理 `targetKind == 'status_field'` 且已解析出 targetId 的通道——
  /// 预绑定（targetId 为空）的通道没有对应字段，反而应该由 UI 提供初始值。
  ///
  /// 返回 true 表示有组件被改动，调用方需要持久化。
  static bool applyStatusFieldInitialValues(
    List<UIElement> elements,
    List<StatusBarField> fields,
  ) {
    if (fields.isEmpty) return false;
    final byId = <String, StatusBarField>{
      for (final f in fields) f.id: f,
    };

    var changed = false;

    void visit(List<UIElement> nodes) {
      for (final node in nodes) {
        final module = node.module;
        if (module != null) {
          final raw = module.properties['dataChannel'];
          if (raw is Map) {
            final channel = Map<String, dynamic>.from(raw);
            if (channel['targetKind']?.toString() == 'status_field') {
              final targetId = channel['targetId']?.toString().trim() ?? '';
              final field = targetId.isEmpty ? null : byId[targetId];
              final value = field?.initialValue.trim() ?? '';
              if (value.isNotEmpty && applyValueToModule(module, value)) {
                changed = true;
              }
            }
          }
        }
        if (node.isComposite && node.composite != null) {
          visit(node.composite!.children);
        }
      }
    }

    visit(elements);
    return changed;
  }

  /// 收集所有「预绑定」条目：写了状态字段名、但角色卡里还没有该字段。
  ///
  /// 供状态栏编辑页在新建字段时提示——作者在 UI 里写下「生命值」之后，
  /// 去状态栏建字段时不该还得自己回忆当时打的是什么。
  ///
  /// 同名多处引用只返回一条，值取第一个非空的。
  static List<PendingStatusBinding> collectPendingStatusBindings(
    List<UIElement> elements,
  ) {
    final out = <String, PendingStatusBinding>{};

    void visit(List<UIElement> nodes) {
      for (final node in nodes) {
        final module = node.module;
        if (module != null) {
          final raw = module.properties['dataChannel'];
          if (raw is Map) {
            final channel = Map<String, dynamic>.from(raw);
            if (channel['targetKind']?.toString() == 'status_field') {
              final targetId = channel['targetId']?.toString().trim() ?? '';
              final pending =
                  channel['pendingName']?.toString().trim() ?? '';
              // targetId 非空 = 已经绑上真实字段，不是预绑定。
              if (targetId.isEmpty && pending.isNotEmpty) {
                final existing = out[pending];
                final value = readModuleValue(module)?.trim() ?? '';
                if (existing == null) {
                  out[pending] = PendingStatusBinding(
                    name: pending,
                    initialValue: value,
                    fieldType:
                        channel['fieldType']?.toString() ?? 'number',
                    sourceComponent: module.name,
                  );
                } else if (existing.initialValue.isEmpty &&
                    value.isNotEmpty) {
                  out[pending] = PendingStatusBinding(
                    name: existing.name,
                    initialValue: value,
                    fieldType: existing.fieldType,
                    sourceComponent: existing.sourceComponent,
                  );
                }
              }
            }
          }
        }
        if (node.isComposite && node.composite != null) {
          visit(node.composite!.children);
        }
      }
    }

    visit(elements);
    return out.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  /// 从会话副本里取出该通道对应的值；无对应数据时返回 null。
  static String? _resolveSessionValue(
    Map<String, dynamic> channel,
    SessionState session,
  ) {
    final targetKind = channel['targetKind']?.toString() ?? 'local_ui_state';

    if (targetKind == 'status_field') {
      final targetId = channel['targetId']?.toString() ?? '';
      // 未匹配到角色卡字段（pendingName）时没有可靠数据源。
      if (targetId.trim().isEmpty) return null;
      return session.statusValues[targetId];
    }

    if (targetKind == 'session_var') {
      final label = channel['semanticLabel']?.toString().trim() ?? '';
      if (label.isEmpty) return null;
      return session.vars[label];
    }

    if (targetKind == 'card_entry') {
      final target = CardEntryTarget.fromJson(channel['cardEntryTarget']);
      if (target == null || !target.isValid) return null;
      return session.vars[target.sessionKey];
    }

    return null;
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
      cardTarget: CardEntryTarget.fromJson(channel['cardEntryTarget']),
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

      if (write.isCardEntry) {
        final target = write.cardTarget;
        // 定位不完整时无处可写。自定义条目尤其常见：
        // 作者选了「添加自定义条目」但还没填标题。
        if (target == null || !target.isValid) continue;
        if (session.vars[target.sessionKey] != write.value) {
          session.vars[target.sessionKey] = write.value;
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
