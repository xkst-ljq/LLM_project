/// UIEngine API 字典。
///
/// 目标：让转译 AI 和校验器共用同一份“组件 / mode / linker / 限制”事实源。
/// AI 不需要一次背完整引擎；需要某个组件时，按 key 查询本字典即可。
class UiEngineApiDictionary {
  const UiEngineApiDictionary._();

  static const Map<String, dynamic> modes = {
    'opening': {
      'purpose': '开场白全屏 UI；确认后关闭。',
      'lifecycle': 'conversation_start_only',
      'requiresKeyAction': true,
      'blocksWithoutKeyAction': true,
      'keyActionMeaning': '确认并关闭 opening；可写入 targetBranchIndex 切换开场分支。',
      'coexistsWith': ['scene', 'extra_sticky', 'extra_companion'],
      'recommendedFor': ['开场身份选择', '一次性分支选择', '玩家档案输入'],
      'avoidFor': ['长期状态栏', '每回合正文承载'],
    },
    'scene': {
      'purpose': '全屏接管聊天页，用自定义 UI 承载正文、状态、操作。',
      'lifecycle': 'runtime_takeover',
      'requiresKeyAction': true,
      'blocksWithoutKeyAction': true,
      'keyActionMeaning': '打开聊天设置 / 菜单，不是故事内退出动作。',
      'coexistsWith': ['opening', 'extra_sticky'],
      'suppresses': ['native_message_list', 'native_input_bar', 'extra_companion'],
      'recommendedFor': ['沉浸式终端', '正文被原卡 UI 包裹', '信息量大且需要全屏排布'],
      'coreCompanionComponent': 'message_flow',
    },
    'extra_sticky': {
      'purpose': '常驻悬浮 UI / 工具层。',
      'lifecycle': 'persistent_tool_layer',
      'requiresKeyAction': true,
      'blocksWithoutKeyAction': false,
      'keyActionMeaning': '折叠界面。',
      'coexistsWith': ['opening', 'scene', 'extra_companion'],
      'recommendedFor': ['快捷工具', '轻量状态条', '全局操作按钮'],
    },
    'extra_companion': {
      'purpose': '伴生 UI，嵌入 AI 消息气泡周围。',
      'lifecycle': 'message_bubble_companion',
      'requiresKeyAction': false,
      'blocksWithoutKeyAction': false,
      'maxPcbWidth': 212,
      'coexistsWith': ['opening', 'extra_sticky'],
      'suppressedBy': ['scene'],
      'recommendedFor': ['小型状态栏', '紧凑属性面板', '角色徽章'],
      'avoidFor': ['完整正文承载', '复杂任务板', '大表格'],
    },
  };

