import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/session_state.dart';
import '../models/status_bar_field.dart';
import '../models/ui_assembly_info.dart';
import '../services/ui_engine/data_channel_service.dart';
import '../services/ui_engine/linker_event_bus.dart';
import '../services/ui_engine/linker_matrix_engine.dart';
import '../services/ui_engine/linker_service.dart';
import '../models/text_highlight_rule.dart';
import '../services/ui_engine/avatar_scope.dart';
import '../services/ui_engine/message_action.dart';
import '../services/ui_engine/message_flow_scope.dart';
import '../services/ui_engine/text_highlight_scope.dart';
import '../services/ui_engine/ui_semantic_role.dart';
import '../services/ui_engine/ui_models.dart';
import '../services/ui_engine/ui_renderer.dart';

/// Runtime-style renderer for an Assembly UI.
///
/// Design coordinates are pcbWidth × pcbHeight (per-assembly, see
/// [UIAssemblyInfo.defaultPcbSizeFor]). The runtime viewport never
/// stretches PCB non-uniformly and never upscales above 1:1: it uses a single
/// scale-down contain scale, centers the PCB, and optionally fills letterbox
/// space with a blurred cover-scaled copy.
class UIAssemblyRuntimeView extends StatefulWidget {
  /// 兜底基准宽度。实际尺寸取自 `assemblyInfo.pcbWidth`——
  /// 常驻 / 伴生这类挂件宽度可调，不能再假设固定 360。
  static const double designWidth = UIAssemblyInfo.defaultPcbWidth;

  final UIAssemblyInfo assemblyInfo;
  final String? activePageId;
  final bool showBlurredBackdrop;
  final bool showDebugInfo;
  final double blurSigma;

  /// A9.6-2：UI 交互写入的会话副本。
  ///
  /// 传入时，配置了数据通道的输入原子（input / select / switch / slider）
  /// 会在每次交互后把当前值写进 `vars` / `statusValues`。
  /// 不传则运行时完全不触碰会话状态（Assembly 预览默认使用本地临时副本）。
  final SessionState? sessionState;

  /// 会话副本的版本号。
  ///
  /// **不能只靠 `identical` 判断 SessionState 有没有变**：
  /// 聊天页是原地改 `_sessionState.statusValues[...]`，对象始终是同一个，
  /// `identical` 恒为 true，反向同步永远不触发——
  /// 表现就是「Prompt 里数值已经变了，但组件纹丝不动」。
  /// 每次写入后让调用方把这个数 +1，即可强制刷新。
  final int sessionVersion;

  /// 角色卡状态栏字段定义，用于数值字段 clamp。
  final List<StatusBarField> statusFields;

  /// 会话副本发生变化时回调，供上层落盘。
  final ValueChanged<SessionState>? onSessionStateChanged;

  /// 显示数据通道写入的调试浮层（仅 Assembly 预览用）。
  final bool showDataChannelDebug;

  /// 作者标记为「发送消息」的组件触发时回调。
  ///
  /// scene 禁用了原生输入框，玩家只能通过这些组件与 LLM 对话。
  final ValueChanged<String>? onSendMessage;

  /// 角色卡的正则着色规则。null 表示用内置默认。
  final List<TextHighlightRule>? highlightRules;

  /// 作者通过 `button_to_message_action` 方案触发消息操作时回调。
  final ValueChanged<MessageAction>? onMessageAction;

  /// 角色头像本地路径，供 image 组件的「头像同步」来源使用。
  final String characterAvatar;

  /// 用户头像本地路径。
  final String userAvatar;

  /// 这些消息是否来自真实对话。
  ///
  /// 编辑器的运行时预览不传（false），消息流会显示示例对话——
  /// 预览一块空白无从判断排版效果。
  final bool liveMessages;

  /// 供消息流组件显示的对话历史。
  ///
  /// 不塞进 `module.properties`：消息是会话数据而非组件配置，
  /// 写进去会被 `_persistAssemblyElements` 一并存进角色卡。
  final List<FlowMessage> messages;

