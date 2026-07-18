/// 方案参数数据类型
enum SchemeParamType {
  text,
  number,
  doubleVal,
  boolean,
  choice,
  color,
}

/// 方案参数声明 Schema
class SchemeParamField {
  final String key;
  final String label;
  final SchemeParamType type;
  final dynamic defaultValue;
  final List<String>? options; // 仅 choice 类型时生效
  final String? description;

  const SchemeParamField({
    required this.key,
    required this.label,
    required this.type,
    this.defaultValue,
    this.options,
    this.description,
  });
}

/// 传输方案定义模型
class SchemeDefinition {
  final String id;
  final String label;
  final String description;
  final String sourceType; // 源组件类型，'any' 或具体原语名称
  final String targetType; // 目标组件类型，'any' 或具体原语名称
  final bool isPulse; // 是否为脉冲事件型（而非状态持续型）
  final List<SchemeParamField> params; // 该 Scheme 专用的配置参数列表

  const SchemeDefinition({
    required this.id,
    required this.label,
    required this.description,
    required this.sourceType,
    required this.targetType,
    this.isPulse = false,
    this.params = const [],
  });
}

/// 中央协议矩阵引擎 (LinkerMatrixEngine)
class LinkerMatrixEngine {
  /// 组件黑名单 (Blacklist Matrix): 数据源 -> 不可连接的接收端组件列表
  static const Map<String, List<String>> _blacklistMap = {
    'button': ['text', 'progress', 'indicator', 'timer', 'math_node', 'line', 'image', 'button'],
    'math_node': ['input', 'select', 'timer', 'line', 'image', 'surface'],
    'switch': ['timer', 'line', 'image', 'surface'],
    'input': ['line', 'image', 'timer'],
    'slider': ['button', 'input', 'select', 'switch', 'timer', 'line', 'image', 'surface'],
    'select': ['progress', 'slider', 'input', 'timer', 'line', 'image'],
    'progress': ['input', 'select', 'timer', 'line', 'image', 'surface'],
    'timer': ['text', 'input', 'select', 'slider', 'math_node', 'line', 'image', 'surface'],
    'indicator': ['progress', 'slider', 'input', 'select', 'timer', 'line', 'image', 'surface'],
    'text': ['progress', 'slider', 'input', 'timer', 'line', 'image', 'surface'],
    'surface': ['math_node', 'timer', 'line', 'image'],
  };

