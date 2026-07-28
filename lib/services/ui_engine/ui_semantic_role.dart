import 'ui_models.dart';

/// 组件的语义角色。
///
/// 作者在 Assembly 里给普通组件（通常是 button）打上标记，
/// 声明「这个组件在运行时承担什么职责」，运行时据此绑定行为。
///
/// 设计原则（与 `is_overlay_container` 一脉相承）：
///   - 不新增专用组件类型。作者用通用 button 表达意图，
///     外观完全由作者决定，引擎只负责识别职责。
///   - 标记存在 `module.properties['semanticRole']`，随实例保存，
///     不回写资产库模板。
///   - 各 mode 只认自己需要的角色，不认识的角色安全忽略。
class UISemanticRole {
  /// 无角色（默认）。
  static const String none = 'none';

  /// 关闭 / 收起当前 UI。
  ///
  /// - extra_sticky：折叠成悬浮球
  /// - opening：确认并销毁开场白
  /// - scene：退出场景，回到普通聊天
  static const String dismiss = 'dismiss';

  /// 确认并提交。opening 专用，语义上比 dismiss 更明确。
  /// 未来可扩展为「提交前先做校验」。
  static const String confirm = 'confirm';

  /// 拖动把手：按住它可以移动整个挂件。
  ///
  /// **尚未接入运行时**，暂不开放给作者选择（不在 [all] 里）。
  /// 原因：挂件的拖动目前由内置把手的 `_EagerPanRecognizer` 实现，
  /// 要让任意作者组件承担这个职责，需要把拖动手势下沉到渲染层，
  /// 并解决与内部 slider 的手势竞争——那是独立的一步。
  /// 提前定义常量是为了让 `findElementId` 等 API 结构完整。
  static const String dragHandle = 'drag_handle';

  /// 全部可选角色，供编辑器下拉使用。
  ///
  /// 只列已经接入运行时的角色——列出但不生效会让作者以为标了就有用。
  static const List<String> all = [none, dismiss, confirm];

  /// 编辑器里显示的名称。
  static String labelOf(String role) {
    switch (role) {
      case dismiss:
        return '关闭 / 收起';
      case confirm:
        return '确认并关闭';
      case dragHandle:
        return '拖动把手';
      default:
        return '无（普通组件）';
    }
  }

  /// 编辑器里显示的说明，讲清楚它在各 mode 下的实际效果。
  static String hintOf(String role) {
    switch (role) {
      case dismiss:
        return '常驻 UI 折叠为悬浮球；开场白关闭；场景 UI 退出。';
      case confirm:
        return '开场白确认并销毁。用在其他模式时等同于「关闭」。';
      case dragHandle:
        return '按住它可拖动整个界面。适合放一个小图标或标题条。';
      default:
        return '不绑定任何运行时行为。';
    }
  }

  /// 读取组件的语义角色；未标记或值非法时返回 [none]。
  static String of(UIModule? module) {
    final raw = module?.properties['semanticRole']?.toString();
    if (raw == null) return none;
    return all.contains(raw) ? raw : none;
  }

  /// 该组件是否承担某个角色。
  static bool isRole(UIModule? module, String role) => of(module) == role;

  /// 是否是「点击后关闭」类角色（dismiss 与 confirm 都算）。
  ///
  /// 两者的差别只在语义与后续扩展，运行时的收起行为一致。
  static bool closesUI(UIModule? module) {
    final role = of(module);
    return role == dismiss || role == confirm;
  }

  /// 在元素树中查找第一个具有指定角色的元素 id（含复合组件内部）。
  ///
  /// 返回 null 表示作者没有标记该角色，调用方应回退到默认行为
  /// （例如内置的关闭按钮），不能让用户失去唯一的操作入口。
  static String? findElementId(List<UIElement> elements, String role) {
    for (final node in elements) {
      if (isRole(node.module, role)) return node.id;
      if (node.isComposite && node.composite != null) {
        final inner = findElementId(node.composite!.children, role);
        if (inner != null) return inner;
      }
    }
    return null;
  }

  /// 元素树中是否存在该角色。
  static bool hasRole(List<UIElement> elements, String role) =>
      findElementId(elements, role) != null;
}