  /// 可见组件字典。
  static const Map<String, dynamic> components = {
    'surface': {
      'purpose': '视觉面板 / 背景 / 卡片 / 按钮底板。',
      'runtimeType': 'surface',
      'aliases': ['base_box'],
      'geometry': ['offset', 'size', 'layerIndex', 'rotation'],
      'moduleFields': {
        'material': {'type': 'enumIndex', 'values': ['glass', 'solid', 'gradient', 'outline'], 'default': 'solid'},
        'shape': {'type': 'enumIndex', 'values': ['rectangle', 'rounded', 'capsule', 'circle', 'heart', 'star5', 'star4'], 'default': 'rounded'},
        'color': {'type': 'argbInt', 'description': '主色 / 背景色'},
        'opacity': {'type': 'double', 'range': [0, 1], 'default': 1.0},
        'borderRadius': {'type': 'double', 'range': [0, 999], 'default': 12},
      },
      'properties': {
        'animation': {'type': 'ElementAnimation?', 'description': '可由 event_to_animation / click_to_surface_press 触发'},
      },
      'aiGuidance': ['button 自身透明，通常需要 surface 做可见底板', '可做 PCB 内层纸面、卡片块、装饰底层'],
    },
    'text': {
      'purpose': '标题、标签、字段值、长文说明。',
      'runtimeType': 'text',
      'properties': {
        'text': {'type': 'string', 'default': ''},
        'fontSize': {'type': 'double', 'default': 14, 'range': [10, 72]},
        'overflow': {'type': 'enum', 'values': ['ellipsis', 'clip', 'wrap', 'scroll'], 'default': 'ellipsis'},
        'textAlign': {'type': 'enum', 'values': ['left', 'center', 'right'], 'default': 'center'},
        'richText': {'type': 'bool', 'default': false, 'description': 'scroll 模式默认适合开启；短数值不建议开启'},
        'contentPadding': {'type': 'double', 'default': 10, 'onlyFor': 'overflow=scroll'},
        'dataChannel': {'type': 'DataChannel?', 'description': '可绑定状态字段 / 变量 / 卡片条目'},
      },
      'displayExpression': {'type': 'string?', 'description': '支持 {{current}} / {{max}} 等模板'},
      'aiGuidance': ['长文本、任务板、羁绊名录用 overflow=scroll', '短标签/数值用 ellipsis 且 richText=false', '可作为数据通道显示端'],
      'pitfalls': ['HP<50 这类文本若 richText=true 可能被当成 HTML'],
    },
    'progress': {
      'purpose': '数值进度条 / 圆环 / 特殊形状进度。',
      'runtimeType': 'progress',
      'properties': {
        'min': {'type': 'double', 'default': 0},
        'max': {'type': 'double', 'default': 100},
        'current': {'type': 'double', 'default': 0},
        'trackColor': {'type': 'argbInt', 'default': 0xFFEEEEEE},
        'progressShape': {'type': 'enum', 'values': ['rounded', 'capsule', 'ring', 'heart', 'star5', 'star4'], 'default': 'rounded'},
        'strokeWidth': {'type': 'double?', 'description': 'ring 等形态可用'},
        'dataChannel': {'type': 'DataChannel?'},
      },
      'aiGuidance': ['HP/MP/XP/百分比优先用 progress', '若源是 current/max，max 可取证据里的上限', '不要默认假设 max 运行时会自动变化'],
    },
    'button': {
      'purpose': '透明点击热区；外观依赖背后的 surface/text。',
      'runtimeType': 'button',
      'properties': {
        'keyAction': {'type': 'bool', 'description': 'mode 关键职责'},
        'sendsMessage': {'type': 'bool', 'description': '点击发送 text / 联动文本'},
        'text': {'type': 'string', 'description': '发送消息文本，不负责显示'},
        'targetBranchIndex': {'type': 'int?', 'description': 'opening 分支索引'},
        'doubleTapIntervalMs': {'type': 'int', 'range': [100, 1000]},
        'longPressThresholdMs': {'type': 'int', 'range': [150, 3000]},
      },
      'events': ['tap', 'tap_down', 'double_tap', 'long_press'],
      'aiGuidance': ['选项有 onclick/send 或作者确认可点击时才生成 sendsMessage 按钮', 'scene 设置按钮 = keyAction=true', '按钮视觉需 surface/text'],
    },
    'input': {
      'purpose': '玩家自由文本输入。',
      'runtimeType': 'input',
      'properties': {
        'placeholder': {'type': 'string'},
        'text': {'type': 'string', 'default': ''},
        'value': {'type': 'string', 'default': ''},
        'committedValue': {'type': 'string', 'default': ''},
        'maxLength': {'type': 'int?'},
        'multiline': {'type': 'bool', 'default': false},
        'textVerticalAlign': {'type': 'enum', 'values': ['top', 'center', 'bottom'], 'default': 'center'},
        'textHorizontalAlign': {'type': 'enum', 'values': ['left', 'center', 'right'], 'default': 'left'},
        'visualMode': {'type': 'enum', 'values': ['filled', 'outline', 'transparent'], 'default': 'filled'},
        'placeholderColor': {'type': 'argbInt'},
        'inputTextColor': {'type': 'argbInt'},
        'sendsMessage': {'type': 'bool', 'description': '单行提交时发送'},
        'dataChannel': {'type': 'DataChannel?'},
      },
      'aiGuidance': ['extra_companion 通常不要放 input，因为聊天页已有主输入框', 'scene/opening 中可用 input_prompt 转换为 input'],
    },
    'select': {
      'purpose': '下拉 / 弹出选项选择器。',
      'runtimeType': 'select',
      'properties': {
        'options': {'type': 'List<SelectOption>', 'item': {'label': 'string', 'value': 'string'}},
        'current': {'type': 'string'},
        'defaultValue': {'type': 'string'},
        'expandDirection': {'type': 'enum', 'values': ['up', 'down'], 'default': 'down'},
        'dataChannel': {'type': 'DataChannel?'},
      },
    },
    'switch': {
      'purpose': '布尔开关 / 条件状态。',
      'runtimeType': 'switch',
      'properties': {
        'value': {'type': 'bool', 'default': true},
        'dataChannel': {'type': 'DataChannel?'},
      },
    },
    'slider': {
      'purpose': '玩家可拖动数值控件。',
      'runtimeType': 'slider',
      'properties': {
        'min': {'type': 'double', 'default': 0},
        'max': {'type': 'double', 'default': 100},
        'current': {'type': 'double', 'default': 0},
        'committedValue': {'type': 'double?'},
        'step': {'type': 'double', 'default': 1},
        'trackColor': {'type': 'argbInt'},
        'knobSize': {'type': 'double', 'default': 18, 'range': [10, 48]},
        'knobShape': {'type': 'enum', 'values': ['circle', 'square', 'diamond'], 'default': 'circle'},
        'inactiveTrackColor': {'type': 'argbInt?'},
        'thumbColor': {'type': 'argbInt?'},
        'dataChannel': {'type': 'DataChannel?'},
      },
    },
    'line': {
      'purpose': '分隔线 / 边框线 / 装饰线。',
      'runtimeType': 'line',
      'moduleFields': {'color': {'type': 'argbInt'}},
      'properties': {
        'thickness': {'type': 'double', 'default': 2, 'range': [1, 32]},
        'axis': {'type': 'enum', 'values': ['horizontal', 'vertical'], 'default': 'horizontal'},
        'lineStyle': {'type': 'enum', 'values': ['solid', 'dashed', 'dotted', 'curve', 'double'], 'default': 'solid'},
        'dashLength': {'type': 'double', 'default': 6},
        'gapLength': {'type': 'double', 'default': 3},
      },
      'aiGuidance': ['适合模拟 CSS border / 分区线 / 终端装饰线', '不改变玩法，可作为安全视觉增强'],
    },
    'indicator': {
      'purpose': '状态指示灯 / 警告灯。',
      'runtimeType': 'indicator',
      'properties': {
        'dotSize': {'type': 'double', 'default': 14, 'range': [8, 28]},
        'defaultGlow': {'type': 'bool', 'default': false},
        'defaultColor': {'type': 'argbInt', 'default': 0xFF9E9E9E},
        'currentValue': {'type': 'string?'},
        'statusRules': {'type': 'List<StatusRule>', 'description': '根据文本/布尔/数字条件切换颜色'},
      },
      'pitfalls': ['不要使用不存在的 isOn/onColor 键'],
    },
    'image': {
      'purpose': '图片、头像、内嵌资源。',
      'runtimeType': 'image',
      'properties': {
        'imageSource': {'type': 'enum', 'values': ['custom', 'character_avatar', 'user_avatar'], 'default': 'custom'},
        'url': {'type': 'string'},
        'assetPath': {'type': 'string'},
        'fit': {'type': 'enum', 'values': ['cover', 'contain', 'fill'], 'default': 'cover'},
        'borderRadius': {'type': 'double', 'default': 8},
      },
    },
    'message_flow': {
      'purpose': '在 UI 内显示真实聊天历史 / AI 正文。',
      'runtimeType': 'message_flow',
      'properties': {
        'historyLimit': {'type': 'int', 'default': 0, 'description': '0=显示全部'},
        'showUser': {'type': 'bool', 'default': true},
        'showAssistant': {'type': 'bool', 'default': true},
        'richText': {'type': 'bool', 'default': true},
        'fontSize': {'type': 'double', 'default': 12.5, 'range': [8, 24]},
        'userBubbleColor': {'type': 'argbInt', 'default': 0xFFDCF8C6},
        'assistantBubbleColor': {'type': 'argbInt', 'default': 0xFFF1F1F4},
        'bubbleRadius': {'type': 'double', 'default': 12, 'range': [0, 32]},
      },
      'aiGuidance': ['scene 中承载正文的首选组件', '可放在 surface 上形成终端/档案正文框'],
    },
  };

