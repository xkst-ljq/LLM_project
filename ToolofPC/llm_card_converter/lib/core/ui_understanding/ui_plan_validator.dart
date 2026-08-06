import 'ui_design_plan.dart';
import 'ui_source_pack.dart';

class UiPlanValidationResult {
  final bool ok;
  final List<String> errors;
  final List<String> warnings;

  const UiPlanValidationResult({
    required this.ok,
    this.errors = const [],
    this.warnings = const [],
  });
}

/// 对 AI 输出的 UiDesignPlan 做防幻觉和结构校验。
class UiPlanValidator {
  const UiPlanValidator._();

  static UiPlanValidationResult validate(
    UiDesignPlan plan,
    UiSourcePack sourcePack,
  ) {
    final errors = <String>[];
    final warnings = <String>[];

    if (!plan.hasUi) {
      if (plan.evidenceSummary.trim().isEmpty) {
        warnings.add('AI 判断无 UI，但没有说明原因。');
      }
      return UiPlanValidationResult(ok: true, warnings: warnings);
    }

    const modes = {'opening', 'scene', 'extra_sticky', 'extra_companion'};
    if (!modes.contains(plan.uiMode)) {
      errors.add('非法 uiMode：${plan.uiMode}');
    }

    if (plan.fields.isEmpty && plan.inputs.isEmpty && plan.actions.isEmpty) {
      if (plan.uiMode == 'scene') {
        warnings.add('scene 未输出字段/输入/动作，将只生成 message_flow 与系统设置按钮。');
      } else {
        errors.add('AI 判断有 UI，但没有输出任何字段、输入框或动作。');
      }
    }
    if (plan.uiMode == 'opening' && plan.actions.isEmpty && plan.inputs.isEmpty) {
      errors.add('opening UI 必须至少有一个开场按钮或输入框。');
    }

    if (plan.sourceRefs.isEmpty && plan.fields.every((f) => f.sourceRef.isEmpty) &&
        plan.inputs.every((i) => i.sourceRef.isEmpty) &&
        plan.actions.every((a) => a.sourceRef.isEmpty)) {
      errors.add('AI 判断有 UI，但没有提供任何 sourceRef 证据。');
    }

    if (!sourcePack.hasEvidence && plan.confidence >= 0.6) {
      warnings.add('证据包没有明显 UI 证据，但 AI 仍给出较高置信度，请人工复核。');
    }

    if (plan.fields.length > 40) {
      errors.add('字段过多（${plan.fields.length}），可能把正文/世界书误识别成 UI。');
    }
    if (plan.inputs.length > 4) {
      warnings.add('输入框较多（${plan.inputs.length}），编译时会压缩布局。');
    }
    if (plan.actions.length > 24) {
      warnings.add('动作按钮较多（${plan.actions.length}），编译时会压缩布局。');
    }

    final seen = <String>{};
    for (final f in plan.fields) {
      if (f.name.trim().isEmpty) {
        errors.add('存在空字段名。');
        continue;
      }
      final key = f.name.trim().toLowerCase();
      if (!seen.add(key)) {
        warnings.add('字段「${f.name}」重复，编译时会自动去重。');
      }
      if (f.sourceRef.trim().isEmpty) {
        warnings.add('字段「${f.name}」缺少 sourceRef。');
      }
      if (f.isNumber) {
        final min = f.min ?? 0.0;
        final max = f.max ?? 100.0;
        if (max <= min) {
          errors.add('字段「${f.name}」max 必须大于 min。');
        }
        final v = _cleanNumber(f.initialValue);
        if (f.initialValue.trim().isNotEmpty && v == null) {
          warnings.add('数值字段「${f.name}」初值无法解析，将按 0 处理。');
        }
      }
    }

    for (final input in plan.inputs) {
      if (input.placeholder.trim().isEmpty) {
        errors.add('存在空输入框占位提示。');
      }
      if (input.sourceRef.trim().isEmpty) {
        warnings.add('输入框「${input.placeholder}」缺少 sourceRef。');
      }
    }

    for (final a in plan.actions) {
      if (a.label.trim().isEmpty && a.sendText.trim().isEmpty) {
        errors.add('存在空动作按钮。');
      }
      if (a.sourceRef.trim().isEmpty) {
        warnings.add('动作「${a.label.isEmpty ? a.sendText : a.label}」缺少 sourceRef。');
      }
    }

    return UiPlanValidationResult(
      ok: errors.isEmpty,
      errors: errors,
      warnings: warnings,
    );
  }

  static double? _cleanNumber(String raw) {
    if (raw.trim().isEmpty) return null;
    if (RegExp(r'[万亿千百]').hasMatch(raw)) return null;
    final m = RegExp(r'-?\d+(?:\.\d+)?').firstMatch(raw);
    if (m == null) return null;
    return double.tryParse(m.group(0)!);
  }
}
