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
    'button': ['text', 'progress', 'indicator', 'timer', 'line', 'image', 'button'],
    'math_node': ['input', 'select', 'timer', 'line', 'image', 'surface', 'scroll_frame'],
    'switch': ['timer', 'line', 'image', 'surface', 'scroll_frame'],
    'input': ['line', 'image', 'timer', 'scroll_frame'],
    'slider': ['button', 'input', 'select', 'switch', 'timer', 'line', 'image', 'surface', 'scroll_frame'],
    'select': ['progress', 'slider', 'input', 'timer', 'line', 'image', 'scroll_frame'],
    'progress': ['input', 'select', 'timer', 'line', 'image', 'surface', 'scroll_frame'],
    'timer': ['text', 'input', 'select', 'slider', 'line', 'image', 'surface', 'scroll_frame'],
    'indicator': ['progress', 'slider', 'input', 'select', 'timer', 'line', 'image', 'surface', 'scroll_frame'],
    'text': ['progress', 'slider', 'input', 'timer', 'line', 'image', 'surface', 'scroll_frame'],
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
      id: 'click_to_math_trigger',
      label: '唤醒手动计算 (click → math_trigger)',
      description: '点击脉冲强制计算节点重算并刷新向下传导',
      sourceType: 'button',
      targetType: 'math_node',
      isPulse: true,
    ),
    SchemeDefinition(
      id: 'click_to_input_submit',
      label: '提交输入框内容 (click → input_submit)',
      description: '点击脉冲触发 input 提交当前内容',
      sourceType: 'button',
      targetType: 'input',
      isPulse: true,
      params: [
        SchemeParamField(
          key: 'clearOnSubmit',
          label: '提交后清空输入框',
          type: SchemeParamType.boolean,
          defaultValue: true,
        ),
      ],
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
      id: 'click_to_input_focus',
      label: '强制聚焦输入框 (click → input_focus)',
      description: '点击脉冲将焦点与键盘聚焦到输入框',
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
      id: 'result_to_slider_max',
      label: '结果锁定滑块上限 (result → slider_max)',
      description: '计算结果动态覆盖滑块 max 上限值',
      sourceType: 'math_node',
      targetType: 'slider',
    ),
    SchemeDefinition(
      id: 'result_to_slider_min',
      label: '结果锁定滑块下限 (result → slider_min)',
      description: '计算结果动态覆盖滑块 min 下限值',
      sourceType: 'math_node',
      targetType: 'slider',
    ),
    SchemeDefinition(
      id: 'threshold_to_indicator',
      label: '多段阈值映射状态灯 (threshold → indicator)',
      description: '根据区间比对切换指示灯发光颜色',
      sourceType: 'math_node',
      targetType: 'indicator',
      params: [
        SchemeParamField(
          key: 'thresholdLower',
          label: '下限阈值 (Min)',
          type: SchemeParamType.doubleVal,
          defaultValue: 30.0,
        ),
        SchemeParamField(
          key: 'thresholdUpper',
          label: '上限阈值 (Max)',
          type: SchemeParamType.doubleVal,
          defaultValue: 80.0,
        ),
        SchemeParamField(
          key: 'colorLower',
          label: '低区间颜色',
          type: SchemeParamType.color,
          defaultValue: 0xFFFF5252,
        ),
        SchemeParamField(
          key: 'colorMid',
          label: '正常区间颜色',
          type: SchemeParamType.color,
          defaultValue: 0xFF69F0AE,
        ),
        SchemeParamField(
          key: 'colorUpper',
          label: '高区间颜色',
          type: SchemeParamType.color,
          defaultValue: 0xFFFFD740,
        ),
      ],
    ),
    SchemeDefinition(
      id: 'bool_result_to_indicator',
      label: '布尔结果控制指示灯 (bool_result → indicator)',
      description: 'true 亮绿灯，false 亮红灯',
      sourceType: 'math_node',
      targetType: 'indicator',
    ),
    SchemeDefinition(
      id: 'bool_result_to_switch',
      label: '布尔结果覆盖开关 (bool_result → switch)',
      description: '计算布尔结果直接驱动 switch 开启/关闭',
      sourceType: 'math_node',
      targetType: 'switch',
    ),
    SchemeDefinition(
      id: 'threshold_to_switch',
      label: '数值比较驱动开关 (threshold → switch)',
      description: '结果与阈值比较，确定开关状态',
      sourceType: 'math_node',
      targetType: 'switch',
      params: [
        SchemeParamField(
          key: 'operator',
          label: '比较逻辑',
          type: SchemeParamType.choice,
          defaultValue: '>',
          options: ['>', '<', '>=', '<=', '=='],
        ),
        SchemeParamField(
          key: 'threshold',
          label: '判定阈值',
          type: SchemeParamType.doubleVal,
          defaultValue: 0.0,
        ),
      ],
    ),
    SchemeDefinition(
      id: 'math_to_button_enable',
      label: '计算门控解锁按钮 (math → button_enable)',
      description: '计算达成条件时，解锁按钮可点击状态',
      sourceType: 'math_node',
      targetType: 'button',
    ),

    // --- switch (布尔开关) ---
    SchemeDefinition(
      id: 'bool_to_indicator',
      label: '开关状态驱动指示灯 (switch → indicator)',
      description: '开关开启时高亮亮起，关闭时熄灭',
      sourceType: 'switch',
      targetType: 'indicator',
    ),
    SchemeDefinition(
      id: 'bool_to_button_enable',
      label: '开关锁定按钮使能 (switch → button_enable)',
      description: '开关为 true 时解锁按钮点击，为 false 时锁定屏蔽',
      sourceType: 'switch',
      targetType: 'button',
    ),
    SchemeDefinition(
      id: 'bool_to_input_enable',
      label: '开关锁定输入框使能 (switch → input_enable)',
      description: '开关为 true 时允许输入，为 false 时禁用输入',
      sourceType: 'switch',
      targetType: 'input',
    ),
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
      id: 'input_to_button_enable',
      label: '校验合格解锁按钮 (input → button_enable)',
      description: '输入框有内容或正则校验通过时解禁按钮',
      sourceType: 'input',
      targetType: 'button',
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
    SchemeDefinition(
      id: 'input_to_math',
      label: '数值流导计算节点 (input → math_node)',
      description: '将输入框的数值作为参数注入计算节点',
      sourceType: 'input',
      targetType: 'math_node',
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
    SchemeDefinition(
      id: 'slider_to_indicator',
      label: '滑块数值档位驱动状态灯 (slider → indicator)',
      description: '滑块数值所在区间控制指示灯颜色',
      sourceType: 'slider',
      targetType: 'indicator',
      params: [
        SchemeParamField(
          key: 'thresholdLower',
          label: '下限阈值',
          type: SchemeParamType.doubleVal,
          defaultValue: 30.0,
        ),
        SchemeParamField(
          key: 'thresholdUpper',
          label: '上限阈值',
          type: SchemeParamType.doubleVal,
          defaultValue: 80.0,
        ),
      ],
    ),
    SchemeDefinition(
      id: 'num_to_math',
      label: '数值流导计算节点 (num → math_node)',
      description: '数值源作为参数注入计算节点',
      sourceType: 'any',
      targetType: 'math_node',
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
      id: 'select_to_math',
      label: '选项数值注入计算 (select → math_node)',
      description: '将选中项的数值作为参数注入计算节点',
      sourceType: 'select',
      targetType: 'math_node',
    ),
    SchemeDefinition(
      id: 'select_to_switch',
      label: '特定选项匹配开启开关 (select → switch)',
      description: '当选中项等于设定值时触发开关开启',
      sourceType: 'select',
      targetType: 'switch',
      params: [
        SchemeParamField(
          key: 'matchValue',
          label: '匹配触发值',
          type: SchemeParamType.text,
          defaultValue: '',
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
    SchemeDefinition(
      id: 'threshold_to_button_enable',
      label: '进度达标解锁按钮 (progress → button_enable)',
      description: '进度条达到设定的阈值时，解禁目标按钮',
      sourceType: 'progress',
      targetType: 'button',
      params: [
        SchemeParamField(
          key: 'threshold',
          label: '解锁达标阈值',
          type: SchemeParamType.doubleVal,
          defaultValue: 100.0,
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
    SchemeDefinition(
      id: 'timer_tick_to_math_trigger',
      label: '定时脉冲唤醒重算 (timer_tick → math_trigger)',
      description: '每到一次定时 Tick，强制触发计算节点重新求值',
      sourceType: 'timer',
      targetType: 'math_node',
      isPulse: true,
    ),
    SchemeDefinition(
      id: 'timer_tick_to_indicator',
      label: '定时脉冲驱动状态灯 (timer_tick → indicator)',
      description: '定时脉冲闪烁或切换指示灯状态',
      sourceType: 'timer',
      targetType: 'indicator',
      isPulse: true,
    ),

    // --- indicator (状态指示点数据源) ---
    SchemeDefinition(
      id: 'indicator_state_to_switch',
      label: '指示灯状态联动开关 (indicator → switch)',
      description: '指示灯亮起时开启开关，熄灭/危险时关闭开关',
      sourceType: 'indicator',
      targetType: 'switch',
    ),
    SchemeDefinition(
      id: 'indicator_state_to_button_enable',
      label: '指示灯正常解禁按钮 (indicator → button_enable)',
      description: '指示灯处于正常绿色状态时解禁按钮触控',
      sourceType: 'indicator',
      targetType: 'button',
    ),

    // --- surface (面原子全样式全能数据源) ---
    SchemeDefinition(
      id: 'color_to_text',
      label: '同步主题着色 (color → text)',
      description: '源组件的主题色同步渲染目标组件文本/背景',
      sourceType: 'surface',
      targetType: 'text',
    ),
    SchemeDefinition(
      id: 'color_to_track',
      label: '同步轨道色 (color → track)',
      description: '源底面颜色同步充当轨道填充色',
      sourceType: 'surface',
      targetType: 'progress',
    ),
    SchemeDefinition(
      id: 'color_to_switch',
      label: '同步开关高亮色 (color → switch)',
      description: '源底面颜色同步充当开关高亮主题色',
      sourceType: 'surface',
      targetType: 'switch',
    ),
    SchemeDefinition(
      id: 'color_to_select',
      label: '同步选框主题色 (color → select)',
      description: '源底面颜色同步充当下拉框选框主题色',
      sourceType: 'surface',
      targetType: 'select',
    ),
    SchemeDefinition(
      id: 'color_to_indicator',
      label: '同步指示灯发光色 (color → indicator)',
      description: '源底面颜色同步充当指示灯发光颜色',
      sourceType: 'surface',
      targetType: 'indicator',
    ),
    SchemeDefinition(
      id: 'surface_to_button_enable',
      label: '区域激活控制按钮 (surface → button_enable)',
      description: '底面区域激活时解锁按钮热区触控',
      sourceType: 'surface',
      targetType: 'button',
    ),
    SchemeDefinition(
      id: 'surface_to_input_enable',
      label: '区域激活控制输入框 (surface → input_enable)',
      description: '底面区域激活时解锁输入框编辑',
      sourceType: 'surface',
      targetType: 'input',
    ),
    SchemeDefinition(
      id: 'surface_to_switch_enable',
      label: '区域激活锁定开关 (surface → switch_enable)',
      description: '底面区域激活时解锁开关触控',
      sourceType: 'surface',
      targetType: 'switch',
    ),
    SchemeDefinition(
      id: 'surface_to_select_enable',
      label: '区域激活锁定选框 (surface → select_enable)',
      description: '底面区域激活时解锁选框下拉',
      sourceType: 'surface',
      targetType: 'select',
    ),
    SchemeDefinition(
      id: 'surface_to_indicator_state',
      label: '区域选中驱动点亮 (surface → indicator_state)',
      description: '底面区域选中时驱动指示灯点亮',
      sourceType: 'surface',
      targetType: 'indicator',
    ),
    SchemeDefinition(
      id: 'name_to_text',
      label: '表头回写 (name → text)',
      description: '源组件标识名称回写为目标文本',
      sourceType: 'surface',
      targetType: 'text',
    ),
    SchemeDefinition(
      id: 'bounds_to_text',
      label: '规格自测打印 (bounds → text)',
      description: '打印源组件宽 x 高物理尺寸字符串',
      sourceType: 'surface',
      targetType: 'text',
    ),
    SchemeDefinition(
      id: 'size_to_max',
      label: '宽度折算上限 (size → max)',
      description: '源组件物理宽度折算为滑块/进度条上限',
      sourceType: 'surface',
      targetType: 'progress',
    ),
    SchemeDefinition(
      id: 'adopt_into_frame',
      label: '📦 移交收容至视窗沙盘 (adopt → scroll_frame)',
      description: '将目标组件打包为滚动视窗内的可滚动子子元素',
      sourceType: 'surface',
      targetType: 'scroll_frame',
    ),
    SchemeDefinition(
      id: 'color_to_viewport',
      label: '同步视窗底板背景 (color → viewport)',
      description: '源底面颜色充当滚动视窗底层衬底',
      sourceType: 'surface',
      targetType: 'scroll_frame',
    ),
    SchemeDefinition(
      id: 'size_to_viewport_content',
      label: '映射长画布尺寸 (size → viewport_content)',
      description: '将源物理尺寸映射为视窗虚拟画布高度',
      sourceType: 'surface',
      targetType: 'scroll_frame',
    ),
    SchemeDefinition(
      id: 'surface_to_surface_expansion',
      label: '🔗 面的扩充与全样式共生 (surface → surface)',
      description: '主底面材质与色彩样式共享给次表面',
      sourceType: 'surface',
      targetType: 'surface',
    ),

    // --- 通用兜底 ---
    SchemeDefinition(
      id: 'current_to_text',
      label: '当前数值转文本 (current → text)',
      description: '将数据源当前数值（如 slider, progress）渲染为文本',
      sourceType: 'any',
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
      id: 'max_to_text',
      label: '上限数值转文本 (max → text)',
      description: '将数据源最大值渲染为文本',
      sourceType: 'any',
      targetType: 'text',
    ),
    SchemeDefinition(
      id: 'num_to_current',
      label: '数值同步 (num → current)',
      description: '源数值直接覆盖目标的 current 属性',
      sourceType: 'any',
      targetType: 'any',
    ),
    SchemeDefinition(
      id: 'str_to_indicator',
      label: '字面量匹配驱动状态灯 (str → indicator)',
      description: '字符串源匹配指定词时亮灯',
      sourceType: 'any',
      targetType: 'indicator',
      params: [
        SchemeParamField(
          key: 'matchString',
          label: '匹配触发字符串',
          type: SchemeParamType.text,
          defaultValue: '正常',
        ),
      ],
    ),
    SchemeDefinition(
      id: 'to_string',
      label: '通用标准字面量流转 (to_string)',
      description: '标准通用兜底转为字符串流转',
      sourceType: 'any',
      targetType: 'any',
    ),
  ];

  /// 根据源端与目标端原语类型，返回合法的 Scheme 方案列表 (已自动过滤黑名单)
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

      if (matchSrc && matchTgt) {
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
