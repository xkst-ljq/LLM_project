import 'dart:convert';

/// 会话状态（会话副本 Prompt 机制的数据载体）。
///
/// 设计要点（见 ROADMAP「会话副本 Prompt 机制」）：
///   - 角色卡的 systemPrompt / 条目 / 世界书是「母版」，运行时永不被改写；
///     发送时由 _buildFinalSystemPrompt() 每轮重新拼装。
///   - 会话状态是叠加在母版之上的「会话副本覆盖层」，
///     由界面交互、状态栏数值（及后续的自动设定演化）写入。
///   - 统一存放在 characters 表既有的 state_json 列里（v2 已加、此前未使用），
///     因此不需要再升级数据库版本。
///   - 清空聊天记录时，会话状态被清空 → Prompt 回到纯母版（实现「改写后可还原」）。
///
/// 当前承载：
///   - vars       界面交互 / 状态栏写入的变量。渲染时以 {{var.xxx}} 注入 Prompt。
///   - overrides  预留：后续动态设定演化对副本的结构化覆盖（本期不填）。
class SessionState {
  /// 动态变量：键 -> 值。例如 {'主角姓名': '林', '主角技能': '剑术'}。
  /// 在 Prompt 中通过 {{var.主角姓名}} 引用。
  Map<String, String> vars;

  /// 状态栏当前值：字段 id -> 当前值（字符串存储，数值字段也用字符串）。
  /// 字段「定义 / 初始值」在角色卡（CharacterMeta.statusBarFields）里；
  /// 这里只存随会话变化的「当前值」，清空历史后回到初始值。
  Map<String, String> statusValues;

  /// 预留：后续动态设定演化对会话副本的结构化覆盖。
  Map<String, dynamic> overrides;

  SessionState({
    Map<String, String>? vars,
    Map<String, String>? statusValues,
    Map<String, dynamic>? overrides,
  })  : vars = vars ?? <String, String>{},
        statusValues = statusValues ?? <String, String>{},
        overrides = overrides ?? <String, dynamic>{};

  bool get isEmpty =>
      vars.isEmpty && statusValues.isEmpty && overrides.isEmpty;

  factory SessionState.fromJson(Map<String, dynamic> json) {
    Map<String, String> readVars(dynamic v) {
      if (v is Map) {
        final out = <String, String>{};
        v.forEach((key, value) {
          final k = key.toString().trim();
          if (k.isEmpty) return;
          out[k] = value?.toString() ?? '';
        });
        return out;
      }
      return <String, String>{};
    }

    Map<String, dynamic> readOverrides(dynamic v) {
      if (v is Map) return Map<String, dynamic>.from(v);
      return <String, dynamic>{};
    }

    return SessionState(
      vars: readVars(json['vars']),
      statusValues: readVars(json['status_values']),
      overrides: readOverrides(json['overrides']),
    );
  }

  /// 从 state_json 字符串解析（容错：空 / 损坏都回退为空状态）。
  factory SessionState.fromJsonString(String? raw) {
    if (raw == null || raw.trim().isEmpty) return SessionState();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return SessionState.fromJson(decoded);
      }
      if (decoded is Map) {
        return SessionState.fromJson(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {}
    return SessionState();
  }

  Map<String, dynamic> toJson() {
    return {
      'vars': vars,
      'status_values': statusValues,
      'overrides': overrides,
    };
  }

  String toJsonString() => jsonEncode(toJson());

  SessionState copy() => SessionState.fromJson(toJson());
}