  static const Map<String, dynamic> logicComponents = {
    'page_router': {
      'purpose': '页面路由器，运行时隐形。',
      'properties': {
        'route': {
          'targetPageId': 'string',
          'action': ['switch_base_page', 'open_overlay', 'close_overlay'],
          'transition': ['base_slide', 'overlay_fade'],
          'durationMs': 'int',
        }
      }
    },
    'linker': {
      'purpose': '联动器，运行时隐形。',
      'properties': {
        'linker': {
          'scheme': 'string',
          'sourceModuleId': 'elementId',
          'targetModuleId': 'elementId',
          'sourcePort': 'string',
          'targetPort': 'string',
          'schemeParams': 'Map<String,dynamic>',
          'enabled': 'bool',
          'priority': 'int',
        }
      }
    },
    'math_node': {
      'purpose': '原生算术 / 逻辑计算节点。',
      'properties': {
        'expression': 'string',
        'paramA': 'number',
        'paramB': 'number',
        'paramC': 'number',
        'lastResult': 'number|string|bool',
      },
    },
    'timer': {
      'purpose': '周期 tick / 倒计时 / 正计时。',
      'properties': {
        'intervalMs': 'int',
        'isRunning': 'bool',
        'currentVal': 'double',
        'tickCount': 'int',
        'maxTicks': 'int',
        'mode': ['loop', 'countUp', 'countDown'],
        'step': 'double',
      },
    },
  };

