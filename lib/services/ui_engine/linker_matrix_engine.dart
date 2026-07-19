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
  final List<String>? allowedTargetTypes; // targetType 为 any 时的精确目标白名单
  final List<String>? excludedSourceTypes; // sourceType 为 any 时排除的来源类型
  final bool isPulse; // 是否为脉冲事件型（而非状态持续型）
  final List<SchemeParamField> params; // 该 Scheme 专用的配置参数列表

  const SchemeDefinition({
    required this.id,
    required this.label,
    required this.description,
    required this.sourceType,
    required this.targetType,
    this.allowedTargetTypes,
    this.excludedSourceTypes,
    this.isPulse = false,
    this.params = const [],
  });
}

/// 中央协议矩阵引擎 (LinkerMatrixEngine)
class LinkerMatrixEngine {
  /// 组件黑名单 (Blacklist Matrix): 数据源 -> 不可连接的接收端组件列表
  static const Map<String, List<String>> _blacklistMap = {
    'button': ['text', 'progress', 'indicator', 'math_node', 'line', 'image', 'button'],
    'math_node': ['input', 'select', 'timer', 'line', 'image', 'surface'],
    'switch': ['line', 'image'],
    'input': ['line', 'image', 'timer'],
    'slider': ['button', 'input', 'select', 'switch', 'timer', 'line', 'image', 'surface'],
    'select': ['progress', 'slider', 'input', 'timer', 'line', 'image'],
    'progress': ['input', 'select', 'timer', 'line', 'image', 'surface'],
    'timer': ['input', 'select', 'slider', 'math_node', 'line', 'image', 'surface'],
    'indicator': ['progress', 'slider', 'input', 'select', 'timer', 'line', 'image'],
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
    SchemeDefinition(
      id: 'click_to_timer_toggle',
      label: '切换计时器运行状态 (click → timer_toggle)',
      description: '每次点击在启动与停止 Timer 之间切换',
      sourceType: 'button',
      targetType: 'timer',
      isPulse: true,
    ),
    SchemeDefinition(
      id: 'click_to_timer_reset',
      label: '重置计时器 (click → timer_reset)',
      description: '点击脉冲停止 Timer 并清空当前值与 Tick 计数',
      sourceType: 'button',
      targetType: 'timer',
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
      excludedSourceTypes: ['text'],
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
      id: 'boolean_to_visible',
      label: '开关控制可见性 (switch → visible)',
      description: '开关开启时显示目标组件，关闭时在预览和运行时隐藏',
      sourceType: 'switch',
      targetType: 'any',
      allowedTargetTypes: [
        'surface', 'surface_art', 'primitive_art', 'text', 'progress',
        'slider', 'input', 'button', 'switch', 'select', 'indicator',
      ],
    ),
    SchemeDefinition(
      id: 'boolean_to_enabled',
      label: '开关控制交互使能 (switch → enabled)',
      description: '开关开启时允许目标交互，关闭时禁用并淡化',
      sourceType: 'switch',
      targetType: 'any',
      allowedTargetTypes: [
        'button', 'input', 'slider', 'switch', 'select', 'indicator',
      ],
    ),
    SchemeDefinition(
      id: 'boolean_to_locked',
      label: '开关控制编辑锁定 (switch → locked)',
      description: '开关开启时锁定目标编辑，关闭时解除锁定',
      sourceType: 'switch',
      targetType: 'any',
      allowedTargetTypes: ['button', 'input', 'slider', 'switch', 'select'],
    ),
    SchemeDefinition(
      id: 'boolean_to_frozen',
      label: '开关控制数值冻结 (switch → frozen)',
      description: '开关开启时冻结目标的外部数值更新，关闭时恢复更新',
      sourceType: 'switch',
      targetType: 'any',
      allowedTargetTypes: ['progress', 'math_node'],
    ),
    SchemeDefinition(
      id: 'boolean_to_timer_running',
      label: '系统条件控制计时器 (switch → timer)',
      description: '开关开启时 Timer 运行，关闭时 Timer 停止',
      sourceType: 'switch',
      targetType: 'timer',
    ),

    // --- input (输入框) ---
    SchemeDefinition(
      id: 'input_live_to_text',
      label: '输入实时同步文本 (input → text)',
      description: '每次输入立即更新目标文本',
      sourceType: 'input',
      targetType: 'text',
    ),
    SchemeDefinition(
      id: 'input_commit_to_text',
      label: '输入提交后同步文本 (input → text)',
      description: '输入法完成、回车或失焦后更新目标文本，保留输入框内容',
      sourceType: 'input',
      targetType: 'text',
    ),
    SchemeDefinition(
      id: 'input_submit_to_text_clear',
      label: '提交文本并清空输入框 (input → text)',
      description: '提交值写入目标文本后立即清空输入框，适合快速记录与短指令',
      sourceType: 'input',
      targetType: 'text',
    ),
    SchemeDefinition(
      id: 'input_nonempty_to_button_enable',
      label: '输入非空启用按钮 (input → button)',
      description: '输入去除空白后有内容时启用按钮，无内容时禁用',
      sourceType: 'input',
      targetType: 'button',
    ),
    SchemeDefinition(
      id: 'input_valid_to_button_enable',
      label: '输入校验启用按钮 (input → button)',
      description: '输入通过 required 与 maxLength 校验时启用按钮',
      sourceType: 'input',
      targetType: 'button',
    ),
    SchemeDefinition(
      id: 'input_validity_to_indicator',
      label: '输入校验状态驱动指示灯 (input → indicator)',
      description: '向状态灯传入 empty、valid 或 invalid，由状态规则决定颜色',
      sourceType: 'input',
      targetType: 'indicator',
    ),
    SchemeDefinition(
      id: 'input_length_to_indicator',
      label: '输入长度驱动指示灯 (input → indicator)',
      description: '向状态灯传入当前字符长度，由范围规则决定颜色',
      sourceType: 'input',
      targetType: 'indicator',
    ),
    SchemeDefinition(
      id: 'input_value_to_select_match',
      label: '输入精确匹配选项 (input → select)',
      description: '输入内容与选项完全匹配时自动切换 Select；不匹配时保持当前选项',
      sourceType: 'input',
      targetType: 'select',
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
    SchemeDefinition(
      id: 'select_value_to_surface_visible',
      label: '选项控制面板可见性 (select → surface)',
      description: '选中值匹配时显示目标 Surface，不匹配时隐藏',
      sourceType: 'select',
      targetType: 'any',
      allowedTargetTypes: ['surface', 'surface_art', 'primitive_art'],
      params: [
        SchemeParamField(
          key: 'triggerValue',
          label: '匹配选项值',
          type: SchemeParamType.text,
          defaultValue: '',
          description: '填写 Select 选项中的完整文本',
        ),
      ],
    ),
    SchemeDefinition(
      id: 'select_value_to_switch',
      label: '选项控制开关状态 (select → switch)',
      description: '选中值匹配时开启 Switch，不匹配时关闭',
      sourceType: 'select',
      targetType: 'switch',
      params: [
        SchemeParamField(
          key: 'triggerValue',
          label: '匹配选项值',
          type: SchemeParamType.text,
          defaultValue: '',
          description: '填写 Select 选项中的完整文本',
        ),
      ],
    ),

    // --- progress (进度条数据源) ---
    SchemeDefinition(
      id: 'progress_to_text',
      label: '进度数据转文本 (progress → text)',
      description: '输出当前值、最大值、百分比或范围文本',
      sourceType: 'progress',
      targetType: 'text',
      params: [
        SchemeParamField(
          key: 'sourceField',
          label: '输出字段',
          type: SchemeParamType.choice,
          defaultValue: 'current',
          options: ['current', 'max', 'percentage', 'range'],
        ),
        SchemeParamField(
          key: 'precision',
          label: '保留小数位数',
          type: SchemeParamType.number,
          defaultValue: 0,
        ),
        SchemeParamField(
          key: 'template',
          label: '格式模板（可选 {{value}}）',
          type: SchemeParamType.text,
          defaultValue: '{{value}}',
        ),
      ],
    ),
    SchemeDefinition(
      id: 'progress_to_math_param',
      label: '进度数值注入计算参数 (progress → math)',
      description: '将当前值或最大值注入 Math Node 指定参数口',
      sourceType: 'progress',
      targetType: 'math_node',
      params: [
        SchemeParamField(
          key: 'sourceField',
          label: '输入字段',
          type: SchemeParamType.choice,
          defaultValue: 'current',
          options: ['current', 'max'],
        ),
        SchemeParamField(
          key: 'targetParam',
          label: '目标参数口',
          type: SchemeParamType.choice,
          defaultValue: 'paramA',
          options: ['paramA', 'paramB', 'paramC'],
        ),
      ],
    ),
    SchemeDefinition(
      id: 'progress_threshold_to_button_enable',
      label: '进度阈值启用按钮 (progress → button)',
      description: '进度满足阈值条件时启用按钮，否则禁用',
      sourceType: 'progress',
      targetType: 'button',
      params: [
        SchemeParamField(
          key: 'operator',
          label: '比较条件',
          type: SchemeParamType.choice,
          defaultValue: '>=',
          options: ['>', '<', '>=', '<=', '=='],
        ),
        SchemeParamField(
          key: 'threshold',
          label: '阈值',
          type: SchemeParamType.doubleVal,
          defaultValue: 100.0,
        ),
      ],
    ),
    SchemeDefinition(
      id: 'progress_threshold_to_switch',
      label: '进度阈值控制开关 (progress → switch)',
      description: '进度满足阈值条件时开启 Switch，否则关闭',
      sourceType: 'progress',
      targetType: 'switch',
      params: [
        SchemeParamField(
          key: 'operator',
          label: '比较条件',
          type: SchemeParamType.choice,
          defaultValue: '>=',
          options: ['>', '<', '>=', '<=', '=='],
        ),
        SchemeParamField(
          key: 'threshold',
          label: '阈值',
          type: SchemeParamType.doubleVal,
          defaultValue: 100.0,
        ),
      ],
    ),

    // ==========================================
    // Phase 3: 高级功能与自动化 Phase 协议族
    // ==========================================

    // --- text (只读展示数据源) ---
    SchemeDefinition(
      id: 'text_extract_to_math_param',
      label: '文本取数注入计算参数 (text → math)',
      description: '从纯数值、首个数、第 N 个数或关键字字段中提取数值',
      sourceType: 'text',
      targetType: 'math_node',
      params: [
        SchemeParamField(
          key: 'targetParam',
          label: '目标参数口',
          type: SchemeParamType.choice,
          defaultValue: 'paramA',
          options: ['paramA', 'paramB', 'paramC'],
        ),
        SchemeParamField(
          key: 'extractMode',
          label: '取数方式',
          type: SchemeParamType.choice,
          defaultValue: 'whole',
          options: ['whole', 'first', 'index', 'key'],
        ),
        SchemeParamField(
          key: 'numberIndex',
          label: '数值序号（从 0 开始）',
          type: SchemeParamType.number,
          defaultValue: 0,
        ),
        SchemeParamField(
          key: 'key',
          label: '关键字',
          type: SchemeParamType.text,
          defaultValue: '',
          description: '例如 HP，可提取“HP：75”中的 75',
        ),
        SchemeParamField(
          key: 'parseFailBehavior',
          label: '提取失败时',
          type: SchemeParamType.choice,
          defaultValue: 'zero',
          options: ['zero', 'keep'],
        ),
      ],
    ),
    SchemeDefinition(
      id: 'text_match_to_switch',
      label: '文本匹配控制开关 (text → switch)',
      description: '文本匹配时开启 Switch，不匹配时关闭',
      sourceType: 'text',
      targetType: 'switch',
      params: [
        SchemeParamField(
          key: 'triggerText',
          label: '匹配文本',
          type: SchemeParamType.text,
          defaultValue: '',
        ),
      ],
    ),
    SchemeDefinition(
      id: 'text_nonempty_to_button_enable',
      label: '文本非空启用按钮 (text → button)',
      description: '文本去除空白后有内容时启用按钮',
      sourceType: 'text',
      targetType: 'button',
    ),
    SchemeDefinition(
      id: 'text_match_to_button_enable',
      label: '文本匹配启用按钮 (text → button)',
      description: '文本匹配时启用按钮，不匹配时禁用',
      sourceType: 'text',
      targetType: 'button',
      params: [
        SchemeParamField(
          key: 'triggerText',
          label: '匹配文本',
          type: SchemeParamType.text,
          defaultValue: '',
        ),
      ],
    ),
    SchemeDefinition(
      id: 'text_value_to_select_match',
      label: '文本精确匹配选项 (text → select)',
      description: '文本与选项完全匹配时切换 Select，不匹配时保持当前选项',
      sourceType: 'text',
      targetType: 'select',
    ),

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
      id: 'timer_tick_to_switch_set_true',
      label: '定时脉冲设为开启 (timer_tick → switch_on)',
      description: '每到一次定时 Tick，强制将目标 switch 设为 true',
      sourceType: 'timer',
      targetType: 'switch',
      isPulse: true,
    ),
    SchemeDefinition(
      id: 'timer_tick_to_switch_set_false',
      label: '定时脉冲设为关闭 (timer_tick → switch_off)',
      description: '每到一次定时 Tick，强制将目标 switch 设为 false',
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
          label: '单次步长',
          type: SchemeParamType.doubleVal,
          defaultValue: 5.0,
        ),
        SchemeParamField(
          key: 'boundaryBehavior',
          label: '到达边界后',
          type: SchemeParamType.choice,
          defaultValue: 'stop',
          options: ['stop', 'loop', 'pingPong'],
        ),
      ],
    ),
    SchemeDefinition(
      id: 'timer_tick_to_progress_decrement',
      label: '定时脉冲递减进度 (timer_tick → progress_dec)',
      description: '每到一次定时 Tick，驱动进度条减少固定步长',
      sourceType: 'timer',
      targetType: 'progress',
      isPulse: true,
      params: [
        SchemeParamField(
          key: 'step',
          label: '单次步长',
          type: SchemeParamType.doubleVal,
          defaultValue: 5.0,
        ),
        SchemeParamField(
          key: 'boundaryBehavior',
          label: '到达边界后',
          type: SchemeParamType.choice,
          defaultValue: 'stop',
          options: ['stop', 'loop', 'pingPong'],
        ),
      ],
    ),

    SchemeDefinition(
      id: 'timer_value_to_text',
      label: '计时器数值显示文本 (timer → text)',
      description: '输出当前值、Tick 次数或步长，由 Text 负责格式化展示',
      sourceType: 'timer',
      targetType: 'text',
      params: [
        SchemeParamField(
          key: 'sourceField',
          label: '输出字段',
          type: SchemeParamType.choice,
          defaultValue: 'currentVal',
          options: ['currentVal', 'tickCount', 'stepValue'],
        ),
        SchemeParamField(
          key: 'precision',
          label: '保留小数位数',
          type: SchemeParamType.number,
          defaultValue: 0,
        ),
      ],
    ),

    // --- indicator (状态指示点数据源) ---

    // --- indicator (颜色通道路由源) ---
    SchemeDefinition(
      id: 'indicator_color_to_switch',
      label: '颜色通道控制开关 (indicator → switch)',
      description: '当前激活颜色匹配时开关为 true，不匹配时为 false',
      sourceType: 'indicator',
      targetType: 'switch',
      params: [
        SchemeParamField(
          key: 'triggerColor',
          label: '监听颜色通道',
          type: SchemeParamType.color,
          defaultValue: 0xFF4CAF50,
        ),
      ],
    ),
    SchemeDefinition(
      id: 'indicator_color_to_text',
      label: '颜色通道显示文案 (indicator → text)',
      description: '当前激活颜色匹配时显示匹配文案，否则显示未匹配文案',
      sourceType: 'indicator',
      targetType: 'text',
      params: [
        SchemeParamField(
          key: 'triggerColor',
          label: '监听颜色通道',
          type: SchemeParamType.color,
          defaultValue: 0xFF4CAF50,
        ),
        SchemeParamField(
          key: 'matchText',
          label: '匹配时文案',
          type: SchemeParamType.text,
          defaultValue: '已激活',
        ),
        SchemeParamField(
          key: 'mismatchText',
          label: '未匹配时文案',
          type: SchemeParamType.text,
          defaultValue: '',
        ),
      ],
    ),
    SchemeDefinition(
      id: 'indicator_color_to_button_enable',
      label: '颜色通道控制按钮使能 (indicator → button)',
      description: '当前激活颜色匹配时按钮可点击，不匹配时禁用',
      sourceType: 'indicator',
      targetType: 'button',
      params: [
        SchemeParamField(
          key: 'triggerColor',
          label: '监听颜色通道',
          type: SchemeParamType.color,
          defaultValue: 0xFF4CAF50,
        ),
      ],
    ),
    SchemeDefinition(
      id: 'indicator_color_to_visible',
      label: '颜色通道控制可见性 (indicator → visible)',
      description: '当前激活颜色匹配时显示目标，不匹配时隐藏目标',
      sourceType: 'indicator',
      targetType: 'any',
      allowedTargetTypes: [
        'surface', 'surface_art', 'primitive_art', 'text', 'progress',
        'slider', 'input', 'button', 'switch', 'select', 'indicator',
      ],
      params: [
        SchemeParamField(
          key: 'triggerColor',
          label: '监听颜色通道',
          type: SchemeParamType.color,
          defaultValue: 0xFF4CAF50,
        ),
      ],
    ),

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
      final matchSrc = (def.sourceType == 'any' ||
              def.sourceType == normalizedSrc) &&
          !(def.excludedSourceTypes?.contains(normalizedSrc) ?? false);
      final matchTgt = def.allowedTargetTypes != null
          ? def.allowedTargetTypes!.contains(normalizedTgt)
          : def.targetType == 'any' || def.targetType == normalizedTgt;

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
