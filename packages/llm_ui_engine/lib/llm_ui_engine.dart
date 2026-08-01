/// LLM Project UI 引擎。
///
/// ## 这个包是什么
///
/// 把「组件模型 + 联动器 + 数据通道 + 运行时渲染」从主项目抽出来，
/// 让主应用与 PC 端转译工具（`ToolofPC/llm_card_converter`）
/// **共用同一份源码**。
///
/// ## 为什么要抽包，而不是让工具直接 path 依赖主项目
///
/// 两个实测到的阻碍：
///
/// 1. **依赖冲突**：主项目与工具的 `desktop_drop` 版本区间无交集
///    （`^0.5.0` vs `^0.7.1`）；
/// 2. **无关依赖**：path 指向整个主项目会把 `sqflite` / `image_picker`
///    等一并拉进工具，而渲染闭包**只需要 3 个第三方包**
///    （`flutter_markdown` / `markdown` / `flutter_html`），
///    多余的包在 Windows 桌面端还可能没有实现。
///
/// ## 为什么不复制一份源码过去
///
/// 本项目栽过最多次的坑是「静默失效」：两份拷贝一旦漂移，
/// 工具按旧规则生成、引擎按新规则读，**不报错、只是不生效**
/// （见 `ASSEMBLY_HANDOFF.md` 3.5j）。同一份源码则不存在漂移。
///
/// ## 边界
///
/// 只装**渲染运行时**需要的东西。以下**不在**本包内：
///
/// - `ui_asset_service.dart`（编辑器资产库，与应用层耦合）
/// - Assembly 编辑器本身（`character_assembly_page`）
/// - 数据库 / 聊天页 / 路由等应用层代码
library;

// ===== 模型 =====
export 'src/models/card_entry_target.dart';
export 'src/models/character_entry.dart';
export 'src/models/session_state.dart';
export 'src/models/status_bar_field.dart';
export 'src/models/text_highlight_rule.dart';
export 'src/models/ui_assembly_info.dart';

// ===== 引擎 =====
export 'src/engine/assembly_rich_text.dart';
export 'src/engine/avatar_scope.dart';
export 'src/engine/data_channel_service.dart';
export 'src/engine/element_animation.dart';
export 'src/engine/linker_event_bus.dart';
export 'src/engine/linker_matrix_engine.dart';
export 'src/engine/linker_service.dart';
export 'src/engine/math_node_engine.dart';
export 'src/engine/message_action.dart';
export 'src/engine/message_flow_scope.dart';
export 'src/engine/ripple_shader.dart';
export 'src/engine/select_option.dart';
export 'src/engine/text_highlight_engine.dart';
export 'src/engine/text_highlight_scope.dart';
export 'src/engine/text_value_extractor.dart';
export 'src/engine/ui_models.dart';
export 'src/engine/ui_renderer.dart';
export 'src/engine/ui_semantic_role.dart';

// ===== 运行时视图 =====
export 'src/widgets/ui_assembly_runtime_view.dart';