  /// 作者标记为「关闭 / 确认」的组件被点击时回调。
  ///
  /// 由挂载方决定关闭意味着什么：常驻 UI 折叠成球、开场白销毁、场景退出。
  /// 未提供时该标记不产生行为，作者的按钮仍可正常参与 linker 等其他配置。
  final VoidCallback? onDismissRequested;

  /// 是否启用整页滑动手势（切换平级页 / 打开叠加页 / 点空白关闭 overlay）。
  ///
  /// 常驻 / 伴生这类挂件不该吃掉滑动手势：
  ///   - 它覆盖在聊天内容上，会挡住内部 slider 的拖动；
  ///   - 挂件通常只有一页，页面切换没有意义。
  final bool enablePageGestures;

  const UIAssemblyRuntimeView({
    super.key,
    required this.assemblyInfo,
    this.activePageId,
    this.showBlurredBackdrop = true,
    this.showDebugInfo = false,
    this.blurSigma = 16.0,
    this.sessionState,
    this.sessionVersion = 0,
    this.statusFields = const <StatusBarField>[],
    this.onSessionStateChanged,
    this.showDataChannelDebug = false,
    this.enablePageGestures = true,
    this.onDismissRequested,
    this.messages = const <FlowMessage>[],
    this.liveMessages = false,
    this.onSendMessage,
    this.highlightRules,
    this.onMessageAction,
    this.characterAvatar = '',
    this.userAvatar = '',
  });

  @override
  State<UIAssemblyRuntimeView> createState() => _UIAssemblyRuntimeViewState();
}

class _UIAssemblyRuntimeViewState extends State<UIAssemblyRuntimeView> {
  static const double _swipeThreshold = 72.0;
  static const double _directionDominance = 1.3;

  late List<AssemblyPage> _pages;
  late String _activePageId;
  late SessionState _session;
  List<String> _lastChannelDebug = const <String>[];
  Timer? _channelPollTimer;
  StreamSubscription<LinkerPulseEvent>? _roleSubscription;
  Offset? _swipeStart;
  String _lastTransition = 'base_slide';
  String _lastSwipeDirection = 'swipe_left';
  int _lastDurationMs = 220;

  @override
  void initState() {
    super.initState();
    _restoreRuntimeState();
    // 先用会话副本填充组件，再建立联动与轮询，
    // 保证首帧显示的就是真实状态而不是模板默认值。
    _applySessionToUI();
    _setupRuntimeLinkers();
    _startChannelPolling();
  }

  /// 组件内部（滑块拖动 / 输入 / 开关）直接改写 `module.properties`，
  /// 并不一定发出 LinkerEventBus 事件，因此仅靠事件回调会漏掉这些变化。
  /// 这里用低频轮询兜底，保证会话副本与调试浮层能跟随交互实时更新。
  void _startChannelPolling() {
    _channelPollTimer?.cancel();
    if (widget.sessionState == null && !widget.showDataChannelDebug) return;
    _channelPollTimer = Timer.periodic(
      const Duration(milliseconds: 300),
      (_) {
        if (!mounted) return;
        final before = _lastChannelDebug;
        _syncDataChannels();
        if (!_sameDebug(before, _lastChannelDebug)) {
          setState(() {});
        }
      },
    );
  }