  static const Map<String, dynamic> semanticRoles = {
    'keyAction': {
      'opening': '确认并关闭 opening；如果有 targetBranchIndex 则切换分支。',
      'scene': '打开聊天设置 / 菜单。',
      'extra_sticky': '折叠界面。',
      'extra_companion': '通常不需要。',
    },
    'sendsMessage': {
      'purpose': 'button/input 触发发送用户消息。',
      'recommendedMode': 'scene',
    },
  };

  static const Map<String, dynamic> dataChannel = {
    'targetKinds': ['local_ui_state', 'session_var', 'status_field', 'card_entry', 'user_profile'],
    'readableTypes': ['input', 'select', 'switch', 'slider', 'progress', 'text'],
    'writableTypes': ['input', 'select', 'switch', 'slider'],
    'policies': {
      'llmReadPolicy': ['none', 'prompt'],
      'llmWritePolicy': ['none', 'suggest_delta', 'suggest_replace'],
      'notifyStyle': ['silent', 'toast', 'status_bar'],
    },
    'statusField': {
      'id': 'stable field id; translator should use sourceKey when available',
      'branchInitialValues': 'Map<branchIndex,value>',
    },
  };

  static const Map<String, dynamic> linkerSchemes = {
    'pageAndMessage': ['button_to_page_route', 'button_to_message_action'],
    'clickControl': [
      'click_to_surface_press',
      'click_to_switch_toggle',
      'click_to_switch_set_true',
      'click_to_switch_set_false',
      'click_to_input_clear',
      'click_to_slider_reset',
      'click_to_timer_toggle',
      'click_to_timer_reset',
      'click_to_math_trigger',
    ],
    'math': ['value_to_math_param', 'result_to_text', 'bool_result_to_text', 'result_to_progress', 'bool_result_to_progress'],
    'visibilityAndControl': ['boolean_to_visible', 'boolean_to_enabled', 'boolean_to_locked', 'boolean_to_frozen', 'boolean_to_timer_running'],
    'input': [
      'input_live_to_text',
      'input_commit_to_text',
      'input_submit_to_text_clear',
      'input_nonempty_to_button_enable',
      'input_valid_to_button_enable',
      'input_validity_to_indicator',
      'input_length_to_indicator',
      'input_value_to_select_match',
      'input_value_to_select_filter',
      'input_to_progress',
      'input_to_slider',
    ],
    'selectionSliderProgress': [
      'slider_to_text',
      'slider_to_progress',
      'slider_commit_to_text',
      'slider_commit_to_math_param',
      'select_to_text',
      'select_value_to_surface_visible',
      'select_value_to_switch',
      'progress_to_text',
      'progress_to_math_param',
      'progress_threshold_to_button_enable',
      'progress_threshold_to_switch',
    ],
    'text': ['text_extract_to_math_param', 'text_match_to_switch', 'text_nonempty_to_button_enable', 'text_match_to_button_enable', 'text_value_to_select_match'],
    'timer': ['timer_tick_to_switch_toggle', 'timer_tick_to_switch_set_true', 'timer_tick_to_switch_set_false', 'timer_tick_to_progress_increment', 'timer_tick_to_progress_decrement', 'timer_tick_to_math_trigger', 'timer_value_to_text'],
    'animationIndicator': ['event_to_animation', 'event_to_indicator', 'indicator_color_to_switch', 'indicator_color_to_text', 'indicator_color_to_enabled', 'indicator_color_to_locked', 'indicator_color_to_frozen', 'indicator_color_to_visible'],
    'aggregate': ['sum_to_display', 'pool_to_allocation'],
    'utility': ['name_to_text', 'to_string'],
  };