  /// 全量协议方案注册表
  static const List<SchemeDefinition> _schemeRegistry = [
    // ==========================================
    // Phase 1: 核心 Phase 协议族
    // ==========================================

    // --- button (脉冲数据源) ---
    SchemeDefinition(
      id: 'click_to_surface_press',
      label: '点击触发按压动画 (click → surface_press)',
      description: 'button 点击脉冲触发 surface 的按下凹陷反馈',
      sourceType: 'button',
      targetType: 'surface',
      isPulse: true,
      params: [
        SchemeParamField(
          key: 'durationMs',
          label: '动画时长 (ms)',
          type: SchemeParamType.number,
          defaultValue: 150,
        ),
      ],
    ),
    SchemeDefinition(
      id: 'click_to_surface_ripple',
      label: '点击触发涟漪动画 (click → surface_ripple)',
      description: 'button 点击脉冲触发 surface 水波纹扩散动画',
      sourceType: 'button',
      targetType: 'surface',
      isPulse: true,
      params: [
        SchemeParamField(
          key: 'rippleRadius',
          label: '扩散半径 (px)',
          type: SchemeParamType.doubleVal,
          defaultValue: 150.0,
        ),
        SchemeParamField(
          key: 'durationMs',
          label: '动画时长 (ms)',
          type: SchemeParamType.number,
          defaultValue: 300,
        ),
      ],
    ),
    SchemeDefinition(
      id: 'click_to_switch_toggle',
      label: '翻转开关状态 (click → switch_toggle)',
      description: '每次点击脉冲，switch 状态翻转一次 (true ↔ false)',
      sourceType: 'button',
      targetType: 'switch',
      isPulse: true,
    ),
    SchemeDefinition(
      id: 'click_to_switch_set_true',
      label: '强制设为开启 (click → switch_set_true)',
      description: '每次点击脉冲，强制将 switch 设为 true',
      sourceType: 'button',
      targetType: 'switch',
      isPulse: true,
    ),
    SchemeDefinition(
      id: 'click_to_switch_set_false',
      label: '强制设为关闭 (click → switch_set_false)',
      description: '每次点击脉冲，强制将 switch 设为 false',
      sourceType: 'button',
      targetType: 'switch',
      isPulse: true,
    ),
    SchemeDefinition(
      id: 'click_to_input_clear',
      label: '一键清空输入框 (click → input_clear)',
      description: '点击脉冲清空 input 当前内容',
      sourceType: 'button',
      targetType: 'input',
      isPulse: true,
    ),
    SchemeDefinition(
      id: 'click_to_slider_reset',
      label: '重置滑块至默认值 (click → slider_reset)',
      description: '点击脉冲将滑块恢复至默认值',
      sourceType: 'button',
      targetType: 'slider',
      isPulse: true,
    ),

    // --- math_node (算术计算节点) ---
    SchemeDefinition(
      id: 'result_to_text',
      label: '计算结果渲染文本 (result → text)',
      description: '计算结果实时覆盖文本原子的模板输出',
      sourceType: 'math_node',
      targetType: 'text',
      params: [
        SchemeParamField(
          key: 'template',
          label: '展示模板 (如 {{value}})',
          type: SchemeParamType.text,
          defaultValue: '{{value}}',
          description: '包含 {{value}} 占位符',
        ),
        SchemeParamField(
          key: 'precision',
          label: '保留小数位数',
          type: SchemeParamType.number,
          defaultValue: 0,
        ),
      ],
    ),
    SchemeDefinition(
      id: 'bool_result_to_text',
      label: '布尔结果文本映射 (bool_result → text)',
      description: '根据计算结果真假，显示条件文案',
      sourceType: 'math_node',
      targetType: 'text',
      params: [
        SchemeParamField(
          key: 'trueText',
          label: '真值文案 (True)',
          type: SchemeParamType.text,
          defaultValue: '通过',
        ),
        SchemeParamField(
          key: 'falseText',
          label: '假值文案 (False)',
          type: SchemeParamType.text,
          defaultValue: '未通过',
        ),
      ],
    ),
    SchemeDefinition(
      id: 'result_to_progress',
      label: '计算结果驱动进度条 (result → progress)',
      description: '计算结果驱动进度条数值，支持比例归一化与绝对值截断',
      sourceType: 'math_node',
      targetType: 'progress',
      params: [
        SchemeParamField(
          key: 'mappingMode',
          label: '区间映射模式',
          type: SchemeParamType.choice,
          defaultValue: 'ratio',
          options: ['ratio', 'absolute'],
          description: 'ratio: 相对 0~100% 比例归一化折算；absolute: 绝对物理数值透传截断',
        ),
      ],
    ),
    SchemeDefinition(
      id: 'bool_result_to_progress',
      label: '布尔结果开/满进度 (bool_result → progress)',
      description: 'true 跳至 100%，false 跳至 0%',
      sourceType: 'math_node',
      targetType: 'progress',
    ),
    SchemeDefinition(
      id: 'value_to_math_param',
      label: '数值注入计算参数 (value → math param)',
      description: '将来源当前值转换为数值并注入目标计算节点的指定参数口',
      sourceType: 'any',
      targetType: 'math_node',
      params: [
        SchemeParamField(
          key: 'targetParam',
          label: '目标参数口',
          type: SchemeParamType.choice,
          defaultValue: 'paramA',
          options: ['paramA', 'paramB', 'paramC'],
        ),
      ],
    ),

    // --- switch (布尔开关) ---
    SchemeDefinition(
      id: 'bool_to_text',
      label: '开关切换文案显示 (switch → text)',
      description: '根据开关开启/关闭渲染对应文案',
      sourceType: 'switch',
      targetType: 'text',
      params: [
        SchemeParamField(
          key: 'trueText',
          label: '开启时文案',
          type: SchemeParamType.text,
          defaultValue: '已启用',
        ),
        SchemeParamField(
          key: 'falseText',
          label: '关闭时文案',
          type: SchemeParamType.text,
          defaultValue: '已禁用',
        ),
      ],
    ),
    SchemeDefinition(
      id: 'bool_to_visibility',
      label: '开关折叠显隐组件 (switch → visibility)',
      description: '开关开启时显示目标组件，关闭时完全折叠隐藏',
      sourceType: 'switch',
      targetType: 'any',
    ),

    // --- input (输入框) ---
    SchemeDefinition(
      id: 'text_to_text',
      label: '输入字面量实时覆盖文本 (input → text)',
      description: '输入框的内容实时输出并渲染在目标文本框中',
      sourceType: 'input',
      targetType: 'text',
      params: [
        SchemeParamField(
          key: 'template',
          label: '展示模板',
          type: SchemeParamType.text,
          defaultValue: '{{value}}',
        ),
      ],
    ),
    SchemeDefinition(
      id: 'input_to_progress',
      label: '数值输入驱动进度条 (input → progress)',
      description: '尝试解析输入的数值，驱动进度条变化',
      sourceType: 'input',
      targetType: 'progress',
    ),
    SchemeDefinition(
      id: 'input_to_slider',
      label: '数值输入驱动滑块 (input → slider)',
      description: '解析输入的数值，驱动滑块滑动',
      sourceType: 'input',
      targetType: 'slider',
    ),

    // ==========================================
    // Phase 2: 体验进阶 Phase 协议族
    // ==========================================

    // --- slider (滑块数据源) ---
    SchemeDefinition(
      id: 'slider_to_text',
      label: '滑块当前值渲染文本 (slider → text)',
      description: '滑块当前数值实时渲染到文本模板',
      sourceType: 'slider',
      targetType: 'text',
      params: [
        SchemeParamField(
          key: 'template',
          label: '格式模板',
          type: SchemeParamType.text,
          defaultValue: '{{value}}',
        ),
      ],
    ),
    SchemeDefinition(
      id: 'slider_to_progress',
      label: '滑块驱动进度条 (slider → progress)',
      description: '滑块当前数值实时同步到进度条，支持比例折算与绝对值截断',
      sourceType: 'slider',
      targetType: 'progress',
      params: [
        SchemeParamField(
          key: 'mappingMode',
          label: '区间映射模式',
          type: SchemeParamType.choice,
          defaultValue: 'ratio',
          options: ['ratio', 'absolute'],
          description: 'ratio: 相对 0~100% 比例归一化折算；absolute: 绝对物理数值透传截断',
        ),
      ],
    ),

    // --- select (单选下拉数据源) ---
    SchemeDefinition(
      id: 'select_to_text',
      label: '选中项输出文本 (select → text)',
      description: '单选组件选中的 Value/Label 输出到文本模板',
      sourceType: 'select',
      targetType: 'text',
      params: [
        SchemeParamField(
          key: 'template',
          label: '格式模板',
          type: SchemeParamType.text,
          defaultValue: '{{value}}',
        ),
      ],
    ),

    // --- progress (进度条数据源) ---
    SchemeDefinition(
      id: 'progress_to_text',
      label: '进度条数值转文本 (progress → text)',
      description: '进度条当前/最大数值格式化渲染为文本',
      sourceType: 'progress',
      targetType: 'text',
      params: [
        SchemeParamField(
          key: 'template',
          label: '格式模板 (例: {{value}}%)',
          type: SchemeParamType.text,
          defaultValue: '{{value}}%',
        ),
      ],
    ),

    // ==========================================
    // Phase 3: 高级功能与自动化 Phase 协议族
    // ==========================================

    // --- timer (定时脉冲发生器数据源) ---
    SchemeDefinition(
      id: 'timer_tick_to_switch_toggle',
      label: '定时脉冲翻转开关 (timer_tick → switch_toggle)',
      description: '每到一次定时 Tick，驱动目标 switch 翻转一次',
      sourceType: 'timer',
      targetType: 'switch',
      isPulse: true,
    ),
    SchemeDefinition(
      id: 'timer_tick_to_progress_increment',
      label: '定时脉冲推进进度 (timer_tick → progress_inc)',
      description: '每到一次定时 Tick，驱动进度条增加固定步长',
      sourceType: 'timer',
      targetType: 'progress',
      isPulse: true,
      params: [
        SchemeParamField(
          key: 'step',
          label: '单次步长增量',
          type: SchemeParamType.doubleVal,
          defaultValue: 5.0,
        ),
      ],
    ),

    // --- indicator (状态指示点数据源) ---

    // --- surface (面原子全样式全能数据源) ---
    SchemeDefinition(
      id: 'name_to_text',
      label: '表头回写 (name → text)',
      description: '源组件标识名称回写为目标文本',
      sourceType: 'surface',
      targetType: 'text',
    ),

    // --- 通用兜底 ---
    SchemeDefinition(
      id: 'to_string',
      label: '传入状态值 (value → indicator)',
      description: '将上游原始值交给状态灯自身的状态规则解释',
      sourceType: 'any',
      targetType: 'indicator',
    ),
  ];