  bool _sameDebug(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  void didUpdateWidget(covariant UIAssemblyRuntimeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assemblyInfo.toJsonString() != widget.assemblyInfo.toJsonString() ||
        oldWidget.activePageId != widget.activePageId) {
      _restoreRuntimeState();
      _applySessionToUI();
      _setupRuntimeLinkers();
      _startChannelPolling();
      return;
    }

    // 外部会话副本被替换（如 LLM 更新状态、撤回回滚）时刷新界面显示。
    // 这是反向同步的主要触发点：状态变了，UI 要跟着变。
    final incoming = widget.sessionState;
    if (incoming != null &&
        (!identical(incoming, _session) ||
            oldWidget.sessionVersion != widget.sessionVersion)) {
      _session = incoming;
      if (_applySessionToUI() && mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _channelPollTimer?.cancel();
    _roleSubscription?.cancel();
    LinkerService.initEventBusListener(const <UIElement>[], () {});
    super.dispose();
  }

  void _restoreRuntimeState() {
    _pages = _clonePages(_restorePages(widget.assemblyInfo));
    _activePageId = _resolveActivePage(_pages, widget.activePageId).id;
    // 未接入外部会话时使用本地临时副本，保证预览里通道逻辑同样可验证，
    // 但不会污染真实角色卡会话状态。
    _session = widget.sessionState ?? SessionState();
  }

  void _setupRuntimeLinkers() {
    final activePage = _resolveActivePage(_pages, _activePageId);
    LinkerService.initEventBusListener(activePage.elements, () {
      if (!mounted) return;
      _syncDataChannels();
      setState(() {});
    });
    _syncDataChannels();
    _setupSemanticRoleListener();
  }

  /// 监听语义标记组件的事件。
  ///
  /// 直接复用组件已有的脉冲（button 的 `tap`、input 的 `committedValue`），
  /// 不改渲染器——这样被标记的组件仍可正常参与 linker 等既有配置。
  void _setupSemanticRoleListener() {
    _roleSubscription?.cancel();
    if (widget.onDismissRequested == null &&
        widget.onSendMessage == null &&
        widget.onMessageAction == null) {
      return;
    }

    _roleSubscription = LinkerEventBus().onPulse.listen((event) {
      if (!mounted) return;
      final activePage = _resolveActivePage(_pages, _activePageId);
      final module =
          _findModuleById(activePage.elements, event.sourceModuleId);
      if (module == null) return;

      // 关键职责：点击触发（关闭 / 确认 / 打开设置）。
      if (event.eventType == 'tap' && UISemanticRole.isKeyAction(module)) {
        widget.onDismissRequested?.call();
      }

      // 消息操作：button 通过 linker 连到 message_flow。
      //
      // 走 linker 而不是语义标记，是因为它需要携带参数（执行哪个动作）。
      // 语义标记是「是 / 否」的单一职责，表达不了六种动作的选择。
      if (event.eventType == 'tap' && widget.onMessageAction != null) {
        final action = _resolveMessageAction(
          event.sourceModuleId,
          activePage.elements,
        );
        if (action != null) widget.onMessageAction!(action);
      }

      // 发送消息：button 点击，或 input 回车提交。
      if (UISemanticRole.sendsMessage(module)) {
        // input 回车提交时发的是 input_commit，payload 即提交内容。
        final isSubmit = event.eventType == 'input_commit';
        if (event.eventType == 'tap' || isSubmit) {
          final text = isSubmit
              ? (event.payload?.toString() ?? '')
              : _resolveSendText(module, activePage.elements);
          if (text.trim().isNotEmpty) {
            widget.onSendMessage?.call(text);
            // 发送后清空输入框，避免玩家重复提交同一句。
            if (module.type == 'input') {
              module.properties['text'] = '';
              module.properties['value'] = '';
              module.properties['committedValue'] = '';
              setState(() {});
            }
          }
        }
      }
    });
  }

  /// 查找该 button 通过 `button_to_message_action` 方案配置的消息操作。
  ///
  /// 直接读 linker 节点而不是走 `LinkerService`：后者的输出通道面向
  /// 「把值写进目标组件」，而消息操作要调的是聊天页的方法，
  /// 不落在任何组件属性上。
  MessageAction? _resolveMessageAction(
    String sourceElementId,
    List<UIElement> elements,
  ) {
    for (final linker in _collectLinkers(elements)) {
      final data =
          (linker.properties['linker'] as Map?)?.cast<String, dynamic>();
      if (data == null || data['enabled'] == false) continue;
      if (data['scheme']?.toString() != 'button_to_message_action') continue;
      if (data['sourceModuleId']?.toString() != sourceElementId) continue;

      final params =
          (data['schemeParams'] as Map?)?.cast<String, dynamic>() ?? const {};
      final raw = params['action']?.toString();
      if (raw == null || raw.isEmpty) {
        // 参数缺失 ≠ 参数非法：老数据或跳过配置时回落到方案声明的默认动作，
        // 否则按钮会完全没反应，作者只会以为连线坏了。
        final def =
            LinkerMatrixEngine.getSchemeDefinition('button_to_message_action');
        final fallback = def?.params
            .firstWhere((p) => p.key == 'action')
            .defaultValue
            ?.toString();
        return MessageAction.fromKey(fallback);
      }
      // 值本身认不出来才返回 null——静默执行别的动作更危险。
      return MessageAction.fromKey(raw);
    }
    return null;
  }

  /// 收集元素树里的全部 linker 节点（含复合组件内部）。
  List<UIModule> _collectLinkers(List<UIElement> elements) {
    final out = <UIModule>[];
    for (final node in elements) {
      final module = node.module;
      if (module != null && module.type == 'linker') out.add(module);
      if (node.isComposite && node.composite != null) {
        out.addAll(_collectLinkers(node.composite!.children));
      }
    }
    return out;
  }

  /// 取出该组件要发送的文本。
  ///
  /// input 用自己的内容；button 则取它通过 linker 指向的文本源
  /// （选项式剧情：按钮上写「向左走」，点击就发送这句）。
  String _resolveSendText(UIModule module, List<UIElement> elements) {
    if (module.type == 'input') {
      return (module.properties['committedValue'] ??
              module.properties['text'] ??
              '')
          .toString();
    }
    // button：优先用 linker 联动到的值，否则用按钮自身文字。
    final linked = LinkerService.resolveTargetValue(module);
    if (linked != null && linked.toString().trim().isNotEmpty) {
      return linked.toString();
    }
    return (module.properties['text'] ?? module.name).toString();
  }

  UIModule? _findModuleById(List<UIElement> elements, String id) {
    for (final node in elements) {
      if (node.id == id) return node.module;
      if (node.isComposite && node.composite != null) {
        final inner = _findModuleById(node.composite!.children, id);
        if (inner != null) return inner;
      }
    }
    return null;
  }

  /// 收集当前页的暴露项通道覆写（复合组件用）。
  Map<String, Map<String, dynamic>> _overrideChannelsOf(AssemblyPage page) {
    final out = <String, Map<String, dynamic>>{};
    for (final override in page.propertyOverrides) {
      final raw = override.overrides['dataChannel'];
      if (raw is Map) {
        out[override.componentId] = Map<String, dynamic>.from(raw);
      }
    }
    return out;
  }

  /// A9.6-2：把当前页配置了数据通道的输入原子的值同步进会话副本。
  ///
  /// 单向 UI → SessionState。反向回填见 [_applySessionToUI]。
  void _syncDataChannels() {
    final activePage = _resolveActivePage(_pages, _activePageId);
    final overrideChannels = _overrideChannelsOf(activePage);

    final writes = DataChannelService.collectWrites(
      activePage.elements,
      overrideChannels: overrideChannels,
    );
    _lastChannelDebug = DataChannelService.describeWrites(writes);

    final changed = DataChannelService.applyWrites(
      _session,
      writes,
      statusFields: widget.statusFields,
    );
    if (changed) {
      widget.onSessionStateChanged?.call(_session);
    }
  }

  /// 反向同步：SessionState → UI 组件。
  ///
  /// 用于 LLM 更新状态、或状态被外部改动后刷新界面显示。
  /// 返回 true 表示有组件被更新。
  bool _applySessionToUI() {
    final activePage = _resolveActivePage(_pages, _activePageId);
    return DataChannelService.applySessionToElements(
      activePage.elements,
      _session,
      overrideChannels: _overrideChannelsOf(activePage),
    );
  }

  String _defaultTransitionForAction(String action) {
    return action == 'open_overlay' ? 'overlay_fade' : 'base_slide';
  }

  int _defaultDurationForAction(String action) {
    return action == 'open_overlay' ? 180 : 220;
  }

  void _handlePreviewPointerDown(Offset position, Rect pcbRect) {
    if (widget.assemblyInfo.mode == 'opening') return;
    if (!pcbRect.contains(position)) return;
    _swipeStart = position;
  }

  void _handlePreviewPointerUp(
    Offset position,
    Rect pcbRect,
    double scale,
  ) {
    if (widget.assemblyInfo.mode == 'opening') return;
    final start = _swipeStart;
    _swipeStart = null;
    if (start == null) return;

    final delta = position - start;
    final absDx = delta.dx.abs();
    final absDy = delta.dy.abs();
    final activePage = _resolveActivePage(_pages, _activePageId);

    if (activePage.isOverlay && absDx < 12 && absDy < 12) {
      _handleOverlayTap(position, pcbRect, scale, activePage);
      return;
    }

    String? direction;
    if (absDx >= _swipeThreshold && absDx > absDy * _directionDominance) {
      direction = delta.dx < 0 ? 'swipe_left' : 'swipe_right';
    } else if (absDy >= _swipeThreshold && absDy > absDx * _directionDominance) {
      direction = delta.dy < 0 ? 'swipe_up' : 'swipe_down';
    }
    if (direction == null) return;

    AssemblyPageGesture? matched;
    for (final gesture in activePage.gestures) {
      if (gesture.direction == direction) {
        matched = gesture;
        break;
      }
    }
    if (matched == null || matched.targetPageId.isEmpty) return;
    final gesture = matched;
    final swipeDirection = direction;

    final target = _pageById(_pages, gesture.targetPageId);
    if (target == null) return;

    setState(() {
      _lastSwipeDirection = swipeDirection;
      _lastTransition = gesture.transition.isNotEmpty
          ? gesture.transition
          : _defaultTransitionForAction(gesture.action);
      _lastDurationMs = gesture.durationMs > 0
          ? gesture.durationMs
          : _defaultDurationForAction(gesture.action);
      _activePageId = target.id;
    });
    _setupRuntimeLinkers();
  }

  void _handleOverlayTap(
    Offset position,
    Rect pcbRect,
    double scale,
    AssemblyPage activePage,
  ) {
    if (scale <= 0 || !pcbRect.contains(position)) return;
    final designPoint = Offset(
      (position.dx - pcbRect.left) / scale,
      (position.dy - pcbRect.top) / scale,
    );
    final container = _overlayContainerOf(activePage);
    if (container != null) {
      final rect = container.offset & container.size;
      if (rect.contains(designPoint)) return;
    }

    final parentId = activePage.parentPageId;
    if (parentId == null || parentId.isEmpty) return;
    final parent = _pageById(_pages, parentId);
    if (parent == null) return;

    setState(() {
      _lastTransition = 'overlay_fade';
      _lastDurationMs = _defaultDurationForAction('open_overlay');
      _activePageId = parent.id;
    });
    _setupRuntimeLinkers();
  }

  UIElement? _overlayContainerOf(AssemblyPage page) {
    for (final element in page.elements) {
      if (!element.isComposite &&
          element.module?.properties['is_overlay_container'] == true) {
        return element;
      }
    }
    for (final element in page.elements) {
      if (!element.isComposite && _isSurfaceModule(element.module)) {
        return element;
      }
    }
    return null;
  }

  bool _isSurfaceModule(UIModule? module) {
    final type = module?.type;
    return type == 'surface' ||
        type == 'surface_art' ||
        type == 'primitive_art' ||
        type == 'base_box';
  }

  Widget _buildRouteTransition(Widget child, Animation<double> animation) {
    if (_lastTransition == 'overlay_fade') {
      // Overlay 专属动画需要容器面 / 遮罩 / 点击空白关闭语义。
      // 当前只切换目标页，避免把 overlay 当成平级页整页替换动画。
      return child;
    }

    Offset begin;
    switch (_lastSwipeDirection) {
      case 'swipe_right':
        begin = const Offset(-1, 0);
        break;
      case 'swipe_up':
        begin = const Offset(0, 1);
        break;
      case 'swipe_down':
        begin = const Offset(0, -1);
        break;
      default:
        begin = const Offset(1, 0);
    }
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(begin: begin, end: Offset.zero).animate(curved),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activePage = _resolveActivePage(_pages, _activePageId);
    final ancestors = _ancestorPagesFor(_pages, activePage);
    final backgroundPages = _clonePages(_pages);
    final backgroundActivePage = _resolveActivePage(backgroundPages, _activePageId);
    final backgroundAncestors = _ancestorPagesFor(
      backgroundPages,
      backgroundActivePage,
    );
    final designHeight = widget.assemblyInfo.pcbHeight
        .clamp(UIAssemblyInfo.minPcbHeight, UIAssemblyInfo.maxPcbHeight)
        .toDouble();
    final designWidth = widget.assemblyInfo.pcbWidth
        .clamp(UIAssemblyInfo.minPcbWidth,
            UIAssemblyInfo.maxPcbWidthFor(widget.assemblyInfo.mode))
        .toDouble();
    final designSize = Size(designWidth, designHeight);

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : designSize.width;
        final availableHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : designSize.height;

        final rawContainScale = math.min(
          availableWidth / designSize.width,
          availableHeight / designSize.height,
        );
        final safeContainScale = rawContainScale.isFinite && rawContainScale > 0
            ? math.min(1.0, rawContainScale)
            : 1.0;
        final renderedWidth = designSize.width * safeContainScale;
        final renderedHeight = designSize.height * safeContainScale;
        final pcbRect = Rect.fromLTWH(
          (availableWidth - renderedWidth) / 2,
          (availableHeight - renderedHeight) / 2,
          renderedWidth,
          renderedHeight,
        );

        return ClipRect(
          child: Stack(
            children: [
              if (widget.showBlurredBackdrop)
                Positioned.fill(
                  child: IgnorePointer(
                    child: _buildFittedDesignSurface(
                      context,
                      pages: backgroundPages,
                      activePage: backgroundActivePage,
                      ancestors: backgroundAncestors,
                      designSize: designSize,
                      fit: BoxFit.cover,
                      blur: true,
                      opacity: 0.48,
                    ),
                  ),
                ),
              Positioned.fill(
                child: Listener(
                  // 不启用页面手势时用 deferToChild：
                  // translucent 会让这层持续参与命中测试，
                  // 从而抢走内部 slider / 输入框的拖动手势。
                  behavior: widget.enablePageGestures
                      ? HitTestBehavior.translucent
                      : HitTestBehavior.deferToChild,
                  onPointerDown: widget.enablePageGestures
                      ? (event) => _handlePreviewPointerDown(
                          event.localPosition, pcbRect)
                      : null,
                  onPointerUp: (event) {
                    if (widget.enablePageGestures) {
                      _handlePreviewPointerUp(
                        event.localPosition,
                        pcbRect,
                        safeContainScale,
                      );
                    }
                    // 抬手即同步一次，避免等到下一个轮询周期才更新。
                    if (!mounted) return;
                    final before = _lastChannelDebug;
                    _syncDataChannels();
                    if (!_sameDebug(before, _lastChannelDebug)) {
                      setState(() {});
                    }
                  },
                  onPointerCancel: (_) => _swipeStart = null,
                  child: AnimatedSwitcher(
                    duration: Duration(milliseconds: _lastDurationMs),
                    transitionBuilder: _buildRouteTransition,
                    child: KeyedSubtree(
                      key: ValueKey(_activePageId),
                      child: _buildFittedDesignSurface(
                        context,
                        pages: _pages,
                        activePage: activePage,
                        ancestors: ancestors,
                        designSize: designSize,
                        fit: BoxFit.scaleDown,
                        blur: false,
                      ),
                    ),
                  ),
                ),
              ),
              if (widget.showDataChannelDebug && _lastChannelDebug.isNotEmpty)
                Positioned(
                  left: 8,
                  right: 8,
                  top: 8,
                  child: _buildDataChannelDebug(),
                ),
              if (widget.showDebugInfo)
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 8,
                  child: _buildDebugInfo(
                    scale: safeContainScale,
                    renderedWidth: renderedWidth,
                    renderedHeight: renderedHeight,
                    designWidth: designWidth,
                    designHeight: designHeight,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFittedDesignSurface(
    BuildContext context, {
    required List<AssemblyPage> pages,
    required AssemblyPage activePage,
    required List<AssemblyPage> ancestors,
    required Size designSize,
    required BoxFit fit,
    required bool blur,
    double opacity = 1.0,
  }) {
    Widget child = ClipRect(
      child: FittedBox(
        fit: fit,
        alignment: Alignment.center,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: designSize.width,
          height: designSize.height,
          child: _buildDesignSurface(
            context,
            pages: pages,
            activePage: activePage,
            ancestors: ancestors,
            designSize: designSize,
          ),
        ),
      ),
    );

    if (blur) {
      child = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(
          sigmaX: widget.blurSigma,
          sigmaY: widget.blurSigma,
        ),
        child: Opacity(opacity: opacity, child: child),
      );
      child = Stack(
        fit: StackFit.expand,
        children: [
          child,
          Container(color: Colors.black.withValues(alpha: 0.12)),
        ],
      );
    }

    return child;
  }

  Widget _buildDesignSurface(
    BuildContext context, {
    required List<AssemblyPage> pages,
    required AssemblyPage activePage,
    required List<AssemblyPage> ancestors,
    required Size designSize,
  }) {
    final elementsForSnapshot = <UIElement>[
      ...ancestors.expand((page) => page.elements),
      ...activePage.elements,
    ];
    final snapshot = LinkerSnapshot.fromElements(elementsForSnapshot);
    final borderRadius =
        BorderRadius.circular(widget.assemblyInfo.pcbRadius);

    return MessageFlowScope(
      messages: widget.messages,
      // 只有真实聊天页会传 liveMessages；编辑器预览不传，
      // 消息流据此显示示例对话而不是「暂无消息」。
      isLive: widget.liveMessages,
      child: AvatarScope(
      characterAvatar: widget.characterAvatar,
      userAvatar: widget.userAvatar,
      child: TextHighlightScope(
      rules: widget.highlightRules ?? TextHighlightRule.defaults(),
      child: UILinkerSnapshotScope(
      snapshot: snapshot,
      child: UISceneModeScope(
        isStudioCreationMode: false,
        child: ClipRRect(
          borderRadius: borderRadius,
          child: Container(
            width: designSize.width,
            height: designSize.height,
            decoration: BoxDecoration(
              color: Color(widget.assemblyInfo.pcbColorValue),
              borderRadius: borderRadius,
            ),
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                ...ancestors.expand((page) {
                  return page.elements.map(
                    (element) => _buildRuntimeElement(
                      context,
                      element,
                      overrides: page.propertyOverrides,
                      opacity: 0.35,
                    ),
                  );
                }),
                if (activePage.isOverlay)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        color: const Color(0xFF000000).withValues(alpha: 0.28),
                      ),
                    ),
                  ),
                ...activePage.elements.map(
                  (element) => _buildRuntimeElement(
                    context,
                    element,
                    overrides: activePage.propertyOverrides,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      ),
      ),
      ),
    );
  }

  Widget _buildRuntimeElement(
    BuildContext context,
    UIElement element, {
    List<PropertyOverride> overrides = const <PropertyOverride>[],
    double opacity = 1.0,
  }) {
    final displayElement = _applyPropertyOverridesToElement(element, overrides);
    // 必须用 Builder 取新的 context：这里传进来的 context 是 State.build 的
    // context，位于 MessageFlowScope / UILinkerSnapshotScope **之上**，
    // 用它去 dependOnInheritedWidgetOfExactType 永远拿不到这些作用域，
    // 消息流会一直落到「无作用域→显示示例消息」的兜底分支。
    Widget child = Builder(
      builder: (innerContext) => UIRenderer.render(innerContext, displayElement),
    );
    if (opacity < 1.0) {
      child = Opacity(opacity: opacity, child: child);
    }
    return Positioned(
      left: element.offset.dx,
      top: element.offset.dy,
      width: element.size.width,
      height: element.size.height,
      child: child,
    );
  }

  /// 数据通道写入调试浮层：列出本轮实际同步进会话副本的键值。
  Widget _buildDataChannelDebug() {
    return IgnorePointer(
      child: Align(
        alignment: Alignment.topCenter,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.56),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '数据通道写入',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                for (final line in _lastChannelDebug)
                  Text(
                    line,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      height: 1.4,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDebugInfo({
    required double scale,
    required double renderedWidth,
    required double renderedHeight,
    required double designWidth,
    required double designHeight,
  }) {
    return Align(
      alignment: Alignment.center,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.56),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Text(
            '设计 ${designWidth.toStringAsFixed(0)}'
            '×${designHeight.toStringAsFixed(0)} · '
            'scale ${scale.toStringAsFixed(3)} · '
            '渲染 ${renderedWidth.toStringAsFixed(0)}×${renderedHeight.toStringAsFixed(0)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  static List<AssemblyPage> _restorePages(UIAssemblyInfo info) {
    final pages = <AssemblyPage>[];
    final rawPages = info.pagesJson.trim();
    if (rawPages.isNotEmpty && rawPages != '[]') {
      try {
        final decoded = jsonDecode(rawPages);
        if (decoded is List) {
          pages.addAll(
            decoded.whereType<Map>().map(
                  (item) => AssemblyPage.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                ),
          );
        }
      } catch (_) {
        pages.clear();
      }
    }

    if (pages.isNotEmpty) {
      pages.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      return pages;
    }

    final legacyElements = <UIElement>[];
    final rawElements = info.elementsJson.trim();
    if (rawElements.isNotEmpty && rawElements != '[]') {
      try {
        final decoded = jsonDecode(rawElements);
        if (decoded is List) {
          legacyElements.addAll(
            decoded.whereType<Map>().map(
                  (item) => UIElement.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                ),
          );
        }
      } catch (_) {}
    }

    return [
      AssemblyPage(
        id: 'runtime_root',
        name: '主菜单',
        type: 'base',
        elements: legacyElements,
      ),
    ];
  }

  static List<AssemblyPage> _clonePages(List<AssemblyPage> pages) {
    return pages.map((page) => AssemblyPage.fromJson(page.toJson())).toList();
  }

  static AssemblyPage? _pageById(List<AssemblyPage> pages, String pageId) {
    for (final page in pages) {
      if (page.id == pageId) return page;
    }
    return null;
  }

  static AssemblyPage _resolveActivePage(
    List<AssemblyPage> pages,
    String? activePageId,
  ) {
    if (pages.isEmpty) {
      return AssemblyPage(id: 'runtime_empty', name: '主菜单', type: 'base');
    }
    if (activePageId != null && activePageId.isNotEmpty) {
      for (final page in pages) {
        if (page.id == activePageId) return page;
      }
    }
    final bases = pages.where((page) => page.isBase).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return bases.isNotEmpty ? bases.first : pages.first;
  }

  static List<AssemblyPage> _ancestorPagesFor(
    List<AssemblyPage> pages,
    AssemblyPage activePage,
  ) {
    final ancestors = <AssemblyPage>[];
    var parentId = activePage.parentPageId;
    final visited = <String>{activePage.id};
    while (parentId != null && parentId.isNotEmpty && visited.add(parentId)) {
      final index = pages.indexWhere((page) => page.id == parentId);
      if (index == -1) break;
      final page = pages[index];
      ancestors.insert(0, page);
      parentId = page.parentPageId;
    }
    return ancestors;
  }

  static UIElement _applyPropertyOverridesToElement(
    UIElement element,
    List<PropertyOverride> overrides,
  ) {
    if (!element.isComposite || element.composite == null || overrides.isEmpty) {
      return element;
    }

    UIElement patchNode(UIElement node) {
      if (!node.isComposite && node.module != null) {
        final matched = overrides
            .where((override) => override.componentId == node.id)
            .toList();
        if (matched.isEmpty) return node;
        final props = Map<String, dynamic>.from(
          _deepCloneValue(node.module!.properties) as Map,
        );
        for (final override in matched) {
          props.addAll(
            Map<String, dynamic>.from(
              _deepCloneValue(override.overrides) as Map,
            ),
          );
        }
        return node.copyWith(module: node.module!.copyWith(properties: props));
      }
      if (node.isComposite && node.composite != null) {
        return node.copyWith(
          composite: node.composite!.copyWith(
            children: node.composite!.children.map(patchNode).toList(),
          ),
        );
      }
      return node;
    }

    return element.copyWith(
      composite: element.composite!.copyWith(
        children: element.composite!.children.map(patchNode).toList(),
      ),
    );
  }

  static dynamic _deepCloneValue(dynamic value) {
    if (value is Map) {
      return value.map(
        (key, entry) => MapEntry(key, _deepCloneValue(entry)),
      );
    }
    if (value is List) return value.map(_deepCloneValue).toList();
    return value;
  }
}