  static const Map<String, dynamic> layoutPolicies = {
    'fidelityFirst': '先还原原卡渲染结构、阅读顺序和分组，再因移动端冲突做适配。',
    'avoidSparseTabs': '不要把原本单张长卡机械拆成很多空页；多页必须让每页有足够内容、可滚动大内容区，或作为 overlay 详情。opening 的资料填写和开场方向选择默认应合并成同一张登记卡。',
    'textSizing': '有意义的状态值/任务/物品/选项/位置不能靠 ellipsis；使用 wrap/scroll 并给足高度。wrap 会正常换行，scroll 用于长任务板/羁绊名录。',
    'semanticProximity': '语义关联紧密的信息应尽量放在一起，并使用精确 group 名称而非泛化大类：生存数值同组、任务详情与任务行动同组、正文与当前选项相邻、装备与状态相邻、opening 的设定填写和开场方向选择保持同一登记流程。',
    'reasonableInteraction': '原卡纯文本选项可在作者确认或语义明确时增强为 sendsMessage 按钮；不改变玩法规则。scene 中选项应靠近正文或作为 overlay/sticky 行动坞，不要单独做稀疏 tab。',
    'useOriginalGrid': '原卡有 flex/grid/两列进度条时，应优先保留其布局意图，而不是单列堆叠。',
  };

  static const Map<String, dynamic> layoutPatterns = {
    'opening_then_scene': {
      'useWhen': '一次性开场方向选择 / 简介 / 少量人物信息 + 后续沉浸式正文/状态 UI',
      'assemblies': ['opening', 'scene'],
      'openingShouldChoose': 'opening_greetings branchIndex, not branch-internal DQ_ChoiceBox/quest choices',
    },
    'scene_terminal': {
      'useWhen': '原卡把正文、状态、选项包在一个终端/档案卡里',
      'mustUse': ['layout page role=story/message so compiler inserts message_flow', 'keyAction button'],
    },
    'companion_status': {
      'useWhen': '小型状态栏跟随 AI 消息',
      'mode': 'extra_companion',
      'maxWidth': 212,
    },
    'overlay_detail': {
      'useWhen': '低频详细信息，如档案、任务、好友列表',
      'mechanism': 'UiDesignPlan layout.pages[].type=overlay + parentPage; compiler emits page_router open_overlay buttons',
      'sizing': 'overlay 仍在同一 PCB 内渲染；编译器会按 overlay 内容与 scene 最小高度扩展 PCB，并把 story message_flow 拉伸填充。长内容应使用 overflow=scroll。',
    },
  };