  /// 仅已注册的方案可被选择和执行。
  static bool isSchemeSelectable(String schemeId) =>
      getSchemeDefinition(schemeId) != null;

  /// 根据源端与目标端原语类型，返回当前可用且已接入运行端的方案。
  static List<SchemeDefinition> getAvailableSchemes(
      String? sourceType,
      String? targetType,
      ) {
    if (sourceType == null || targetType == null) return const [];

    final normalizedSrc = _normalizeType(sourceType);
    final normalizedTgt = _normalizeType(targetType);

    // 检查黑名单屏蔽
    final blacklistedTargets = _blacklistMap[normalizedSrc];
    if (blacklistedTargets != null &&
        blacklistedTargets.contains(normalizedTgt)) {
      return const [];
    }

    final result = <SchemeDefinition>[];
    for (final def in _schemeRegistry) {
      final matchSrc =
          def.sourceType == 'any' || def.sourceType == normalizedSrc;
      final matchTgt =
          def.targetType == 'any' || def.targetType == normalizedTgt;

      if (matchSrc && matchTgt && isSchemeSelectable(def.id)) {
        result.add(def);
      }
    }
    return result;
  }

  /// 获取单个 Scheme 方案的完整配置元数据
  static SchemeDefinition? getSchemeDefinition(String schemeId) {
    for (final def in _schemeRegistry) {
      if (def.id == schemeId) return def;
    }
    return null;
  }

  /// 标准化组件原语名称（兼容艺术变体类型）
  static String _normalizeType(String type) {
    if (type == 'surface_art' || type == 'primitive_art') return 'surface';
    return type;
  }
}