  static const List<String> limitations = [
    '不执行 SillyTavern JS / CSS / hover 伪类。',
    '当前转译编译器还没有 per-message template schema；消息级 UI 可标注为待支持或转为作者确认的持久页。',
    '完整 branchVariants 布局生成仍待扩展；当前优先同布局 + branchInitialValues。',
    '复杂条件样式需 indicator.statusRules 或后续 conditionalStyles schema。',
    '动态 progress max/min 需要额外 API；不要默认假设。',
    'UIEngine runtime 支持 ElementAnimation/event_to_animation，但当前 UiDesignPlan 编译器尚无通用 animations[] schema；只会自动生成按钮按压反馈与页面过渡。',
    'Opening UI 应选择 opening_greetings 分支方向并收集少量人物信息；不要把某个分支内部的 quest/DQ 选择提升成 opening 选择。',
    'quest / DQ_ChoiceBox / FriendsAlbumPage 等稳定消息级 schema，在来源明确或作者确认时可映射为 LLM 可更新的持久字段/页面。',
  ];

  static const Map<String, dynamic> root = {
    'modes': modes,
    'components': components,
    'logicComponents': logicComponents,
    'semanticRoles': semanticRoles,
    'dataChannel': dataChannel,
    'linkerSchemes': linkerSchemes,
    'layoutPolicies': layoutPolicies,
    'layoutPatterns': layoutPatterns,
    'limitations': limitations,
  };

  /// 用点分路径查询，例如 `components.text.properties.overflow`。
  static dynamic lookup(String path) {
    dynamic node = root;
    for (final part in path.split('.')) {
      if (node is Map && node.containsKey(part)) {
        node = node[part];
      } else {
        return null;
      }
    }
    return node;
  }

  static Map<String, dynamic>? component(String type) {
    final direct = components[type];
    if (direct is Map<String, dynamic>) return direct;
    for (final entry in components.entries) {
      final value = entry.value;
      if (value is Map && (value['aliases'] as List? ?? const []).contains(type)) {
        return Map<String, dynamic>.from(value);
      }
    }
    return null;
  }

  static String compactIndexMarkdown() {
    return '''
# UIEngine API Dictionary Index

modes: ${modes.keys.join(', ')}
visible components: ${components.keys.join(', ')}
logic components: ${logicComponents.keys.join(', ')}
semantic roles: ${semanticRoles.keys.join(', ')}
layout policies: ${layoutPolicies.keys.join(', ')}
layout patterns: ${layoutPatterns.keys.join(', ')}
linker groups: ${linkerSchemes.keys.join(', ')}

Use dictionary paths like `components.text`, `components.progress`, `modes.scene`, `layoutPatterns.opening_then_scene` when you need details.
''';
  }

  static String compactReferenceForTranslator() {
    final b = StringBuffer();
    b.writeln(compactIndexMarkdown());
    b.writeln('\n# Mode details');
    modes.forEach((key, value) {
      final v = value as Map;
      b.writeln('- $key: ${v['purpose']} keyAction=${v['keyActionMeaning'] ?? 'none'}');
    });
    b.writeln('\n# Component details');
    for (final key in [
      'surface',
      'text',
      'progress',
      'button',
      'input',
      'select',
      'switch',
      'slider',
      'line',
      'indicator',
      'image',
      'message_flow',
    ]) {
      final c = components[key] as Map;
      b.writeln('## $key');
      b.writeln('- purpose: ${c['purpose']}');
      final props = c['properties'];
      if (props is Map) b.writeln('- properties: ${props.keys.join(', ')}');
      final guidance = c['aiGuidance'];
      if (guidance is List) b.writeln('- aiGuidance: ${guidance.join(' / ')}');
      final pitfalls = c['pitfalls'];
      if (pitfalls is List) b.writeln('- pitfalls: ${pitfalls.join(' / ')}');
    }
    b.writeln('\n# Layout policies');
    layoutPolicies.forEach((key, value) => b.writeln('- $key: $value'));
    b.writeln('\n# Logic details');
    logicComponents.forEach((key, value) {
      final v = value as Map;
      b.writeln('- $key: ${v['purpose']}');
    });
    b.writeln('\n# Linker scheme groups');
    linkerSchemes.forEach((key, value) {
      b.writeln('- $key: ${(value as List).join(', ')}');
    });
    b.writeln('\n# Limitations');
    for (final item in limitations) b.writeln('- $item');
    return b.toString();
  }
}
