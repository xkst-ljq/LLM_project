// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_html/flutter_html.dart' as fhtml;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md hide Text;
import 'package:provider/provider.dart';

import '../models/background_card.dart';
import '../models/character_card.dart';
import 'package:llm_ui_engine/llm_ui_engine.dart';
import '../models/prompt_settings.dart';
import '../models/user_profile.dart';
import '../models/world_book_entry.dart';
import '../modules/chat_module.dart';
import '../services/api_config_service.dart';
import '../services/background_service.dart';
import '../services/database_service.dart';
import '../services/prompt_settings_service.dart';
import '../services/status_bar_engine.dart';
import '../services/ui_engine/data_channel_prompt_builder.dart';
import '../services/ui_engine/data_channel_update_engine.dart';
import '../services/ui_engine/status_notification.dart';
import '../widgets/status_notification_layer.dart';
import '../services/user_service.dart';
import '../utils/protagonist_setting_utils.dart';
import '../widgets/chat_assembly_mount.dart';
import '../widgets/keyboard_avoiding_stage.dart';
import '../widgets/page_guide_overlay.dart';
import 'background_picker_sheet.dart';
import 'prompt_preview_page.dart';
import 'prompt_settings_page.dart';
import 'role_user_settings_page.dart';

enum _ChatGuidePhase { none, chat, settings }

class ChatPage extends StatefulWidget {
  final CharacterCard? character;
  final bool startGuide;
  final VoidCallback? onExitGuide;

  const ChatPage({
    super.key,
    this.character,
    this.startGuide = false,
    this.onExitGuide,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with TickerProviderStateMixin {
  final TextEditingController _msgController = TextEditingController();
  final List<Map<String, dynamic>> _messages = [];
  final double _panelWidthFraction = 0.5; // 设置面板占屏幕宽度比例
  late AnimationController _animController; // 平移控制
  double _dragStartOffset = 0.0;
  double _panelStartValue = 0.0;
  String? _dynamicUserDetail;
  List<WorldBookEntry>? _cachedWorldBookEntries;
  PromptSettings _promptSettings = PromptSettings();
  String? _cachedWorldBookId;
  // 世界书 position=after_char 的命中条目，暂存后注入到角色设定之后。
  List<WorldBookEntry> _pendingAfterCharWorldEntries = [];
  // 会话副本覆盖层：界面交互 / 状态栏写入的变量等。
  // 母版（角色卡）不变，渲染时叠加；清空历史时一并清除。
  SessionState _sessionState = SessionState();
  // 状态栏灵动岛展开状态。
  bool _statusBarExpanded = false;
  late AnimationController _fanSnapController;
  double _fanSnapStart = 0.0;
  double _fanSnapTarget = 0.0;
  _ChatGuidePhase _guidePhase = _ChatGuidePhase.none;

  bool _isLastMessage(int index) {
    return index == _messages.length - 1 && !_isLoading;
  }
  int _getUserTurnCount() {
    return _messages.where((m) => m['role'] == 'user').length;
  }

  bool _shouldInjectSummaryPrompt() {
    final turn = _getUserTurnCount();
    final interval = _promptSettings.summaryInterval;

    if (interval <= 0) return false;
    if (turn <= 1) return true;

    return turn % interval == 0;
  }
  bool _shouldInjectFullDetailPrompt() {
    final turn = _getUserTurnCount();
    final interval = _promptSettings.fullDetailInterval;

    if (interval <= 0) return false;
    if (turn <= 1) return true;

    return turn % interval == 0;
  }
  String _truncatePromptText(String text, int maxChars) {
    final raw = text.trim();
    if (raw.length <= maxChars) return raw;
    return '${raw.substring(0, maxChars)}…';
  }
  bool _isCorePromptEntry(CharacterEntry entry) {
    if (_currentCharacter == null) return false;

    if (_currentCharacter!.cardType == 'system') {
      return {
        'system_name',
        'system_summary',
      }.contains(entry.id);
    }

    return {
      'name_entry',
      'relationship',
    }.contains(entry.id);
  }

  List<CharacterEntry> _getEnabledPromptEntries({
    required bool includeDetailed,
  }) {
    if (_currentCharacter == null) return [];

    try {
      final entriesList = jsonDecode(
        _currentCharacter!.entriesJson.isEmpty
            ? '[]'
            : _currentCharacter!.entriesJson,
      ) as List;

      final entries = entriesList
          .map((e) => CharacterEntry.fromJson(e))
          .where((entry) {
        if (!entry.enabled || entry.content.trim().isEmpty) return false;

        // 系统卡主角设定已经作为用户/主角设定处理，避免重复注入
        if (_currentCharacter?.cardType == 'system' &&
            entry.id == 'protagonist') {
          return false;
        }

        final isCore = _isCorePromptEntry(entry);

        if (includeDetailed) {
          return !isCore;
        } else {
          return isCore;
        }
      }).toList();

      return entries;
    } catch (_) {
      return [];
    }
  }

  String _buildEntriesPrompt(List<CharacterEntry> entries) {
    if (entries.isEmpty) return '';

    return entries
        .map((e) => '【${e.title}】\n${e.content}')
        .join('\n\n');
  }

  String _buildPeriodicSummaryPrompt() {
    final lines = <String>[];

    if (_dynamicUserDetail != null && _dynamicUserDetail!.trim().isNotEmpty) {
      lines.add('当前用户/主角设定：');
      lines.add(_truncatePromptText(_dynamicUserDetail!, 500));
    }

    final detailEntries = _getEnabledPromptEntries(includeDetailed: true);

    if (detailEntries.isNotEmpty) {
      lines.add('角色行为相关摘要：');

      for (final entry in detailEntries.take(4)) {
        final formatted = _formatEntryForDetailPanel(entry).trim();
        if (formatted.isEmpty) continue;

        lines.add(
          '【${entry.title}】${_truncatePromptText(formatted, 260)}',
        );
      }
    }

    lines.add(
      '涉及动作、距离、触摸、身体互动、语气、情绪和关系推进时，必须自然考虑上述设定，而不是只在用户直接询问时才使用。',
    );

    return lines.join('\n');
  }

  String _buildContinuityReminderPrompt() {
    return _renderPromptTemplate(_promptSettings.continuityReminder).trim();
  }

  String _buildRoleplayRules() {
    if (_currentCharacter == null) return '';

    final template = _currentCharacter!.cardType == 'character'
        ? _promptSettings.characterRoleplayRules
        : _promptSettings.systemRoleplayRules;

    return _renderPromptTemplate(template).trim();
  }

  String _renderPromptTemplate(String template) {
    final charName = _currentCharacter?.name.trim().isNotEmpty == true
        ? _currentCharacter!.name.trim()
        : '当前角色';

    final userName = _currentUser.name.trim().isNotEmpty
        ? _currentUser.name.trim()
        : '用户';

    var rendered = template
        .replaceAll('{{char}}', charName)
        .replaceAll('{{user}}', userName);

    // 会话副本变量：{{var.xxx}} -> 会话状态里 xxx 的值（界面交互 / 状态栏写入）。
    // 未设置的变量替换为空串，避免把占位符原样发给模型。
    rendered = rendered.replaceAllMapped(
      RegExp(r'\{\{\s*var\.([^}]+?)\s*\}\}'),
      (m) {
        final key = m.group(1)!.trim();
        return _sessionState.vars[key] ?? '';
      },
    );

    // A9.6-3：UI 数据通道占位符 {{ui.语义名}}。
    // 受 llmReadPolicy 约束：不可读的通道替换为空串，绝不泄漏受保护的值。
    rendered = DataChannelPromptBuilder.renderPlaceholders(
      rendered,
      _collectUIChannelPromptItems(),
    );

    return rendered;
  }

  /// 收集当前角色 UI 方案里参与 Prompt 的数据通道。
  ///
  /// 每轮构建 Prompt 时重新解析，保证作者在 Assembly 里改完通道后
  /// 不需要重启会话即可生效。
  List<DataChannelPromptItem> _collectUIChannelPromptItems() {
    final character = _currentCharacter;
    if (character == null) return const <DataChannelPromptItem>[];
    final assemblies = character.meta.uiAssemblies;
    if (assemblies.isEmpty) return const <DataChannelPromptItem>[];
    return DataChannelPromptBuilder.collectItems(
      uiAssemblyJsons: assemblies,
      session: _sessionState,
      statusFields: character.meta.statusBarFields,
      cardEntries: _allCardEntries(),
    );
  }

  /// 角色卡的全部设定条目（含未启用的）。
  ///
  /// A13-2 用它把 `cardEntryTarget` 还原成「身体数据 · 种族」这类显示名。
  /// 这里不过滤 enabled：条目被作者关掉后，玩家此前填的值仍然存在，
  /// 显示名要能正常解析，否则会退化成裸的内部 id。
  List<CharacterEntry> _allCardEntries() {
    final raw = _currentCharacter?.entriesJson ?? '';
    if (raw.trim().isEmpty) return const <CharacterEntry>[];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => CharacterEntry.fromJson(e)).toList();
    } catch (_) {
      return const <CharacterEntry>[];
    }
  }

  /// 供 Assembly 消息流组件使用的对话历史。
  ///
  /// 每次构建时转换：`_messages` 里还带 id / versions 等编辑态字段，
  /// 消息流只需要 role + content。
  List<FlowMessage> get _flowMessages {
    return _messages
        .map(
          (m) => FlowMessage(
            role: (m['role'] as String?) ?? 'assistant',
            content: (m['content'] as String?) ?? '',
          ),
        )
        .where((m) => m.content.isNotEmpty)
        .toList();
  }

  /// 角色头像本地路径，供 Assembly 的 image 组件「头像同步」使用。
  String get _characterAvatarPath => _currentCharacter?.avatar ?? '';

  /// 用户头像本地路径。
  ///
  /// 角色卡里的 `userAvatar` 优先于全局用户设定——
  /// 作者可以为单张卡指定专属的玩家形象。
  String get _userAvatarPath {
    final local = _currentCharacter?.userAvatar ?? '';
    return local.isNotEmpty ? local : _currentUser.avatarPath;
  }

  /// A10-2：常驻 UI 是否已折叠为悬浮球。
  bool _stickyCollapsed = false;

  /// 伴生 UI 当前打开的叠加页 id（无叠加页时为 null）。
  ///
  /// 叠加层打开时 chat_page 切换成全屏浮层（独立悬浮窗）渲染，
  /// 让叠加层「浮出」气泡、覆盖更大区域。
  String? _companionOverlayPageId;

  /// 常驻 UI 相对默认位置的拖动偏移。
  /// 仅存在于本次会话，不持久化——位置属于临时观感，不值得写进角色卡。
  Offset _stickyOffset = Offset.zero;

  /// 正在长按拖动挂件。仅用于给出视觉反馈（轻微放大 + 阴影），
  /// 让玩家知道「已经抓起来了」——长按本身没有可见的触发点。
  bool _stickyDragging = false;

  /// 常驻 UI 的默认纵向锚点：状态栏长条下方。
  /// 状态栏展开时挂件不跟随下移（它已是独立层），由用户自行拖开。
  static const double _stickyTopAnchor = 78.0;

  // ---- 折叠悬浮球 ----
  static const double _ballSize = 44.0;
  static const double _ballMargin = 4.0;

  /// 悬浮球位置（左上角坐标，相对聊天区）。null 表示尚未初始化。
  Offset? _ballPos;

  /// 是否贴边缩进（半隐）。停靠 3 秒后进入。
  bool _ballTucked = false;

  /// 缩进状态下被点出来时的临时展示态，再点一次才展开 UI。
  bool _ballPeeking = false;

  /// 正在拖动悬浮球——拖动期间不缩进。
  bool _ballDragging = false;

  Timer? _ballTuckTimer;

  /// 折叠时记录 UI 位置，展开时让 UI 回到球的附近。

  /// 悬浮球是否停靠在左侧。决定缩进方向与展开方向。
  bool get _ballOnLeft {
    final pos = _ballPos;
    if (pos == null) return false;
    final screenW = MediaQuery.of(context).size.width;
    return pos.dx + _ballSize / 2 < screenW / 2;
  }

  /// 把球吸附到最近一侧，并重启缩进计时。
  void _snapBallToEdge(Size screen) {
    final pos = _ballPos;
    if (pos == null) return;
    final onLeft = pos.dx + _ballSize / 2 < screen.width / 2;
    final targetX =
        onLeft ? _ballMargin : screen.width - _ballSize - _ballMargin;
    // 纵向留出安全范围，避免贴到状态栏或输入栏上。
    final targetY = pos.dy.clamp(_stickyTopAnchor, screen.height - 160.0);
    setState(() => _ballPos = Offset(targetX, targetY));
    _restartBallTuckTimer();
  }

  /// 停靠 3 秒后缩进半个球宽并淡化。
  void _restartBallTuckTimer() {
    _ballTuckTimer?.cancel();
    if (!_stickyCollapsed) return;
    setState(() {
      _ballTucked = false;
      _ballPeeking = false;
    });
    _ballTuckTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted || !_stickyCollapsed || _ballDragging) return;
      setState(() => _ballTucked = true);
    });
  }

  /// A10-1：聊天页挂载的 Assembly UI 改动了会话副本时的统一处理。
  ///
  /// 玩家在常驻 / 伴生 UI 上的交互（拖滑块、按开关）会直接写入会话副本，
  /// 这里负责落盘并刷新界面，使状态栏与 UI 组件保持一致。
  Future<void> _onAssemblySessionChanged(SessionState next) async {
    _sessionState = next;
    // 同 _dismissOpeningAssembly：先刷新界面再落盘。
    //
    // 这个回调跟着 300ms 轮询走，玩家每拖一下滑块都会进来一次。
    // 等磁盘 IO 完成才 setState 会让交互带上明显的黏滞感。
    if (mounted) setState(() {});
    await _saveSessionState();
  }

  /// 玩家档案通道写入：把值落到**角色卡本体**并刷新显示。
  ///
  /// 与 `_onAssemblySessionChanged` 的区别是目标不同——
  /// 那个写会话副本，这个写 `character.user_name` /
  /// `user_detail_setting`。开场白里让玩家填的名字要能出现在
  /// 「用户设定」里，只能走这条路（用户反馈：填了名字用户名还是「我」）。
  ///
  /// 优先级见 `_loadUser`：本卡 userName > 主角设定 > 全局用户，
  /// 所以写本卡这一层就能覆盖显示名，且不污染别的角色。
  Future<void> _onAssemblyUserProfileChanged(
    String? name,
    String? detail,
  ) async {
    final character = _currentCharacter;
    if (character == null) return;

    final nextName = name?.trim() ?? '';
    final nextDetail = detail?.trim() ?? '';
    // 值没变就不写库：这个回调跟着 300ms 轮询走，
    // 不做判等会每轮都刷一次数据库。
    final nameChanged = nextName.isNotEmpty && nextName != character.userName;
    final detailChanged =
        nextDetail.isNotEmpty && nextDetail != character.userDetailSetting;
    if (!nameChanged && !detailChanged) return;

    if (nameChanged) character.userName = nextName;
    if (detailChanged) character.userDetailSetting = nextDetail;

    // 只提交改动的列——updateCharacter 走的是 db.update，
    // 传全字段没必要，也容易把别处刚改的值覆盖回旧值。
    await DatabaseService.updateCharacter({
      'id': character.id,
      if (nameChanged) 'user_name': nextName,
      if (detailChanged) 'user_detail_setting': nextDetail,
    });
    if (!mounted) return;
    await _loadUser();
  }

  /// 读取当前角色的会话状态（进入聊天 / 切换角色时调用）。
  Future<void> _loadSessionState() async {
    if (_currentCharacter == null) {
      _sessionState = SessionState();
      _openingDismissed = false;
      _sessionReady = true;
      return;
    }
    final raw = await DatabaseService.getSessionStateJson(_currentCharacter!.id);
    _sessionState = SessionState.fromJsonString(raw);
    // 快速标记跟着会话副本走：换角色 / 重进聊天都要重新对齐，
    // 否则上一个角色的「已确认」会带到下一个角色身上。
    _openingDismissed = OpeningGreetingState.isDismissed(_sessionState);
    _invalidateAssemblyCaches();
    _sessionReady = true;
    _ensureStatusValuesInitialized();
  }

  /// 用卡片里的状态栏字段定义，为「尚无当前值」的字段填入初始值。
  /// 只补缺失的键，不覆盖已有值；新增字段（卡片更新后）也能被补上。
  void _ensureStatusValuesInitialized() {
    if (_currentCharacter == null) return;
    final fields = _currentCharacter!.meta.statusBarFields;
    if (fields.isEmpty) return;
    var changed = false;
    for (final f in fields) {
      if (!_sessionState.statusValues.containsKey(f.id)) {
        _sessionState.statusValues[f.id] = f.initialValue;
        changed = true;
      }
    }
    if (changed) {
      // 仅在补了初始值时持久化一次（不阻塞调用方）。
      _saveSessionState();
    }
  }

  /// 把会话状态回滚到「这批消息产生之前」。
  ///
  /// 每条 AI 消息在入库时都记录了结算前的状态快照。删除一段对话时，
  /// 取其中 id 最小（即最早）的那条的快照即可还原——它之后的所有
  /// 状态变化都由这批被删消息产生。
  ///
  /// 找不到任何快照时不做处理：可能是旧数据（升级前入库，无快照），
  /// 此时保持现状比猜一个值更安全。
  Future<void> _rollbackSessionStateFor(List<int> deletedIds) async {
    if (_currentCharacter == null || deletedIds.isEmpty) return;

    final snapshots = await DatabaseService.getStateSnapshots(deletedIds);
    if (snapshots.isEmpty) return;

    final earliestId =
        snapshots.keys.reduce((a, b) => a < b ? a : b);
    final raw = snapshots[earliestId];
    if (raw == null || raw.isEmpty) return;

    final restored = SessionState.fromJsonString(raw);

    // 开场白「已确认」是**会话级的一次性事实**，不随消息回滚。
    //
    // 快照是在每条 AI 消息结算前拍的，可能早于玩家确认开场白。
    // 整体覆盖会把标记抹回 false，于是删几条消息后开场白又弹出来，
    // 而玩家明明已经看过了。
    // 只有清空聊天记录（会话副本整个重建）才该让它重新出现。
    if (OpeningGreetingState.isDismissed(_sessionState)) {
      OpeningGreetingState.markDismissed(restored);
    }

    _sessionState = restored;
    _openingDismissed = OpeningGreetingState.isDismissed(restored);
    _ensureStatusValuesInitialized();
    await _saveSessionState();
    if (mounted) setState(() {});
  }

  /// 持久化当前角色的会话状态。
  /// 切换开场白 = 切换开场分支。
  ///
  /// ## 为什么不能只改消息文本
  ///
  /// 此前这里只写 `msg['content']`，切完就没了下文。
  /// 但不同开场白往往带**不同的初始状态**——
  /// 例如「新人入狱」精神 84%、「狱警入职」精神 90%。
  /// 运行时若不知道当前是第几条，这些差异根本无从套用。
  ///
  /// 各开场白之间是**平级分支**，没有父子关系；
  /// 下标 0 即主支路，作者未单独设计的分支照搬它。
  ///
  /// 分支索引写进 `SessionState.branchIndex` 并落盘，
  /// 这样重开 App、切走再回来都还认得当前分支。
  void _switchGreeting(
    Map<String, dynamic> msg,
    List<OpeningGreeting> greetings,
    int index,
  ) {
    if (index < 0 || index >= greetings.length) return;
    setState(() {
      msg['content'] = greetings[index].content;
      _sessionState.branchIndex = index;
    });
    _applyBranchInitialValues(index);
    _saveSessionState();

    final id = int.tryParse(msg['id']?.toString() ?? '');
    if (id != null) {
      DatabaseService.updateMessageContent(id, greetings[index].content);
    }
  }

  /// 套用该分支的初始状态值。
  ///
  /// 只覆盖**尚未被玩家/LLM 改动过**的字段——
  /// 已经在对话中变化的数值不该因为翻看别的开场白就被重置。
  /// 判据是当前值仍等于该字段的默认初值。
  void _applyBranchInitialValues(int branch) {
    // 用 _currentCharacter 而非 widget.character：
    // 前者是运行时真正生效的那张卡（可被切换 / 重新加载），
    // 后者只是初始入参，且可空。
    final fields = _currentCharacter?.meta.statusBarFields;
    if (fields == null || fields.isEmpty) return;
    var changed = false;
    for (final f in fields) {
      final preset = f.initialValueForBranch(branch);
      if (preset == null) continue;
      final cur = _sessionState.statusValues[f.id];
      // 未设过值，或仍是别的分支的预设 → 可以覆盖。
      if (cur == null || cur == f.initialValue || f.isBranchPreset(cur)) {
        _sessionState.statusValues[f.id] = preset;
        changed = true;
      }
    }
    if (changed) setState(() {});
  }

  Future<void> _saveSessionState() async {
    // 版本号在这里统一递增：所有会话写入最终都汇到这个函数，
    // 逐个改调用点必然会漏。运行时视图靠它识别「内容变了但对象没换」。
    _sessionVersion++;
    if (_currentCharacter == null) return;
    await DatabaseService.setSessionStateJson(
      _currentCharacter!.id,
      _sessionState.toJsonString(),
    );
  }

  /// 处理 LLM 回复中的状态栏变更：解析变化量 → 引擎算账 → 回写会话副本，
  /// 返回剥离掉 <状态变化> 技术标记后的展示文本。
  /// 无状态栏字段时原样返回。
  Future<String> _processStatusBarReply(String reply) async {
    if (_currentCharacter == null) return reply;
    final fields = _currentCharacter!.meta.statusBarFields;
    if (fields.isEmpty) return reply;

    // 被数据通道标记为不可写的字段，即使 LLM 输出了也不应生效。
    final policies = DataChannelPromptBuilder.collectStatusFieldPolicies(
      _collectUIChannelPromptItems(),
    );

    // 值一律写入，不再分「自动 / 待确认」两批。
    //
    // 旧实现里 confirm 策略会先算不写、弹卡片让玩家逐条勾选——
    // 那是「否决权」。用户判断这个语义不对：数据变化本身不该让玩家拒绝，
    // 该做的是把重要变化**告知**他。勾掉一条会让状态分叉
    // （AI 说升级了、玩家点拒绝，那这局到底算不算升级？）。
    final applied = StatusBarEngine.applyFromReply(
      reply,
      fields,
      _sessionState.statusValues,
      policies: policies,
    );
    var changed = applied.isNotEmpty;

    // 写完再通知——通知就是通知，不是预告。
    if (applied.isNotEmpty) {
      _notificationQueue.enqueue(
        applied
            .map((c) {
              final policy = policies[c.fieldId];
              return StatusNotification(
                label: c.fieldName,
                oldValue: c.oldValue,
                newValue: c.newValue,
                style: StatusNotifyStyle.parse(policy?.notifyStyle),
                template: policy?.notifyTemplate ?? '',
              );
            })
            .where((n) => !n.style.isSilent),
      );
    }

    if (changed) {
      await _saveSessionState();
      if (mounted) setState(() {});
    }
    return StatusBarEngine.stripFromReply(reply);
  }


  /// A9.6-4：处理 LLM 回复中的 `<界面状态变化>` 块。
  ///
  /// 流程：解析 → 权限校验 → 引擎算账 → 按应用策略分流
  ///   - auto_low_risk：直接写入会话副本
  ///   - confirm：弹确认卡片，用户逐条决定
  ///   - never / 不可写 / 未知语义名：静默丢弃
  ///
  /// 返回剥离技术标记后的展示文本；无数据通道时原样返回。
  Future<String> _processUIChannelReply(String reply) async {
    if (_currentCharacter == null) return reply;
    final items = _collectUIChannelPromptItems();
    if (items.isEmpty) return reply;

    final result = DataChannelUpdateEngine.parse(
      reply: reply,
      items: items,
      session: _sessionState,
      statusFields: _currentCharacter!.meta.statusBarFields,
    );

    final stripped = DataChannelUpdateEngine.stripFromReply(reply);
    if (result.isEmpty) return stripped;

    // 同上：值一律写入，不再有「待确认」这一批。
    final changed =
        DataChannelUpdateEngine.apply(_sessionState, result.applied);

    _notificationQueue.enqueue(
      result.needsNotify.map(
        (u) => StatusNotification(
          label: u.semanticLabel,
          oldValue: u.oldValue,
          newValue: u.newValue,
          style: StatusNotifyStyle.parse(u.notifyStyle),
          template: u.notifyTemplate,
        ),
      ),
    );

    if (changed) {
      await _saveSessionState();
      if (mounted) setState(() {});
    }
    return stripped;
  }


  List<CharacterCard> _selectableCharacters = [];

  Future<PromptPreviewData> _buildPromptPreviewData(
      PromptSettings previewSettings,
      ) async {
    final oldSettings = _promptSettings;

    _promptSettings = previewSettings;

    try {
      final systemPrompt = await _buildFinalSystemPrompt();

      final baseMessages = _messages
          .map(
            (m) => {
          'role': (m['role'] as String?) ?? '',
          'content': (m['content'] as String?) ?? '',
        },
      )
          .toList();

      // 预览也体现历史后注入，与真实发送保持一致
      final requestMessages = _withPostHistoryInstructions(baseMessages);

      int totalChars = systemPrompt.length;
      for (final msg in requestMessages) {
        totalChars += (msg['content'] ?? '').length;
      }

      final estimatedTokens = (totalChars / 2).ceil();

      return PromptPreviewData(
        userTurnCount: _getUserTurnCount(),
        injectedSummary: _shouldInjectSummaryPrompt(),
        injectedFullDetail: _shouldInjectFullDetailPrompt(),
        estimatedTokens: estimatedTokens,
        systemPrompt: systemPrompt,
        messages: requestMessages,
      );
    } finally {
      _promptSettings = oldSettings;
    }
  }

  Future<void> _loadSelectableCharacters() async {
    final all = await DatabaseService.getAllCharacters();
    setState(() {
      _selectableCharacters = all
          .map(
            (c) => CharacterCard(
              id: c['id'] as String,
              name: c['name'] as String,
              avatar: c['avatar'] as String? ?? '',
              cardImagePath: c['card_image_path'] as String? ?? '',
              description: c['description'] as String? ?? '',
              systemPrompt: c['system_prompt'] as String? ?? '',
              userName: c['user_name'] as String? ?? '',
              userAvatar: c['user_avatar'] as String? ?? '',
              userDetailSetting: c['user_detail_setting'] as String? ?? '',
            ),
          )
          .where((c) => c.id != _currentCharacter?.id)
          .toList();
    });
  }

  void _onGlobalUserChanged() {
    if (!mounted) return;
    _loadUser();
  }

  void _onPromptSettingsChanged() {
    if (!mounted) return;
    _loadPromptSettings();
  }

  Future<void> _loadPromptSettings() async {
    final settings = await PromptSettingsService.getEffectiveSettings(
      _currentCharacter?.id,
    );

    if (!mounted) return;

    setState(() {
      _promptSettings = settings;
    });
  }

  Widget _buildBackground(BackgroundCard bg) {
    switch (bg.type) {
      case 'color':
        return _buildColorBackground(bg.colorValue);
      case 'gradient':
        try {
          final data = jsonDecode(bg.colorValue.isEmpty ? '{}' : bg.colorValue);
          final gradientList = data['gradient'] as List?;
          if (gradientList != null && gradientList.isNotEmpty) {
            final colors = <Color>[];
            final stops = <double>[];
            for (final item in gradientList) {
              final hex = item['color'] as String?;
              if (hex != null) {
                colors.add(
                  Color(int.parse(hex.replaceFirst('#', 'FF'), radix: 16)),
                );
                stops.add((item['position'] as num?)?.toDouble() ?? 0.0);
              }
            }
            if (colors.isNotEmpty) {
              // 使用第一个停止点的方向作为整体渐变方向
              final first = gradientList.first as Map<String, dynamic>;
              final sx = (first['startX'] as num?)?.toDouble() ?? 0.5;
              final sy = (first['startY'] as num?)?.toDouble() ?? 0.0;
              final ex = (first['endX'] as num?)?.toDouble() ?? 0.5;
              final ey = (first['endY'] as num?)?.toDouble() ?? 1.0;

              return Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment(sx * 2 - 1, sy * 2 - 1),
                    end: Alignment(ex * 2 - 1, ey * 2 - 1),
                    colors: colors,
                    stops: stops,
                  ),
                ),
              );
            }
          }
        } catch (_) {}
        // 解析失败或没有数据时，返回默认渐变
        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFE3F2FD), Color(0xFFF3E5F5)],
            ),
          ),
        );
      case 'image':
        if (bg.originalImagePath.isNotEmpty) {
          final file = File(bg.originalImagePath);
          if (file.existsSync()) {
            return Image.file(file, fit: BoxFit.cover);
          }
        }
        return Container(color: Colors.grey[300]);
      default:
        return Container(color: Colors.grey[300]);
    }
  }

  Widget _buildColorBackground(String colorValue) {
    try {
      final data = jsonDecode(colorValue.isEmpty ? '{}' : colorValue);
      final active = data['active'] as String?;
      if (active == 'color' && data.containsKey('color')) {
        final hex = data['color'] as String;
        final color = Color(int.parse(hex.replaceFirst('#', 'FF'), radix: 16));
        return Container(color: color);
      }
    } catch (_) {}
    // 解析失败返回默认渐变
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFE3F2FD), Color(0xFFF3E5F5)],
        ),
      ),
    );
  }

  // 椭圆轮盘
  double _fanOffset = 0.0; // 弧长偏移量
  double _cardDs = 80.0; // 卡片弧长间距（缓存）
  double _halfArcLen = 200.0; // 上半弧长的一半（缓存）
  int _cardCount = 0;

  // 惯性滑动
  Ticker? _inertiaTicker;
  double _inertiaVelocity = 0.0;

  // 详情弹窗
  bool _showCardDetail = false;
  CharacterCard? _detailCard;
  late AnimationController _detailAnimController;
  late Animation<double> _detailScaleAnim;
  late Animation<double> _detailFadeAnim;

  List<WorldBookEntry> _getActiveWorldBookEntries(int scanDepth) {
    // 缓存：避免每次请求都解析 JSON
    if (_cachedWorldBookId == _currentCharacter?.worldBookId &&
        _cachedWorldBookEntries != null) {
      return _filterActiveEntries(_cachedWorldBookEntries!, scanDepth);
    }
    return [];
  }

  void _cacheWorldBookEntries(List<WorldBookEntry> entries) {
    _cachedWorldBookEntries = entries;
    _cachedWorldBookId = _currentCharacter?.worldBookId;
  }

  List<WorldBookEntry> _filterActiveEntries(
    List<WorldBookEntry> allEntries,
    int scanDepth,
  ) {
    // 只考虑已启用的条目（作者关闭 / 用户关闭的条目不参与触发）。
    final entries = allEntries.where((e) => e.enabled).toList();

    final activeIds = <String>{};

    // 永久激活（常驻）
    for (final e in entries) {
      if (e.alwaysActive) activeIds.add(e.id);
    }

    // 关键词匹配：keys 列表中命中任意一个即触发。
    final recentText = _messages.reversed
        .take(scanDepth)
        .map((m) => m['content'] as String)
        .join(' ');

    bool hit(WorldBookEntry e, String text) {
      for (final k in e.keys) {
        final kw = k.trim();
        if (kw.isNotEmpty && text.contains(kw)) return true;
      }
      return false;
    }

    for (final e in entries) {
      if (e.hasKeys && hit(e, recentText)) {
        activeIds.add(e.id);
      }
    }

    // 递归扩展
    bool changed = true;
    int rounds = 3;
    while (changed && rounds > 0) {
      changed = false;
      rounds--;
      final activatedContent = entries
          .where((e) => activeIds.contains(e.id) && e.recursive)
          .map((e) => e.content)
          .join(' ');
      for (final e in entries) {
        if (!activeIds.contains(e.id) && e.hasKeys && hit(e, activatedContent)) {
          activeIds.add(e.id);
          changed = true;
        }
      }
    }

    // 命中条目按注入优先级排序：insertionOrder 小的在前；
    // 相同优先级再按 sortOrder（条目原始顺序）稳定排序。
    final result = entries.where((e) => activeIds.contains(e.id)).toList();
    result.sort((a, b) {
      final c = a.insertionOrder.compareTo(b.insertionOrder);
      if (c != 0) return c;
      return a.sortOrder.compareTo(b.sortOrder);
    });
    return result;
  }

  Map<String, String> _parseCharacterInfo(CharacterCard card) {
    String background = card.description.isNotEmpty ? card.description : '';
    String scenario = '';

    final prompt = card.systemPrompt;
    if (prompt.isNotEmpty) {
      // 尝试从 systemPrompt 提取当前情景
      for (final kw in ['当前情景', '当前场景', '情景：', '场景：', '开场']) {
        final idx = prompt.indexOf(kw);
        if (idx != -1) {
          final start = idx + kw.length;
          final raw = prompt
              .substring(start, (start + 150).clamp(0, prompt.length))
              .trim();
          final cut = raw.indexOf('\n\n');
          scenario = cut != -1 ? raw.substring(0, cut).trim() : raw;
          break;
        }
      }
      // 若 description 为空，用 prompt 首段作为背景介绍
      if (background.isEmpty) {
        final first = prompt.split('\n\n').first.trim();
        background = first.length > 120 ? '${first.substring(0, 120)}…' : first;
      }
    }

    return {
      'name': card.name,
      'background': background.isEmpty ? '暂无介绍' : background,
      'scenario': scenario,
    };
  }

  String _detailFieldLabel(
      String entryId,
      String fieldKey, {
        String? parentKey,
      }) {
    const map = {
      'name_entry': {
        'last_name': '姓',
        'first_name': '名',
        'other': '其他',
      },
      'body': {
        'race': '种族',
        'gender': '性别',
        'age': '年龄',
        'height': '身高',
        'weight': '体重',
        'measurements': '三围',
        'other': '其他数据',
      },
      'psychology': {
        'personality': '性格',
        'thoughts': '思想',
        'interests': '兴趣/爱好/癖好',
      },
      'background': {
        'origin': '出身背景',
        'experiences': '经历事件',
        'current': '当前背景',
      },
      'system_details': {
        'world_setting': '世界设定',
        'worldview': '世界观设定',
        'system_mechanism': '系统机制设定',
      },
      'protagonist': {
        'name': '主角名称',
        'detail': '主角详细设定',
      },
      'plot': {
        'cause': '起因',
        'events': '中途特定触发事件',
        'goal': '目标',
        'possible_endings': '可能结局设定',
      },
    };

    // 系统卡 protagonist.detail 下的字段
    if (entryId == 'protagonist' && parentKey == 'detail') {
      const detailMap = {
        'race': '种族',
        'gender': '性别',
        'age': '年龄',
        'body': '身体',
        'background': '背景',
      };
      return detailMap[fieldKey] ?? fieldKey;
    }

    return map[entryId]?[fieldKey] ?? fieldKey;
  }

  String _indentDetailLines(String text) {
    return text
        .split('\n')
        .map((line) => line.trim().isEmpty ? line : '  $line')
        .join('\n');
  }

  String _formatEntryValueForDetail(
      String entryId,
      dynamic value, {
        String? parentKey,
      }) {
    if (value == null) return '';

    if (value is Map) {
      final lines = <String>[];

      for (final rawKey in value.keys) {
        final key = rawKey.toString();
        final childValue = value[rawKey];

        final label = _detailFieldLabel(
          entryId,
          key,
          parentKey: parentKey,
        );

        final formatted = _formatEntryValueForDetail(
          entryId,
          childValue,
          parentKey: key,
        ).trim();

        if (formatted.isEmpty) continue;

        if (childValue is Map) {
          lines.add('$label：\n${_indentDetailLines(formatted)}');
        } else {
          lines.add('$label：$formatted');
        }
      }

      return lines.join('\n');
    }

    if (value is List) {
      return value
          .map((e) => _formatEntryValueForDetail(entryId, e).trim())
          .where((e) => e.isNotEmpty)
          .join('、');
    }

    return value.toString().trim();
  }

  String _formatEntryForDetailPanel(CharacterEntry entry) {
    final raw = entry.content.trim();
    if (raw.isEmpty) return '';

    if (raw.startsWith('{')) {
      try {
        final decoded = jsonDecode(raw);
        final formatted = _formatEntryValueForDetail(entry.id, decoded).trim();
        if (formatted.isNotEmpty) return formatted;
      } catch (_) {
        return raw;
      }
    }

    return raw;
  }

  /// 把角色扩展元信息（标签 / 作者 / 版本 / 作者备注 / 来源）拼成展示文本。
  /// 这些信息默认不进 Prompt，只在角色详情里展示。
  String _buildCharacterMetaText(CharacterCard card) {
    final meta = card.meta;
    if (meta.isEmpty) return '';

    final lines = <String>[];
    if (meta.tags.isNotEmpty) {
      lines.add('标签：${meta.tags.join('、')}');
    }
    if (meta.creator.trim().isNotEmpty) {
      lines.add('作者：${meta.creator.trim()}');
    }
    if (meta.characterVersion.trim().isNotEmpty) {
      lines.add('版本：${meta.characterVersion.trim()}');
    }
    if (meta.sourceFormat.trim().isNotEmpty) {
      lines.add('来源：${meta.sourceFormat.trim()}');
    }
    if (meta.creatorNotes.trim().isNotEmpty) {
      lines.add('作者备注：\n${meta.creatorNotes.trim()}');
    }

    if (lines.isEmpty) return '';
    return '【角色信息】\n${lines.join('\n')}';
  }

  String _buildCharacterDetailText(CharacterCard card) {
    try {
      final metaText = _buildCharacterMetaText(card);

      final rawList = jsonDecode(
        card.entriesJson.isEmpty ? '[]' : card.entriesJson,
      ) as List;

      final entries = rawList
          .map(
            (e) => CharacterEntry.fromJson(
          Map<String, dynamic>.from(e as Map),
        ),
      )
          .toList();

      final detailIds = card.cardType == 'system'
          ? {
        'system_details',
        'protagonist',
        'plot',
      }
          : {
        'body',
        'psychology',
        'background',
      };

      final detailEntries = entries.where((entry) {
        if (entry.content.trim().isEmpty) return false;

        // 详情展示页用于查看角色卡信息，不一定只显示启用条目。
        // 如果你只想显示启用条目，可以取消下一行注释：
        // if (!entry.enabled) return false;

        return detailIds.contains(entry.id) || entry.isCustom;
      }).toList();

      final sections = <String>[];
      if (metaText.isNotEmpty) sections.add(metaText);

      for (final entry in detailEntries) {
        final content = _formatEntryForDetailPanel(entry).trim();
        if (content.isEmpty) continue;

        sections.add('【${entry.title}】\n$content');
      }

      if (sections.isEmpty) return '暂无详细设定';

      return sections.join('\n\n');
    } catch (_) {
      return '暂无详细设定';
    }
  }

  Widget _buildDetailSettingPanel(CharacterCard card) {
    final detailText = _buildCharacterDetailText(card);
    final screenHeight = MediaQuery.of(context).size.height;

    // 固定高度，但根据屏幕大小略微自适应
    final panelHeight = (screenHeight * 0.13).clamp(96.0, 135.0).toDouble();

    final hasImage =
        card.cardImagePath.isNotEmpty && _fileExists(card.cardImagePath);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: panelHeight,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 背景：优先使用角色卡封面高斯模糊
              if (hasImage)
                ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Transform.scale(
                    scale: 1.06,
                    child: Image.file(
                      File(card.cardImagePath),
                      fit: BoxFit.cover,
                    ),
                  ),
                )
              else
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withValues(alpha: 0.22),
                        Colors.white.withValues(alpha: 0.10),
                      ],
                    ),
                  ),
                ),

              // 遮罩：保证文字可读性
              Container(
                color: hasImage
                    ? Colors.black.withValues(alpha: 0.52)
                    : Colors.black.withValues(alpha: 0.18),
              ),

              // 边框
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.22),
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 标题栏
                    Row(
                      children: [
                        Icon(
                          Icons.article_outlined,
                          size: 16,
                          color: Colors.white.withValues(alpha: 0.92),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '详细设定',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.94),
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 6),

                    // 内容区：固定框内滚动
                    Expanded(
                      child: Scrollbar(
                        thumbVisibility: false,
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: Text(
                            detailText,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.92),
                              fontSize: 12,
                              height: 1.45,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 惯性结束后吸附到最近卡片
  void _snapFanOffset() {
    final centerIdx = (_cardCount - 1) / 2.0;
    final maxOffset = centerIdx * _cardDs;
    // 合法吸附点是「让某张卡正好居中」的偏移：(i - centerIdx) * ds。
    // 当卡片数为偶数时 centerIdx 是半整数，直接四舍五入到 ds 整数倍会落在
    // 两张卡之间（出现两张并排居中）。这里按 centerIdx 对齐后再取整。
    final i = (_fanOffset / _cardDs + centerIdx).round();
    final snapped = (i - centerIdx) * _cardDs;
    setState(() {
      _fanOffset = snapped.clamp(-maxOffset, maxOffset);
    });
  }

  /// 启动惯性（拖拽结束时调用）
  void _startInertia(double velocityPxSec) {
    _inertiaTicker?.stop();
    _inertiaTicker?.dispose();
    _inertiaTicker = null;

    // 拖拽方向与 fanOffset 方向相反（向右拖 → fanOffset 减少）
    _inertiaVelocity = velocityPxSec;

    if (_inertiaVelocity.abs() < 60) {
      _snapFanOffset();
      return;
    }

    DateTime? lastTime;
    _inertiaTicker = createTicker((_) {
      if (!mounted) return;
      final now = DateTime.now();
      final dtSec = lastTime == null
          ? 0.016
          : now.difference(lastTime!).inMicroseconds / 1e6;
      lastTime = now;

      final maxOffset = (_cardCount - 1) / 2.0 * _cardDs;
      setState(() {
        _fanOffset += _inertiaVelocity * dtSec;
        _inertiaVelocity *= pow(0.92, dtSec * 60).toDouble(); // 摩擦减速

        if (_fanOffset.abs() >= maxOffset) {
          _fanOffset = _fanOffset.clamp(-maxOffset, maxOffset);
          _inertiaVelocity = 0;
        }
        // 速度低于阈值 → 吸附停止
        if (_inertiaVelocity.abs() < 80) {
          _snapFanOffset();
          _inertiaTicker?.stop();
          _inertiaTicker?.dispose();
          _inertiaTicker = null;
        }
      });
    });
    _inertiaTicker!.start();
  }

  Widget _buildFanCards() {
    final cards = _selectableCharacters;
    if (cards.isEmpty) {
      return const Center(
        child: Text('没有可切换的角色', style: TextStyle(color: Colors.white70)),
      );
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // ── 水平弧形参数（新版排序方式） ──
    final cx = screenWidth / 2;
    final baseY = screenHeight - 240.0; // 轮盘基准线，保持在屏幕偏下
    const cardW = 140.0;
    const cardH = 210.0;
    const cornerR = 12.0;
    const ds = 80.0; // 卡片间距（沿用旧变量 _cardDs）
    _cardDs = ds;

    _cardCount = cards.length;
    // 把“半弧长”语义替换为屏幕中心线，这样旧的 _snapFanOffset / 惯性 / 居中判断全部兼容
    _halfArcLen = screenWidth / 2;

    // 轻微弧形：中间向上凸，两边自然下沉（最大 40 像素）
    double getArcY(double x) {
      final dx = (x - cx).abs() / (screenWidth * 0.6);
      return dx * dx * 40.0;
    }

    final centerIdx = (cards.length - 1) / 2.0;

    // 边界限制（语义与旧版保持一致）
    final maxFanOffset = _halfArcLen + centerIdx * ds;
    _fanOffset = _fanOffset.clamp(-maxFanOffset, maxFanOffset);

    final List<_FanCard> fanCards = [];
    for (int i = 0; i < cards.length; i++) {
      final x = cx + (centerIdx - i) * ds + _fanOffset;
      final y = baseY + getArcY(x);

      // 超出可视区过远的卡片不渲染（可选优化）
      if (x < -cardW || x > screenWidth + cardW) continue;

      final fc = _FanCard(character: cards[i], t: 0.0);
      fc._x = x;
      fc._y = y;
      // 不再旋转，保持水平
      fc._arcS = x; // 用 x 坐标替代旧版弧长，用于居中判断
      fc._index = i;
      fanCards.add(fc);
    }

    // 按 y 降序：y 大（靠下）的先画，中间（靠上）的后画 → 中间卡片在最上层
    fanCards.sort((a, b) => b._y.compareTo(a._y));

    return SizedBox.expand(
      child: Stack(
        clipBehavior: Clip.none,
        children: fanCards.map((card) {
          final isCentered = (card._arcS - _halfArcLen).abs() < ds * 0.5;

          return Positioned(
            left: card._x - cardW / 2,
            top: card._y,
            // 新版 y 已经是顶部坐标，不再减 cardH
            width: cardW,
            height: cardH,
            child: GestureDetector(
              onTap: () {
                if (isCentered) {
                  setState(() {
                    _detailCard = card.character;
                    _showCardDetail = true;
                  });
                  _detailAnimController.forward(from: 0);
                } else {
                  // 停止惯性，避免冲突
                  _inertiaTicker?.stop();
                  _inertiaTicker?.dispose();
                  _inertiaTicker = null;

                  final targetOffset = (card._index - centerIdx) * _cardDs;
                  final maxOff = _halfArcLen + centerIdx * _cardDs;
                  final clampedTarget = targetOffset.clamp(-maxOff, maxOff);

                  _fanSnapStart = _fanOffset;
                  _fanSnapTarget = clampedTarget;
                  _fanSnapController.forward(from: 0);
                }
              },
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(cornerR),
                  boxShadow: [
                    BoxShadow(
                      color: isCentered
                          ? Colors.white.withValues(alpha: 0.2)
                          : Colors.black38,
                      blurRadius: isCentered ? 20 : 8,
                      spreadRadius: isCentered ? 3 : 0,
                      offset: const Offset(0, 3),
                    ),
                  ],
                  image: card.character.cardImagePath.isNotEmpty
                      ? DecorationImage(
                          image: FileImage(File(card.character.cardImagePath)),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: card.character.cardImagePath.isEmpty
                    ? Container(
                        decoration: BoxDecoration(
                          color: Colors.grey[400],
                          borderRadius: BorderRadius.circular(cornerR),
                        ),
                        child: Center(
                          child: Text(
                            card.character.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : null,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCardDetailOverlay(CharacterCard card) {
    final info = _parseCharacterInfo(card);
    const cardW = 215.0;
    const cardH = 320.0;

    return Positioned.fill(
      child: AnimatedBuilder(
        animation: _detailAnimController,
        builder: (ctx, child) {
          final fadeVal = _detailFadeAnim.value;
          final scaleVal = _detailScaleAnim.value;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              _detailAnimController.reverse().then((_) {
                if (mounted) setState(() => _showCardDetail = false);
              });
            },
            child: Stack(
              children: [
                // 磨砂玻璃背景（可透见轮盘）
                Positioned.fill(
                  child: Opacity(
                    opacity: fadeVal,
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ),
                // 内容（缩放动画）
                Opacity(
                  opacity: fadeVal,
                  child: Transform.scale(
                    scale: 0.6 + 0.4 * scaleVal,
                    child: GestureDetector(
                      onTap: () {}, // 阻止冒泡关闭
                      child: Column(
                        children: [
                          // 顶部简介面板
                          SafeArea(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: BackdropFilter(
                                  filter: ImageFilter.blur(
                                    sigmaX: 10,
                                    sigmaY: 10,
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.13,
                                      ),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: Colors.white.withValues(
                                          alpha: 0.2,
                                        ),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          info['name']!,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        if (info['background']!.isNotEmpty) ...[
                                          const SizedBox(height: 6),
                                          Text(
                                            '背景介绍',
                                            style: TextStyle(
                                              color: Colors.white.withValues(
                                                alpha: 0.55,
                                              ),
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            info['background']!,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 13,
                                              height: 1.45,
                                            ),
                                            maxLines: 3,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                        if (info['scenario']!.isNotEmpty) ...[
                                          const SizedBox(height: 8),
                                          Text(
                                            '当前情景',
                                            style: TextStyle(
                                              color: Colors.white.withValues(
                                                alpha: 0.55,
                                              ),
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            info['scenario']!,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 13,
                                              height: 1.45,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          _buildDetailSettingPanel(card),
                          // 放大卡片 + 播放按钮
                          Expanded(
                            child: Center(
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Container(
                                    width: cardW,
                                    height: cardH,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: 0.45,
                                          ),
                                          blurRadius: 30,
                                          offset: const Offset(0, 10),
                                        ),
                                      ],
                                      image: card.cardImagePath.isNotEmpty
                                          ? DecorationImage(
                                              image: FileImage(
                                                File(card.cardImagePath),
                                              ),
                                              fit: BoxFit.cover,
                                            )
                                          : null,
                                    ),
                                    child: card.cardImagePath.isEmpty
                                        ? Container(
                                            decoration: BoxDecoration(
                                              color: Colors.grey[400],
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                            ),
                                            child: Center(
                                              child: Text(
                                                card.name,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 20,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          )
                                        : null,
                                  ),
                                  // 播放按钮（右下角）
                                  Positioned(
                                    right: -12,
                                    bottom: -12,
                                    child: GestureDetector(
                                      onTap: () {
                                        _switchCharacter(card);
                                        _detailAnimController.reverse().then((
                                          _,
                                        ) {
                                          if (mounted) {
                                            setState(() {
                                              _showCardDetail = false;
                                              _showFanPanel = false;
                                            });
                                          }
                                        });
                                      },
                                      child: Container(
                                        width: 54,
                                        height: 54,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Colors.white,
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withValues(
                                                alpha: 0.25,
                                              ),
                                              blurRadius: 12,
                                              offset: const Offset(0, 4),
                                            ),
                                          ],
                                        ),
                                        child: const Icon(
                                          Icons.play_arrow_rounded,
                                          color: Colors.black87,
                                          size: 34,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  double get panelWidth =>
      MediaQuery.of(context).size.width * _panelWidthFraction;
  bool _isLoading = false;
  StreamSubscription<String>? _aiReplySub;
  bool _showFanPanel = false;
  late AnimationController _fanPanelAnimController;
  late Animation<double> _fanPanelFadeAnim;
  late Animation<Offset> _fanPanelSlideAnim;
  late AnimationController _inputAnimController;
  late Animation<double> _inputExpandAnimation;
  // 不能用 late：initState 中 _loadPromptSettings() 会先于赋值读取它，
  // 触发 LateInitializationError。直接初始化为 null 更安全，
  // 且全项目已按可空类型使用该字段。
  CharacterCard? _currentCharacter;
  final ScrollController _scrollController = ScrollController();

  /// 状态变化通知队列（4.3b）。
  ///
  /// 弹窗堆叠逐个确认、浮窗向上顶最多 5 个、弹窗全部清空才放浮窗——
  /// 编排规则在 StatusNotificationQueue 里。
  final StatusNotificationQueue _notificationQueue =
      StatusNotificationQueue();

  /// 会话副本的版本号。
  ///
  /// `_sessionState` 是原地修改的，对象身份不变，
  /// 运行时视图靠 `identical` 判断不出变化。每次写入后 +1 强制它刷新。
  int _sessionVersion = 0;
  bool _inputExpanded = false;
  // 键盘弹出/收起时用来判断视口是否变化。见 didChangeDependencies。
  double _lastKeyboardInset = 0.0;
  // 键盘上升期间持续把列表钉在底部的定时器（键盘动画有过程，单次跳转不够）。
  Timer? _keyboardFollowTimer;
  int _editingIndex = -1;
  String _editingOriginalContent = '';

  int _estimateTokens() {
    int totalChars = 0;
    for (final msg in _messages) {
      totalChars += (msg['content'] as String?)?.length ?? 0;
    }
    // 粗略估算：每 2 个字符 ≈ 1 token
    return (totalChars / 2).ceil();
  }

  String _displayCharacterName(String? name) {
    final raw = name?.trim() ?? '';
    if (raw.isEmpty) return '聊天';

    // 控制最大显示字符数，避免极长名字影响布局。
    // 中文、英文都按字符数简单截断。
    const maxChars = 10;

    if (raw.characters.length <= maxChars) return raw;

    return '${raw.characters.take(maxChars).toString()}…';
  }

  UserProfile _currentUser = UserProfile();

  Future<void> _cancelAiReply({bool updateState = true}) async {
    await _aiReplySub?.cancel();
    _aiReplySub = null;

    if (updateState && mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadUser() async {
    // 头像可能刚被换过，存在性缓存要作废重来。
    _invalidateFileExistsCache();
    final globalUser = await UserService.getUser();
    if (_currentCharacter != null) {
      // 重新从数据库读取角色数据，确保获取最新设定
      final allChars = await DatabaseService.getAllCharacters();
      final updatedCharData = allChars.firstWhere(
        (c) => c['id'] == _currentCharacter!.id,
        orElse: () => <String, dynamic>{},
      );
      if (updatedCharData.isNotEmpty) {
        _currentCharacter = CharacterCard(
          id: updatedCharData['id'] as String,
          name: updatedCharData['name'] as String,
          avatar: updatedCharData['avatar'] as String? ?? '',
          cardImagePath: updatedCharData['card_image_path'] as String? ?? '',
          description: updatedCharData['description'] as String? ?? '',
          systemPrompt: updatedCharData['system_prompt'] as String? ?? '',
          userName: updatedCharData['user_name'] as String? ?? '',
          userAvatar: updatedCharData['user_avatar'] as String? ?? '',
          backgroundId: updatedCharData['background_id'] as String? ?? '',
          worldBookId: updatedCharData['world_book_id'] as String? ?? '',
          userDetailSetting:
              updatedCharData['user_detail_setting'] as String? ?? '',
          cardType: updatedCharData['card_type'] as String? ?? 'character',
          entriesJson: updatedCharData['entries_json'] as String? ?? '[]',
          openingGreetings:
              updatedCharData['opening_greetings'] as String? ?? '[]',
          metaJson: updatedCharData['meta_json'] as String? ?? '{}',
        );
      }

      final localName = _currentCharacter!.userName;
      final localAvatar = _currentCharacter!.userAvatar;
      final localDetail = _currentCharacter!.userDetailSetting;

      final protagonistName =
      ProtagonistSettingUtils.getProtagonistName(_currentCharacter!);

      final protagonistDetail =
      ProtagonistSettingUtils.formatProtagonistDetail(_currentCharacter!);

      final effectiveName = localName.isNotEmpty
          ? localName
          : protagonistName.isNotEmpty
          ? protagonistName
          : globalUser.name;

      final effectiveAvatar = localAvatar.isNotEmpty
          ? localAvatar
          : globalUser.avatarPath;

      final effectiveDetail = localDetail.isNotEmpty
          ? localDetail
          : protagonistDetail.isNotEmpty
          ? protagonistDetail
          : '';

      _currentUser = UserProfile(
        name: effectiveName,
        avatarPath: effectiveAvatar,
      );

      _dynamicUserDetail = effectiveDetail.isNotEmpty ? effectiveDetail : null;

      setState(() {});
      return;
    }
    _currentUser = globalUser;
    _dynamicUserDetail = null;
    setState(() {});
  }

  bool _isLatestAiMessage(int index) {
    if (index < 0 || index >= _messages.length) return false;
    final msg = _messages[index];
    if (msg['role'] != 'assistant') return false;
    // 从后往前找第一个 assistant
    for (int i = _messages.length - 1; i >= 0; i--) {
      if (_messages[i]['role'] == 'assistant') {
        return i == index;
      }
    }
    return false;
  }

  bool _isLatestUserMessage(int index) {
    if (index < 0 || index >= _messages.length) return false;
    final msg = _messages[index];
    if (msg['role'] != 'user') return false;
    for (int i = _messages.length - 1; i >= 0; i--) {
      if (_messages[i]['role'] == 'user') {
        return i == index;
      }
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _guidePhase = widget.startGuide
        ? _ChatGuidePhase.chat
        : _ChatGuidePhase.none;

    UserService.versionNotifier.addListener(_onGlobalUserChanged);
    PromptSettingsService.versionNotifier.addListener(_onPromptSettingsChanged);
    BackgroundService.versionNotifier.addListener(_onBackgroundChanged);
    _loadPromptSettings();
    // 先同步吃一口缓存，保证首帧就有背景（见 _seedBackgroundFromCache）。
    _seedBackgroundFromCache();
    // 再异步校准一次，覆盖缓存未预热 / 数据刚被改过的情况。
    _loadBackground();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    // 抽屉动画：**只在跨越结构性阈值时**才整树重建。
    //
    // 聊天主体（750+ 行）已经用 AnimatedBuilder 隔离，位移本身不需要
    // setState。但 build 里还有两处依赖动画值的**条件渲染**——
    // 输入栏的 `if (_animController.value < 0.1)` 和状态栏的
    // `ignoring / opacity`。前者决定 widget 存不存在，无法靠
    // AnimatedBuilder 局部化，必须重建整棵树。
    //
    // 于是只在 0.1 / 0.5 这两个阈值被跨过时才 setState：
    // 一次 300ms 的抽屉动画约 18 帧，原本 18 次全树重建，
    // 现在最多 4 次（进出各跨两个阈值）。
    _animController.addListener(() {
      if (!mounted) return;
      final v = _animController.value;
      final bucket = v < 0.1 ? 0 : (v < 0.5 ? 1 : 2);
      if (bucket == _animBucket) return;
      _animBucket = bucket;
      setState(() {});
    });
    _inputAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _inputExpandAnimation = CurvedAnimation(
      parent: _inputAnimController,
      curve: Curves.easeInOut,
    );
    // 这里**故意不加** setState 监听。
    //
    // 输入框展开动画的两个消费点（见 build 里 4800 行附近）都已经
    // 各自套了 AnimatedBuilder，会自行订阅这个 controller 并只重建
    // 自己那一小块。再挂一个全局 setState 等于让 AnimatedBuilder
    // 白圈——整棵 1285 行的聊天树仍会每帧重建。
    _detailAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _detailScaleAnim = CurvedAnimation(
      parent: _detailAnimController,
      curve: Curves.easeOutBack,
    );
    _detailFadeAnim = CurvedAnimation(
      parent: _detailAnimController,
      curve: Curves.easeOut,
    );
    _fanSnapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _fanPanelAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
      reverseDuration: const Duration(milliseconds: 260),
    );

    _fanPanelFadeAnim = CurvedAnimation(
      parent: _fanPanelAnimController,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );

    _fanPanelSlideAnim = Tween<Offset>(
      begin: const Offset(0, 1.0),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _fanPanelAnimController,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeInCubic,
      ),
    );
    _fanSnapController.addListener(() {
      if (!mounted) return;
      setState(() {
        _fanOffset =
            _fanSnapStart +
            (_fanSnapTarget - _fanSnapStart) * _fanSnapController.value;
      });
    });

    _currentCharacter = widget.character;

    // ✅ 修复：使用 Future.microtask 确保异步初始化完成
    if (_currentCharacter == null) {
      Future.microtask(() async {
        String? lastId;
        try {
          lastId = await DatabaseService.getLastActiveCharacterId();
        } catch (_) {}
        final all = await DatabaseService.getAllCharacters();
        Map<String, dynamic>? charData;
        if (lastId != null) {
          charData = all.cast<Map<String, dynamic>?>().firstWhere(
            (c) => c?['id'] == lastId,
            orElse: () => null,
          );
        }
        charData ??= all.isNotEmpty ? all.first : null;
        if (charData != null) {
          final newChar = CharacterCard(
            id: charData['id'] as String,
            name: charData['name'] as String,
            avatar: charData['avatar'] as String? ?? '',
            cardImagePath: charData['card_image_path'] as String? ?? '',
            description: charData['description'] as String? ?? '',
            systemPrompt: charData['system_prompt'] as String? ?? '',
            userName: charData['user_name'] as String? ?? '',
            userAvatar: charData['user_avatar'] as String? ?? '',
            userDetailSetting: charData['user_detail_setting'] as String? ?? '',
            cardType: charData['card_type'] as String? ?? 'character',
            entriesJson: charData['entries_json'] as String? ?? '[]',
            openingGreetings: charData['opening_greetings'] as String? ?? '[]',
            metaJson: charData['meta_json'] as String? ?? '{}',
          );
          await _setCurrentCharacter(newChar);
        }
      });
    } else {
      Future.microtask(() async {
        await _setCurrentCharacter(widget.character);
      });
    }
  }

  Future<void> _ensureOpeningGreetingForEmptyHistory() async {
    if (_currentCharacter == null) return;

    // 以数据库为准，避免 UI 状态误判
    final existingMessages =
    await DatabaseService.getMessages(_currentCharacter!.id);
    // 只在完全没有历史消息时插入开场白
    if (existingMessages.isNotEmpty) return;

    final greetings = _getCurrentGreetings();
    if (greetings.isEmpty) return;

    final firstGreeting = greetings.first.content.trim();
    if (firstGreeting.isEmpty) return;

    final newId = await DatabaseService.insertMessage(
      characterId: _currentCharacter!.id,
      role: 'assistant',
      content: firstGreeting,
    );

    if (!mounted) return;

    setState(() {
      _messages.clear();
      _messages.add({
        'id': newId.toString(),
        'role': 'assistant',
        'content': firstGreeting,
        'version': 1,
      });
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottomWhenReady();
    });
  }

  void _openFanPanel() {
    if (_showFanPanel) return;

    _loadSelectableCharacters();

    setState(() {
      _showFanPanel = true;
    });

    _fanPanelAnimController.forward(from: 0);
  }

  Future<void> _closeFanPanel() async {
    if (!_showFanPanel) return;

    await _fanPanelAnimController.reverse();

    if (!mounted) return;

    setState(() {
      _showFanPanel = false;
      _showCardDetail = false;
      _detailCard = null;
    });
  }

  Future<void> _setCurrentCharacter(CharacterCard? char) async {
    await _cancelAiReply(updateState: false);
    _isLoading = false;

    if (char == null) return;

    _currentCharacter = char;
    // 新角色的会话副本还没读，先关掉开场白判定的闸门。
    // 不做这一步，下面那次 setState 会拿上一个角色的
    // _openingDismissed 去判断新角色。
    _sessionReady = false;

    // 会话副本要**第一个**读。
    //
    // 闸门只依赖它，而它只是一条 `where id = ?` 的单行查询；
    // 排在 _loadUser（全表扫描）后面的话，开场白要等整条链跑完才敢上屏，
    // 表现就是「点进角色后白等半秒开场白才出来」。
    // 反过来说，先读它就能在第一帧之前定下「这张卡该不该显示开场白」，
    // 既不闪也不等。
    await _loadSessionState();

    await _loadPromptSettings();

    setState(() {
      _messages.clear();
    });

    // 先加载历史
    await _loadHistory();

    // 这里一定要 await。
    // 因为 _loadUser() 里会重新从数据库刷新 _currentCharacter，
    // 包括 openingGreetings、entriesJson 等最新字段。
    await _loadUser();

    // _loadUser 会用数据库里的最新数据重建 _currentCharacter，
    // meta 里的 UI 方案可能刚在编辑器里被改过。
    // 判定缓存是按角色 id 存的，id 没变就不会自动重算，
    // 所以这里要手动失效一次——_loadSessionState 里那次是在刷新之前，
    // 拦不住这种「同一张卡但内容变了」的情况。
    _invalidateAssemblyCaches();

    // 同理，刷新后的卡可能带上了新的状态栏字段定义。
    // 只补缺失键，重复调用无副作用。
    _ensureStatusValuesInitialized();

    // 角色可能绑定了自己的背景，按最新的 backgroundId 再校正一次。
    // 值没变时 _loadBackground 内部会跳过 setState。
    await _loadBackground();

    // 如果没有历史记录，则自动插入开场白
    await _ensureOpeningGreetingForEmptyHistory();

    if (mounted) setState(() {});
  }

  String _buildBehaviorUseReminderPrompt() {
    return '涉及动作、距离、触摸、身体互动、语气、情绪和关系推进时，必须自然考虑角色与用户的身体差异、性格、关系、状态和背景设定。';
  }

  /// 历史后注入文本（post_history_instructions）。
  ///
  /// 与酒馆的 PHI 一致：放在对话历史「之后」，作为最末尾的强约束指令，
  /// 比开头 system 更不容易在长对话中被淡忘。来源于角色卡元信息。
  /// 返回空字符串表示无需注入。
  String _buildPostHistoryInstructions() {
    if (!_promptSettings.injectPostHistoryInstructions) return '';
    final raw = _currentCharacter?.meta.postHistoryInstructions ?? '';
    if (raw.trim().isEmpty) return '';
    return _renderPromptTemplate(raw).trim();
  }

  /// 在请求消息列表末尾追加历史后注入（如有）。返回新的列表，不修改入参。
  List<Map<String, String>> _withPostHistoryInstructions(
    List<Map<String, String>> messages,
  ) {
    final out = [...messages];

    final phi = _buildPostHistoryInstructions();
    if (phi.isNotEmpty) {
      out.add({'role': 'system', 'content': phi});
    }

    // 更新格式约束放在对话历史之后。
    // 放在 system prompt 开头时，长对话中模型经常忽略它，
    // 表现为「正文里说已修改，但不输出标签块」，状态实际纹丝不动。
    final uiItems = _collectUIChannelPromptItems();
    final reminders = <String>[];

    // 状态栏字段（好感度 / 心情等）。这是最常用的一条路径。
    final statusFields = _currentCharacter?.meta.statusBarFields ?? const [];
    if (statusFields.isNotEmpty) {
      final policies =
          DataChannelPromptBuilder.collectStatusFieldPolicies(uiItems);
      final statusFormat = StatusBarEngine.buildUpdateFormatInstruction(
        statusFields,
        _sessionState.statusValues,
        policies: policies,
      );
      if (statusFormat.isNotEmpty) {
        out.add({'role': 'system', 'content': statusFormat});
        final reminder = StatusBarEngine.buildTurnReminder(
          statusFields,
          policies: policies,
        );
        if (reminder.isNotEmpty) reminders.add(reminder);
      }
    }

    // 会话变量类数据通道。
    final uiFormat =
        DataChannelPromptBuilder.buildUpdateFormatInstruction(uiItems);
    if (uiFormat.isNotEmpty) {
      out.add({'role': 'system', 'content': uiFormat});
      final reminder = DataChannelPromptBuilder.buildTurnReminder(uiItems);
      if (reminder.isNotEmpty) reminders.add(reminder);
    }

    // 在最后一条用户消息尾部贴极短提醒。
    // 部分模型在沉浸式扮演时会忽略系统层要求，紧贴用户消息的提醒
    // 是成本最低的补强；足够短，不影响正文质量。
    if (reminders.isNotEmpty) {
      final lastUserIndex = out.lastIndexWhere((msg) => msg['role'] == 'user');
      if (lastUserIndex != -1) {
        final original = out[lastUserIndex]['content'] ?? '';
        out[lastUserIndex] = {
          'role': 'user',
          'content': '$original\n\n${reminders.join('\n')}',
        };
      }
    }

    return out;
  }

  Future<String> _buildFinalSystemPrompt() async {
    String systemPrompt =
        _currentCharacter?.systemPrompt ?? '你是忠于用户的助手。';

    if (_promptSettings.injectRoleplayRules) {
      final roleplayRules = _buildRoleplayRules();
      if (roleplayRules.isNotEmpty) {
        systemPrompt += '\n\n[角色扮演规则]\n$roleplayRules';
      }
    }
    // 注入世界书设定
    if (_currentCharacter?.worldBookId != null &&
        _currentCharacter!.worldBookId.isNotEmpty) {
      if (_cachedWorldBookId != _currentCharacter!.worldBookId) {
        final worldBooks = await DatabaseService.getAllWorldBooks();
        final worldBook = worldBooks.firstWhere(
          (wb) => wb['id'] == _currentCharacter!.worldBookId,
          orElse: () => <String, dynamic>{},
        );
        if (worldBook.isNotEmpty) {
          final entriesJson = worldBook['entries_json'] as String? ?? '[]';
          try {
            final list = jsonDecode(entriesJson) as List;
            _cacheWorldBookEntries(
              list.map((e) => WorldBookEntry.fromJson(e)).toList(),
            );
          } catch (_) {
            _cacheWorldBookEntries([]);
          }
        }
      }

      final activeEntries =
      _getActiveWorldBookEntries(_promptSettings.worldBookScanDepth);
      if (activeEntries.isNotEmpty) {
        // 按插入位置分组：before_char 注入到角色设定之前（此处），
        // after_char 暂存，注入到角色设定之后。
        final beforeEntries =
            activeEntries.where((e) => e.position != 'after_char').toList();
        _pendingAfterCharWorldEntries = activeEntries
            .where((e) => e.position == 'after_char')
            .toList();

        if (beforeEntries.isNotEmpty) {
          final entryText = beforeEntries
              .map((e) => '【${e.title}】\n${e.content}')
              .join('\n\n');
          systemPrompt += '\n\n[世界设定]\n$entryText';
        }
      } else {
        _pendingAfterCharWorldEntries = [];
      }
    } else {
      _pendingAfterCharWorldEntries = [];
    }

    // 注入用户名称
    if (_currentUser.name.isNotEmpty && _currentUser.name != '我') {
      systemPrompt += '\n\n[当前用户名称]\n${_currentUser.name}';
    }

    // 每轮注入核心条目
    final coreEntries = _getEnabledPromptEntries(includeDetailed: false);
    final coreEntryPrompt = _buildEntriesPrompt(coreEntries);
    if (coreEntryPrompt.isNotEmpty) {
      systemPrompt += '\n\n[核心角色设定]\n$coreEntryPrompt';
    }

    // 世界书 position=after_char 的命中条目，注入到角色设定之后。
    if (_pendingAfterCharWorldEntries.isNotEmpty) {
      final afterText = _pendingAfterCharWorldEntries
          .map((e) => '【${e.title}】\n${e.content}')
          .join('\n\n');
      systemPrompt += '\n\n[世界设定·补充]\n$afterText';
    }

// 每轮注入极短连续性提醒
    if (_promptSettings.injectContinuityReminder) {
      final continuityReminder = _buildContinuityReminderPrompt();
      if (continuityReminder.isNotEmpty) {
        systemPrompt += '\n\n[连续性提醒]\n$continuityReminder';
      }
    }

    final shouldInjectFullDetail = _shouldInjectFullDetailPrompt();
    final shouldInjectSummary = _shouldInjectSummaryPrompt();

// 小周期注入摘要设定。
// 如果本轮已经注入完整详细设定，则跳过摘要，避免重复。
    if (shouldInjectSummary && !shouldInjectFullDetail) {
      final summaryPrompt = _buildPeriodicSummaryPrompt();
      if (summaryPrompt.isNotEmpty) {
        systemPrompt += '\n\n[周期性摘要设定]\n$summaryPrompt';
      }
    }

// 大周期注入完整详细设定
    if (shouldInjectFullDetail) {
      final detailEntries = _getEnabledPromptEntries(includeDetailed: true);
      final detailPrompt = _buildEntriesPrompt(detailEntries);

      if (detailPrompt.isNotEmpty) {
        systemPrompt += '\n\n[周期性完整设定]\n$detailPrompt';
      }

      final behaviorReminder = _buildBehaviorUseReminderPrompt();
      if (behaviorReminder.isNotEmpty) {
        systemPrompt += '\n\n[行为使用提醒]\n$behaviorReminder';
      }
    }

    // 状态栏：注入当前状态值 + 变化回报格式约定（LLM 只给变化量，引擎算账）。
    //
    // 状态字段是 SSOT：它可能同时被状态栏和 UI 数据通道引用，
    // 但只能有一套注入与解析，否则模型会看到两个标签、两套格式而无所适从。
    // 因此这类字段统一由状态栏负责，通道里配置的读写策略传进去约束它。
    final uiChannelItems = _collectUIChannelPromptItems();
    if (_currentCharacter != null) {
      final fields = _currentCharacter!.meta.statusBarFields;
      if (fields.isNotEmpty) {
        final injection = StatusBarEngine.buildInjection(
          fields,
          _sessionState.statusValues,
          policies: DataChannelPromptBuilder.collectStatusFieldPolicies(
            uiChannelItems,
          ),
        );
        if (injection.isNotEmpty) {
          systemPrompt += '\n\n$injection';
        }
      }
    }

    // A9.6-3：UI 数据通道注入（仅会话变量部分，状态字段已由上面接管）。
    if (uiChannelItems.isNotEmpty) {
      final injection = DataChannelPromptBuilder.buildInjection(uiChannelItems);
      if (injection.isNotEmpty) {
        systemPrompt += '\n\n$injection';
      }
    }

    // 统一渲染占位符：description / 条目 / 世界书等内容里的 {{char}} {{user}}
    // 在发送给模型前替换为真实角色名与用户名（与酒馆行为一致）。
    // 对已渲染过的片段（规则 / 连续性提醒等）是幂等的。
    return _renderPromptTemplate(systemPrompt);
  }

  /// 真实键盘高度（未被 Scaffold 消费）。见 build 里的赋值处说明。
  double _rawKeyboardInset = 0.0;

  /// 抽屉动画所处的「结构区间」：0 = 收起(<0.1)，1 = 过渡，2 = 展开(>0.5)。
  /// 只有区间变化才需要整树重建，见 initState 里的监听器。
  int _animBucket = 0;

  /// 文件存在性缓存。
  ///
  /// `File(path).existsSync()` 是**同步磁盘 IO**。头像那几处写在 build 里，
  /// 且同一个路径要判 2~3 次（backgroundColor / backgroundImage / child
  /// 各判一次）。聊天页有多个 AnimationController 在 setState，抽屉、
  /// 输入框展开等动画期间每帧都会重跑整棵树，于是每帧几十次 stat 调用。
  ///
  /// 头像文件在一次会话里不会凭空消失，缓存结果即可。换头像走的是
  /// UserService/角色刷新，那时会调 _invalidateFileExistsCache()。
  static final Map<String, bool> _fileExistsCache = {};

  bool _fileExists(String path) {
    if (path.isEmpty) return false;
    final hit = _fileExistsCache[path];
    if (hit != null) return hit;
    final ok = File(path).existsSync();
    _fileExistsCache[path] = ok;
    return ok;
  }

  void _invalidateFileExistsCache() => _fileExistsCache.clear();

  /// 当前生效的背景。缓存在 state 里，**不要**在 build 里现查。
  ///
  /// 原实现是 `FutureBuilder(future: _getCurrentBackground())` 直接写在
  /// build 里，两个后果：
  /// 1. future 每次 build 都新建一个，snapshot 先回到 waiting（data == null），
  ///    于是先铺一帧默认的浅蓝→浅紫渐变，等查询回来再换成真背景——就是肉眼
  ///    看到的「进聊天页背景闪一下」。
  /// 2. 聊天页有好几个 AnimationController 的 listener 在 setState，
  ///    动画期间每帧都会重跑一次数据库查询 + SharedPreferences 读取。
  BackgroundCard? _background;

  /// 是否已经完成过至少一次背景查询。
  /// 用来区分「还没查」和「查完了确实没有背景」——前者不能画默认渐变。
  bool _backgroundLoaded = false;

  void _onBackgroundChanged() {
    _loadBackground();
  }

  /// 从 BackgroundService 的内存缓存同步取一次背景。
  ///
  /// main() 里 `warmUp()` 已经预热过，正常路径下这里必定命中，
  /// 于是聊天页**第一帧**就有正确背景，不存在任何空窗。
  /// 只有缓存意外未就绪（预热失败）才会落空，交给异步路径补。
  void _seedBackgroundFromCache() {
    if (!BackgroundService.isWarm) return;
    final boundId = widget.character?.backgroundId ?? '';
    final bg = boundId.isNotEmpty
        ? (BackgroundService.peekById(boundId) ??
            BackgroundService.peekCurrent())
        : BackgroundService.peekCurrent();
    if (bg == null) return;
    _background = bg;
    _backgroundLoaded = true;
  }

  /// 查一次背景并写进 state。
  ///
  /// 重新加载期间**保留**上一次的值（不先置 null），这样切换背景、
  /// 编辑背景库回来都不会中间闪一帧默认渐变。
  Future<void> _loadBackground() async {
    final bg = await _getCurrentBackground();
    if (!mounted) return;
    // 同一张背景就不 setState 了：这个方法会被角色切换和 versionNotifier
    // 各触发一次，无谓重建会连带整棵聊天树。
    if (_backgroundLoaded &&
        bg?.id == _background?.id &&
        bg?.colorValue == _background?.colorValue &&
        bg?.originalImagePath == _background?.originalImagePath) {
      return;
    }
    setState(() {
      _background = bg;
      _backgroundLoaded = true;
    });
  }

  Future<BackgroundCard?> _getCurrentBackground() async {
    // 优先使用当前角色的独立背景
    if (_currentCharacter?.backgroundId != null &&
        _currentCharacter!.backgroundId.isNotEmpty) {
      // 缓存就绪时直接同步命中，省掉一次建表检查 + 全表查询。
      if (BackgroundService.isWarm) {
        final hit =
            BackgroundService.peekById(_currentCharacter!.backgroundId);
        if (hit != null) return hit;
        return BackgroundService.peekCurrent();
      }

      final all = await BackgroundService.getAll();

      for (final bg in all) {
        if (bg.id == _currentCharacter!.backgroundId) {
          return bg;
        }
      }

      // 如果角色绑定的背景不存在，回退到全局背景
      return BackgroundService.getCurrent();
    }

    // 否则使用全局背景
    return BackgroundService.getCurrent();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // 键盘弹出时保持最后一条气泡可见。
    //
    // 普通聊天页保留 resizeToAvoidBottomInset:true（输入框要跟着键盘上移；
    // scene / 开场白接管时才关掉，见 build 里的说明），
    // 于是视口高度减少了 keyboardInset，但 ListView 的 pixels 不变、
    // maxScrollExtent 反而增大——原本贴底的气泡就被顶到视口之下，
    // 表现为「被输入法挡住」。
    //
    // 只在「原本就在底部附近」时才补滚，用户手动往上翻历史时不打扰。
    // 键盘是带动画上升的，inset 会连续变化好几帧，
    // 单次 jumpTo 会被后续帧重新甩下去，所以用一个短定时器持续跟随。
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    if ((inset - _lastKeyboardInset).abs() > 1.0) {
      final bool opening = inset > _lastKeyboardInset;
      _lastKeyboardInset = inset;
      if (opening) _startKeyboardFollow();
    }
  }

  /// 在键盘上升的动画期间持续把列表钉在底部。
  void _startKeyboardFollow() {
    if (!_scrollController.hasClients) return;
    // 只有原本贴着底部才跟随；用户正在翻历史时不要抢滚动。
    final pos = _scrollController.position;
    if (pos.maxScrollExtent - pos.pixels > 120) return;

    _keyboardFollowTimer?.cancel();
    int ticks = 0;
    _keyboardFollowTimer = Timer.periodic(
      const Duration(milliseconds: 16),
      (timer) {
        // 约 400ms，覆盖各平台键盘弹出动画时长。
        if (!mounted || ticks++ > 25 || !_scrollController.hasClients) {
          timer.cancel();
          _keyboardFollowTimer = null;
          return;
        }
        final p = _scrollController.position;
        if (p.pixels < p.maxScrollExtent) {
          _scrollController.jumpTo(p.maxScrollExtent);
        }
      },
    );
  }

  @override
  void dispose() {
    _keyboardFollowTimer?.cancel();
    _notificationQueue.dispose();
    _aiReplySub?.cancel();
    UserService.versionNotifier.removeListener(_onGlobalUserChanged);
    PromptSettingsService.versionNotifier.removeListener(_onPromptSettingsChanged);
    BackgroundService.versionNotifier.removeListener(_onBackgroundChanged);
    _scrollController.dispose();
    _inputAnimController.dispose();
    _animController.dispose();
    _msgController.dispose();
    _detailAnimController.dispose();
    _inertiaTicker?.stop();
    _inertiaTicker?.dispose();
    _fanSnapController.dispose();
    _ballTuckTimer?.cancel();
    super.dispose();

  }

  Future<Map<String, bool>?> _showClearHistoryDialog() {
    bool resetUserSetting = false;

    return showDialog<Map<String, bool>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('清空历史'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('确定要清空当前角色的聊天记录吗？'),
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    value: resetUserSetting,
                    onChanged: (v) {
                      setDialogState(() {
                        resetUserSetting = v ?? false;
                      });
                    },
                    title: const Text('同时重置用户设定为角色卡默认'),
                    subtitle: const Text(
                      '勾选后会清空当前卡的用户覆盖设定，重新使用角色卡中的主角设定。',
                      style: TextStyle(fontSize: 12),
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, {
                    'clear': true,
                    'resetUserSetting': resetUserSetting,
                  }),
                  child: const Text('清空'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _clearHistoryWithOptions() async {
    if (_currentCharacter == null) return;

    final result = await _showClearHistoryDialog();
    if (result == null || result['clear'] != true) return;

    final resetUserSetting = result['resetUserSetting'] == true;

    await DatabaseService.deleteMessagesByCharacterId(_currentCharacter!.id);

    // 清空会话副本覆盖层：界面交互 / 状态栏写入的变量随历史一并清除，
    // 使 Prompt 回到角色卡母版（实现「改写后可还原」）。
    await DatabaseService.clearSessionState(_currentCharacter!.id);
    _sessionState = SessionState();
    // 会话副本重建 → 开场白应重新出现。
    _openingDismissed = false;

    if (resetUserSetting) {
      await DatabaseService.updateCharacter({
        'id': _currentCharacter!.id,
        'user_name': '',
        'user_avatar': '',
        'user_detail_setting': '',
      });

      _currentCharacter!.userName = '';
      _currentCharacter!.userAvatar = '';
      _currentCharacter!.userDetailSetting = '';

      await _loadUser();
    }

    setState(() {
      _messages.clear();
    });

    // 关掉设置面板再走后续（用户反馈）。
    //
    // 清空会话副本会让 openingUIDismissed 复位，开场白 UI 立刻重现——
    // 而设置页还开着，两层叠在一起，玩家看到的是「设置页背后弹出一个
    // 关不掉的开场白」。开场白本来就要求先确认再操作，
    // 这时候把设置页留着没有意义。
    if (_showFanPanel) _closeFanPanel();
    _closePanel();

    await _ensureOpeningGreetingForEmptyHistory();
  }

  // ===== 状态栏 UI =====

  // 折叠长条上每侧最多固定的字段数（左 / 右各自上限）。
  static const int _statusPinnedMax = 3;

  List<StatusBarField> get _statusFields {
    final list = _currentCharacter?.meta.statusBarFields ??
        const <StatusBarField>[];
    final sorted = [...list]..sort((a, b) => a.order.compareTo(b.order));
    return sorted;
  }

  String _statusValueOf(StatusBarField f) =>
      _sessionState.statusValues[f.id] ?? f.initialValue;

  String _numText(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toString();
  }

  /// 进度（0~1），仅当数值字段设了上下限时有值。
  double? _statusProgress(StatusBarField f) {
    if (!f.isNumber || f.minValue == null || f.maxValue == null) return null;
    final v = double.tryParse(_statusValueOf(f));
    final range = f.maxValue! - f.minValue!;
    if (v == null || range <= 0) return null;
    return ((v - f.minValue!) / range).clamp(0.0, 1.0);
  }

  List<StatusBarField> get _pinnedLeftFields =>
      _statusFields.where((f) => f.isPinnedLeft).take(_statusPinnedMax).toList();
  List<StatusBarField> get _pinnedRightFields =>
      _statusFields.where((f) => f.isPinnedRight).take(_statusPinnedMax).toList();

  void _showStatusPinFullToast(String sideLabel) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$sideLabel侧最多固定 $_statusPinnedMax 条，请先取消一条再添加。'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _toggleStatusBarExpanded() {
    if (_statusFields.isEmpty) return;
    setState(() => _statusBarExpanded = !_statusBarExpanded);
  }

  void _collapseStatusBar() {
    if (_statusBarExpanded) setState(() => _statusBarExpanded = false);
  }

  /// 设置某字段的固定方向（none/left/right），并持久化（属于卡片设定）。
  Future<void> _setStatusPinSide(StatusBarField f, String side) async {
    if (_currentCharacter == null) return;
    // 限制：每侧最多 _statusPinnedMax 个。已满时不允许再固定到该侧。
    if (side == 'left' && !f.isPinnedLeft &&
        _statusFields.where((e) => e.isPinnedLeft).length >= _statusPinnedMax) {
      _showStatusPinFullToast('左');
      return;
    }
    if (side == 'right' && !f.isPinnedRight &&
        _statusFields.where((e) => e.isPinnedRight).length >= _statusPinnedMax) {
      _showStatusPinFullToast('右');
      return;
    }
    final meta = _currentCharacter!.meta;
    final idx = meta.statusBarFields.indexWhere((e) => e.id == f.id);
    if (idx < 0) return;
    meta.statusBarFields[idx] = meta.statusBarFields[idx].copyWith(pinSide: side);
    _currentCharacter!.applyMeta(meta);
    await DatabaseService.updateCharacter({
      'id': _currentCharacter!.id,
      'meta_json': _currentCharacter!.metaJson,
    });
    if (mounted) setState(() {});
  }

  /// 状态栏统一材质（毛玻璃 + 半透明白），长条与详情块共用。
  Widget _statusGlass({required Widget child, double radius = 14}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(60),
            borderRadius: BorderRadius.circular(radius),
          ),
          child: child,
        ),
      ),
    );
  }

  /// 固定长条里的迷你块：无边框无底色。名称在上（极小浅色），
  /// 下面是数值/文本，或一条很细的带百分比迷你进度条。
  Widget _buildStripChip(StatusBarField f, {required bool alignRight}) {
    final value = _statusValueOf(f);
    final progress = _statusProgress(f);
    final cross =
        alignRight ? CrossAxisAlignment.end : CrossAxisAlignment.start;

    final nameWidget = Text(
      f.name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 8, color: Colors.black38, height: 1.1),
    );

    final Widget valueLine;
    if (progress != null) {
      // 迷你进度条 + 百分比（无底色，仅细条）。
      // 用 Flexible 让进度条可压缩，避免在窄空间内溢出。
      valueLine = Row(
        mainAxisSize: MainAxisSize.max,
        mainAxisAlignment:
            alignRight ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 4,
                backgroundColor: Colors.black.withAlpha(28),
                valueColor: AlwaysStoppedAnimation(
                    Theme.of(context).primaryColor.withAlpha(210)),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '${(progress * 100).round()}%',
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
                height: 1.1),
          ),
        ],
      );
    } else {
      valueLine = Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
            height: 1.1),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: cross,
      children: [
        nameWidget,
        const SizedBox(height: 1),
        valueLine,
      ],
    );
  }

  /// 固定长条内容（左固定字段靠左，右固定字段靠右）。不含毛玻璃外壳。
  Widget _buildStatusStrip() {
    final left = _pinnedLeftFields;
    final right = _pinnedRightFields;
    final hasAny = left.isNotEmpty || right.isNotEmpty;

    return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        child: !hasAny
            ? Center(
                child: Text(
                  '状态栏 · 点击展开',
                  style: TextStyle(
                      fontSize: 11, color: Colors.black.withAlpha(120)),
                ),
              )
            : Row(
                children: [
                  // 左侧固定
                  Expanded(
                    child: Row(
                      children: [
                        for (int i = 0; i < left.length; i++)
                          Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(
                                  right: i == left.length - 1 ? 0 : 10),
                              child: _buildStripChip(left[i],
                                  alignRight: false),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 56), // 中间留出较大空白，内容不靠近中部
                  // 右侧固定
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        for (int i = 0; i < right.length; i++)
                          Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(left: i == 0 ? 0 : 10),
                              child: _buildStripChip(right[i],
                                  alignRight: true),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
      );
  }

  /// 详情区：块状网格内容，一个块 = 一个字段。不含毛玻璃外壳。
  /// 每行 3 列等分，撑满整行宽度（避免右侧留白）。
  Widget _buildStatusDetailGrid() {
    final fields = _statusFields;
    if (fields.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      // 顶部留一点和长条隔开的呼吸感，但仍在同一块毛玻璃内（视觉相连）。
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 10),
      child: LayoutBuilder(
        builder: (context, c) {
          const cols = 3;
          const spacing = 8.0;
          final blockW = (c.maxWidth - spacing * (cols - 1)) / cols;
          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: [
              for (final f in fields)
                SizedBox(width: blockW, child: _buildStatusBlock(f)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatusBlock(StatusBarField f) {
    final value = _statusValueOf(f);
    final progress = _statusProgress(f);

    // 字段名称（浅色小字），数值 / 文本块共用。
    final nameWidget = Text(
      f.name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 12, color: Colors.black45),
    );

    // 块主体内容（不含顶部滑块触摸区）。
    final Widget body;
    if (progress != null) {
      // 数值类：名称在上，下面是较厚进度条，进度条内显示「当前值/最大值」。
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          nameWidget,
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  height: 14,
                  width: double.infinity,
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.black12,
                    valueColor: AlwaysStoppedAnimation(
                        Theme.of(context).primaryColor.withAlpha(200)),
                  ),
                ),
                Text(
                  '$value/${_numText(f.maxValue!)}',
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      );
    } else {
      // 文本类（或无范围的数值）：名称在上，值居中显示在下，超出省略。
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          nameWidget,
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.black87),
          ),
        ],
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(110),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 顶部空白区即滑块触摸区（点 / 拖都在这块上半空白，干扰最小）。
          _PinSlider(
            pinSide: f.pinSide,
            onChanged: (side) => _setStatusPinSide(f, side),
          ),
          // 主体内容
          Padding(
            padding: const EdgeInsets.fromLTRB(9, 0, 9, 8),
            child: body,
          ),
        ],
      ),
    );
  }

  /// 状态栏整体：长条始终在顶部；展开时在其下方插入详情块网格。
  /// 同材质、无蒙版，带展开 / 收起动画。
  Widget _buildStatusBar() {
    // 长条与详情同处一块毛玻璃内：等宽、无缝隙、相连。
    return _statusGlass(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 长条（固定长度，始终显示，不被覆盖）
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggleStatusBarExpanded,
            child: _buildStatusStrip(),
          ),
          // 详情块网格（展开时出现在长条下方，同块内相连）
          // AnimatedSize 用带回弹的曲线，整体展开后有一点回弹效果。
          AnimatedSize(
            duration: const Duration(milliseconds: 340),
            curve: _statusBarExpanded
                ? Curves.easeOutBack // 展开：略微过冲再回弹
                : Curves.easeInCubic, // 收起：干脆收回
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SizeTransition(
                  sizeFactor: anim,
                  axisAlignment: -1.0,
                  child: child,
                ),
              ),
              child: _statusBarExpanded
                  ? KeyedSubtree(
                      key: const ValueKey('sb_detail'),
                      child: _buildStatusDetailGrid(),
                    )
                  : const SizedBox(
                      key: ValueKey('sb_none'), width: double.infinity),
            ),
          ),
        ],
      ),
    );
  }

  /// A11-2：执行来自 Assembly 按钮的消息操作。
  ///
  /// 作用对象固定为**最新一条 AI 消息**（用户确认），与原生气泡的
  /// 功能键一致——因此 `message_flow` 不需要引入「选中态」。
  ///
  /// 复用聊天页已有的方法，不另写一套：重生成 / 继续 / 撤回的
  /// 数据库写入、状态回滚、版本记录都已经在那些方法里处理妥当，
  /// 平行实现必然漏掉其中某一步。
  Future<void> _handleMessageAction(MessageAction action) async {
    if (_isLoading) {
      _toast('正在生成回复，请稍候');
      return;
    }

    final aiIndex = _messages.lastIndexWhere((m) => m['role'] == 'assistant');
    if (aiIndex < 0) {
      _toast('还没有可操作的回复');
      return;
    }

    switch (action) {
      case MessageAction.regenerate:
        // _regenerateMessage 内部要求前一条是 user 消息（要重发它）。
        if (aiIndex == 0 || _messages[aiIndex - 1]['role'] != 'user') {
          _toast('这条回复没有对应的提问，无法重新生成');
          return;
        }
        await _regenerateMessage(aiIndex);
      case MessageAction.continueWrite:
        await _continueMessage(aiIndex);
      case MessageAction.edit:
        await _editMessageViaDialog(aiIndex);
      case MessageAction.delete:
        await _deleteRoundFromAssembly(aiIndex);
      case MessageAction.versionPrev:
        _switchVersion(aiIndex, -1);
      case MessageAction.versionNext:
        _switchVersion(aiIndex, 1);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// 弹窗编辑消息内容。
  ///
  /// 不复用 `_startEdit`：那条路径把内容送进底部输入栏，
  /// 而 scene 接管时输入栏根本不渲染，玩家会看到「点了没反应」。
  Future<void> _editMessageViaDialog(int index) async {
    if (index < 0 || index >= _messages.length) return;
    final controller =
        TextEditingController(text: _messages[index]['content'] as String? ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑回复'),
        content: TextField(
          controller: controller,
          maxLines: 10,
          minLines: 4,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null) return;

    final text = result.trim();
    if (text.isEmpty) return;
    if (text == _messages[index]['content']) return;

    setState(() => _messages[index]['content'] = text);

    // 同步落库，否则重进聊天页就变回旧内容。
    final id = int.tryParse(_messages[index]['id']?.toString() ?? '');
    if (id != null) {
      await DatabaseService.updateMessageContent(id, text);
    }
  }

  /// 撤回最近一轮对话。
  ///
  /// `_deleteUserMessage` 的入口是 user 消息（它会连带删掉其后的 AI 回复），
  /// 而这里拿到的是 AI 消息下标，因此先往前找到本轮的提问。
  Future<void> _deleteRoundFromAssembly(int aiIndex) async {
    var userIndex = -1;
    for (var i = aiIndex; i >= 0; i--) {
      if (_messages[i]['role'] == 'user') {
        userIndex = i;
        break;
      }
    }
    if (userIndex < 0) {
      _toast('这条回复没有对应的提问，无法撤回');
      return;
    }
    await _deleteUserMessage(userIndex);
  }

  /// 切换到相邻版本。`delta` 为 -1 / +1。
  ///
  /// 只有重新生成过的消息才有多个版本；没有时给出提示而不是静默无反应——
  /// 玩家按了按钮却什么都没发生，会以为是 UI 坏了。
  void _switchVersion(int index, int delta) {
    final msg = _messages[index];
    final rawVersions = msg['versions'];
    if (rawVersions is! List || rawVersions.length < 2) {
      _toast('这条回复只有一个版本');
      return;
    }
    final versions = List<String>.from(rawVersions);
    final cur = (msg['currentVersionIndex'] as int?) ?? versions.length - 1;
    final next = cur + delta;
    if (next < 0 || next >= versions.length) {
      _toast(delta < 0 ? '已经是第一个版本' : '已经是最后一个版本');
      return;
    }

    setState(() {
      msg['currentVersionIndex'] = next;
      msg['content'] = versions[next];
      // id 要跟着切：后续的编辑 / 删除都按 id 落库，
      // 不同步会把改动写到别的版本上。
      final rawIds = msg['versionIds'];
      if (rawIds is List && next < rawIds.length) {
        msg['id'] = rawIds[next];
      }
    });
  }

  /// A10-3：伴生 UI（extra_companion）。
  ///
  /// 内嵌在 AI 消息气泡的最下方，与正文同属一个气泡容器。
  /// 这样带来两个好处（用户设计）：
  ///   - 省掉了气泡外围一套功能按钮的排布空间；
  ///   - 撤回 / 删除消息时，这条消息携带的数据记录一并消失，
  ///     不需要额外的清理逻辑。
  ///
  /// **只有最新一条 AI 消息可交互**：历史消息里的伴生 UI 仍然渲染
  /// （否则翻看历史会看到一堆空气泡），但禁止操作——
  /// 它们共享同一份 `SessionState`，允许操作历史实例等于让玩家
  /// 回到过去改当前状态，语义混乱。
  ///
  /// 与 scene **互斥**：scene 不渲染原生消息列表，伴生没有宿主。
  /// 互斥在新建 UI 方案时就已拦截（`character_assembly_list_page`），
  /// 这里再判一次是防御旧数据——先做了伴生、后加 scene 的卡片
  /// 在补上双向拦截之前可能同时存在两者。
  Widget _buildCompanionAssembly(int index) {
    final character = _currentCharacter;
    if (character == null) return const SizedBox.shrink();
    if (_sceneTakesOver) return const SizedBox.shrink();
    if (!ChatAssemblyMount.hasAssembly(character.meta, 'extra_companion')) {
      return const SizedBox.shrink();
    }

    // 叠加层打开时由全屏浮层接管，气泡里的伴生实例不可交互，
    // 避免双实例冲突（用户只能操作浮层的叠加层）。
    final interactive =
        _isLatestAiMessage(index) && _companionOverlayPageId == null;

    // 宽度上限跟随气泡：气泡本身是 `屏宽 * 0.7 - 20` 再减去 10 的内边距 ×2。
    // 超出部分由 ChatAssemblyMount 等比缩小，不会撑破气泡。
    final bubbleMaxWidth =
        MediaQuery.of(context).size.width * 0.7 - 20 - 20;

    return Padding(
      // 与正文之间留一点间隔，避免视觉上粘成一块。
      padding: const EdgeInsets.only(top: 8),
      child: IgnorePointer(
        ignoring: !interactive,
        child: Opacity(
          // 历史实例压暗，让「这个不能点」一眼可见。
          opacity: interactive ? 1.0 : 0.55,
          child: ChatAssemblyMount(
            meta: character.meta,
            mode: 'extra_companion',
            sessionState: _sessionState,
            sessionVersion: _sessionVersion,
            onSessionStateChanged: _onAssemblySessionChanged,
            onUserProfileChanged: _onAssemblyUserProfileChanged,
            maxWidth: bubbleMaxWidth,
            // 伴生嵌在滚动列表里，绝不能开页面手势：
            // 它的全屏 Listener 会与 ListView 的垂直滚动打架。
            enablePageGestures: false,
            messages: _flowMessages,
            // 历史实例已被 IgnorePointer 挡住，不会走到这里；
            // 传进去是为了让最新一条的操作按钮可用。
            onMessageAction: _handleMessageAction,
            onSendMessage: _sendMessageFromAssembly,
            onOverlayStateChanged: (pageId) {
              if (_companionOverlayPageId == pageId) return;
              setState(() => _companionOverlayPageId = pageId);
            },
            characterAvatar: _characterAvatarPath,
            userAvatar: _userAvatarPath,
          ),
        ),
      ),
    );
  }

  /// 伴生叠加层「独立悬浮窗」层。
  ///
  /// 当伴生 UI 打开叠加层时，把它从气泡里「浮出」，用全屏浮层覆盖
  /// 更大区域渲染（独立画布由引擎按叠加页的 pcbWidth/pcbHeight 决定），
  /// 像 scene 一样居中、遮罩清晰，点击背景关闭。
  Widget _buildCompanionOverlayFloatLayer(Size screen) {
    final pageId = _companionOverlayPageId;
    final character = _currentCharacter;
    // 必须始终返回 Positioned：返回裸 widget 会让主 Stack 塌缩成 0×0。
    if (pageId == null || character == null) {
      return const Positioned.fill(child: IgnorePointer(child: SizedBox()));
    }
    final info = ChatAssemblyMount.resolveAssembly(character.meta, 'extra_companion');
    if (info == null) {
      return const Positioned.fill(child: IgnorePointer(child: SizedBox()));
    }

    return Positioned.fill(
      child: Stack(
        children: [
          // 背景蒙版：压暗聊天背景，让叠加层浮出更清晰。
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _companionOverlayPageId = null),
              child: Container(
                color: const Color(0xFF000000).withValues(alpha: 0.45),
              ),
            ),
          ),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380, maxHeight: 560),
              child: UIAssemblyRuntimeView(
                assemblyInfo: info,
                // 直接指定叠加页，全屏浮层只渲染叠加层。
                activePageId: pageId,
                showBlurredBackdrop: false,
                enablePageGestures: false,
                onDismissRequested: () =>
                    setState(() => _companionOverlayPageId = null),
                messages: _flowMessages,
                liveMessages: true,
                onSendMessage: _sendMessageFromAssembly,
                onMessageAction: _handleMessageAction,
                onOverlayStateChanged: (p) {
                  // 叠加层内再切换页时同步（如叠加层关闭回到 base）。
                  if (_companionOverlayPageId != p) {
                    setState(() => _companionOverlayPageId = p);
                  }
                },
                characterAvatar: _characterAvatarPath,
                userAvatar: _userAvatarPath,
                highlightRules: character.meta.effectiveHighlightRules,
                sessionState: _sessionState,
                sessionVersion: _sessionVersion,
                statusFields: character.meta.statusBarFields,
                onSessionStateChanged: _onAssemblySessionChanged,
                onUserProfileChanged: _onAssemblyUserProfileChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 常驻 UI 所在的整层（挂件本体 + 折叠悬浮球）。
  ///
  /// 独立成方法是因为它在主 Stack 里的位置很讲究：必须排在
  /// **scene 场景层之后**。常驻挂件是「始终可用的工具层」，
  /// scene 再全屏也不该把它埋掉；但仍要排在开场白之前——
  /// 开场白要求玩家先确认再进入场景，中途不该被挂件干扰。
  ///
  /// 与开场白 / scene 同理：必须**始终返回 Positioned**。
  /// 返回裸 widget 会成为主 Stack 唯一的非定位子组件，
  /// 把整个 Stack 压成 0×0，聊天页黑屏。
  Widget _buildStickyAssemblyLayer(double screenWidth) {
    final hidden = _showFanPanel || _animController.value >= 0.5;
    if (hidden) {
      return const Positioned.fill(child: IgnorePointer(child: SizedBox()));
    }

    return Positioned.fill(
      // 不能包 IgnorePointer：这一层铺满整个聊天区，
      // 挡住会让下方消息列表无法滚动。
      // Stack 默认只在子组件实际占位处命中，空白区域自然穿透给下层。
      child: Stack(
        children: [
          // 用真实坐标而非 Transform：布局盒子必须跟着一起移动，
          // 否则拖出原位置后命中测试收不到触摸。
          Positioned(
            left: _stickyOffset.dx,
            top: _stickyTopAnchor + _stickyOffset.dy,
            width: screenWidth,
            // 这一层给满宽只是为了确定水平基准；
            // 内部用 Align 收缩到挂件自身宽度，
            // 否则角上的按钮会被拉到整屏的边角去。
            child: Align(
              alignment: Alignment.topCenter,
              child: _buildStickyAssembly(screenWidth),
            ),
          ),
          // 折叠悬浮球：独立定位，可拖到任意位置并吸边。
          _buildStickyBallLayer(MediaQuery.of(context).size),
        ],
      ),
    );
  }

  /// A10-2：常驻 UI（extra_sticky）。
  ///
  /// 浮在聊天内容之上，可折叠成悬浮球。
  /// 折叠状态只影响显示，不卸载运行时——否则组件状态会丢失。
  Widget _buildStickyAssembly(double screenWidth) {
    final character = _currentCharacter;
    if (character == null) return const SizedBox.shrink();
    if (!ChatAssemblyMount.hasAssembly(character.meta, 'extra_sticky')) {
      return const SizedBox.shrink();
    }

    // 折叠态由 _buildStickyBallLayer 独立渲染：
    // 悬浮球要能自由拖到屏幕任意位置并吸附边缘，
    // 不能受挂件那层的水平基准约束。
    if (_stickyCollapsed) return const SizedBox.shrink();

    // 不能用 Transform.translate：它只移动绘制与自身内部的命中坐标，
    // 外层布局盒子仍留在原处。命中测试自上而下先检查父盒子边界，
    // 拖出原盒子范围后触摸根本传不进来（表现为「只拖走了样貌」）。
    // 这里改为真实改变布局位置，见调用处的 Positioned。
    // 吸收挂件区域内的水平拖动，避免穿透到聊天页根部触发滑出编辑页。
    // 与状态栏用的是同一招；挂件内部的 slider 层级更深，仍能赢过这层。
    return GestureDetector(
      behavior: HitTestBehavior.deferToChild,
      onHorizontalDragStart: (_) {},
      onHorizontalDragUpdate: (_) {},
      onHorizontalDragEnd: (_) {},
      // 拖动反馈：长按没有可见的触发点，必须让玩家确认「抓起来了」。
      // 轻微放大 + 投影，200ms 内完成，不喧宾夺主。
      child: AnimatedScale(
        scale: _stickyDragging ? 1.04 : 1.0,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: _stickyDragging
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.28),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : const <BoxShadow>[],
          ),
          child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          ChatAssemblyMount(
              meta: character.meta,
              mode: 'extra_sticky',
              sessionState: _sessionState,
              sessionVersion: _sessionVersion,
              onSessionStateChanged: _onAssemblySessionChanged,
              onUserProfileChanged: _onAssemblyUserProfileChanged,
              // 两侧各留 8，避免贴边
              maxWidth: screenWidth - 16,
              // 常驻挂件禁用滑动换页。
              //
              // 虽然 ChatAssemblyMount 的默认值就是 false，这里仍显式写出：
              //   1. 伴生那边是显式 false，只有这里靠默认值，
              //      读代码时容易误以为常驻是漏写了；
              //   2. 挂件浮在聊天内容之上，开启后那层全屏 Listener
              //      会用 translucent 持续参与命中，抢走内部 slider /
              //      输入框的拖动，也会和聊天页的左右滑出设置页打架；
              //   3. 多页面需求应当用叠加页实现（同 3.5g 的决策）。
              enablePageGestures: false,
              onDismissRequested: () => _collapseSticky(),
              // 长按 PCB 拖动整个挂件（取代原先左上角的内置把手）。
              //
              // 命中判定在 UIAssemblyRuntimeView 内部完成：落在 button /
              // slider / input / select / switch / message_flow 上时
              // 不会触发，手势完全让给组件。
              onLongPressDragStart: () {
                setState(() => _stickyDragging = true);
              },
              onLongPressDragUpdate: (delta) {
                setState(() => _stickyOffset += delta);
              },
              onLongPressDragEnd: () {
                setState(() => _stickyDragging = false);
              },
              messages: _flowMessages,
              characterAvatar: _characterAvatarPath,
              userAvatar: _userAvatarPath,
            ),
          // 内置折叠按钮：仅在作者没有标记折叠按钮时兜底显示，
          // 否则用户会看到两个关闭入口。
          if (!ChatAssemblyMount.hasKeyAction(character.meta, 'extra_sticky'))
            Positioned(
              top: -6,
              right: -6,
              child: _buildStickyToggle(
                icon: Icons.remove_rounded,
                onTap: _collapseSticky,
              ),
            ),
        ],
          ),
        ),
      ),
    );
  }

  /// A10-4：开场白 UI（opening）。
  ///
  /// 全屏覆盖在聊天之上，玩家确认后销毁并落盘，本轮会话不再出现。
  /// 与「开场白消息」是两回事：那是一条 assistant 消息，
  /// 这是一层可交互界面，两者可以并存。
  /// A10-5：是否由 scene UI 接管整个聊天页。
  ///
  /// scene 完全顶替聊天页——原生消息气泡与输入框全部禁用，
  /// 聊天页只作为背景蒙版。**底层无法关闭**，只能删除该 UI 方案。
  /// scene 判定缓存。与开场白同理——这个 getter 也是每帧跑，
  /// 里面两次调用都要解析全部 UI 方案并反序列化所有页面元素。
  bool? _sceneRunnableCache;
  String? _sceneCacheCharacterId;

  bool get _sceneTakesOver {
    final character = _currentCharacter;
    if (character == null) return false;
    if (_sceneCacheCharacterId != character.id ||
        _sceneRunnableCache == null) {
      _sceneCacheCharacterId = character.id;
      _sceneRunnableCache =
          ChatAssemblyMount.hasAssembly(character.meta, 'scene') &&
              // 缺少「打开聊天设置」标记时不接管：
              // 否则玩家进不了设置页，连重置对话都做不到，等于被锁死。
              ChatAssemblyMount.canRun(character.meta, 'scene');
    }
    return _sceneRunnableCache == true;
  }

  /// scene 场景 UI 层。
  Widget _buildSceneAssembly(Size screen) {
    // 与开场白同理：必须始终返回 Positioned，
    // 返回裸 widget 会让主 Stack 塌缩成 0×0（黑屏）。
    if (!_sceneTakesOver) {
      return const Positioned.fill(child: IgnorePointer(child: SizedBox()));
    }
    final character = _currentCharacter!;

    final panelW = panelWidth;

    // 键盘弹出时不压缩场景 UI。
    //
    // scene 是全屏接管的 UI：Scaffold body 一收缩，
    // 它绑定的 `top:0 bottom:0` 也跟着缩，
    // UIAssemblyRuntimeView 又按可用高度等比缩放整张 PCB——
    // 结果是作者摆好的界面在打字时整体变小。
    //
    // scene 模式下 Scaffold 的 resizeToAvoidBottomInset 已关闭，
    // body 恒为全屏高度，PCB 的 safeContainScale 不会因键盘而变，
    // 所以这里**不需要**再做 `bottom: -keyboardInset` 的补偿
    // （补了反而会把场景整体顶出屏幕）。
    //
    // 键盘高度只用来驱动 KeyboardAvoidingStage 的平移。
    // 必须用 _rawKeyboardInset：此处在 Scaffold body 内部，
    // 直接读 viewInsetsOf 会拿到被消费后的 0。
    final keyboardInset = _rawKeyboardInset;

    // 与聊天主体同步左移：设置页从右侧滑入时，scene 要一起让开，
    // 否则面板会被压在 scene 之下（scene 层排在主体之后）。
    return Positioned(
      left: -panelW * _animController.value,
      top: 0,
      bottom: 0,
      width: screen.width,
      child: IgnorePointer(
        // 设置页滑出过半后不再接收触摸，避免隔着面板误触场景。
        ignoring: _showFanPanel || _animController.value > 0.5,
        // 整个 scene 区吞掉横向拖动：滑出聊天设置的手势与 PCB 的
        // 翻页手势方向完全相同，同时存在必然误触。设置页的唯一入口
        // 收敛为作者标记的「打开聊天设置」按钮。
        //
        // 这里用 GestureDetector 而非 Listener：竞技场里子级的
        // HorizontalDrag 会赢过根部的同类识别器，从而截断冒泡；
        // 而 PCB 内部翻页走的是 Listener（不参与竞技场），不受影响。
        child: GestureDetector(
          behavior: HitTestBehavior.deferToChild,
          onHorizontalDragStart: (_) {},
          onHorizontalDragUpdate: (_) {},
          onHorizontalDragEnd: (_) {},
          child: KeyboardAvoidingStage(
            stageHeight: screen.height,
            keyboardInset: keyboardInset,
            child: Stack(
          children: [
            // 背景蒙版：压暗聊天背景，让 PCB 缩放留出的信箱区不至于
            // 和场景内容抢视线。保持半透明——作者选的聊天背景图仍是
            // 场景观感的一部分，全遮住反而丢了信息。
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                // 吸收点击：蒙版本身不可穿透到下方聊天内容。
                onTap: () {},
                child: Container(
                  color: const Color(0xFF07070B).withValues(alpha: 0.32),
                ),
              ),
            ),
            Positioned.fill(
              child: ChatAssemblyMount(
                meta: character.meta,
                mode: 'scene',
                sessionState: _sessionState,
                sessionVersion: _sessionVersion,
                onSessionStateChanged: _onAssemblySessionChanged,
                onUserProfileChanged: _onAssemblyUserProfileChanged,
                maxWidth: screen.width,
                // 场景是全屏形态，保留页面手势（多页场景可翻页）。
                enablePageGestures: true,
                // 关键职责在 scene 下是「打开聊天设置」，不是关闭 UI。
                onDismissRequested: _openPanel,
                messages: _flowMessages,
                onSendMessage: _sendMessageFromAssembly,
                onMessageAction: _handleMessageAction,
                characterAvatar: _characterAvatarPath,
                userAvatar: _userAvatarPath,
              ),
            ),
          ],
          ),
          ),
        ),
      ),
    );
  }

  /// 本卡是否有可运行的开场白 UI。null 表示尚未判定。
  ///
  /// **必须缓存**：`hasAssembly` 要解析全部 UI 方案的 JSON，
  /// `canRun` 还要把所有页面的元素反序列化一遍
  /// （跑团卡 5 页 100+ 元素）。这个 getter 每帧都跑，
  /// 不缓存就是每帧解析两百多个元素——
  /// 用户看到的「确认后还要卡半秒」主要来自这里，不是磁盘 IO。
  bool? _openingRunnableCache;

  /// 缓存对应的角色 id。切角色时失效。
  String? _openingCacheCharacterId;

  /// 开场白已被确认关闭的快速标记。
  ///
  /// 与 `OpeningGreetingState.isDismissed(_sessionState)` 等价，
  /// 但省掉一次 Map 查找，且语义更直白：
  /// **一旦置位，本轮对话就彻底不再考虑开场白**（用户建议）。
  /// 会话副本重建（清空历史 / 切角色）时跟着重置。
  bool _openingDismissed = false;

  /// 会话副本是否已经读进来了。
  ///
  /// **开场白在就绪前一律不渲染**——这是用户点出的关键：
  /// 「开关如果是关上的，怎么会先开开一下才关上？」
  ///
  /// `_setCurrentCharacter` 里 `_currentCharacter = char` 之后立刻
  /// setState 开始渲染，而 `_loadSessionState()` 还在三次 await 之后。
  /// 那段窗口里 `_openingDismissed` 还是初始的 false，
  /// 判定就会认为「没确认过」而把开场白铺出来，
  /// 等会话副本读完才消失——那半秒不是动画也不是解析，
  /// 是在等历史/用户/会话三次磁盘 IO。
  ///
  /// 宁可晚一帧显示，也不能先错误地显示再收回。
  bool _sessionReady = false;

  /// 是否应展示开场白 UI。
  ///
  /// 判定顺序按代价从低到高排：先看内存标记，再看缓存，
  /// 最后才可能触发一次 JSON 解析。
  bool get _shouldShowOpeningAssembly {
    // 会话副本没读完之前不做判断：此刻 _openingDismissed 还是默认值，
    // 贸然渲染会让已确认过的开场白又闪一次。
    if (!_sessionReady) return false;

    // 已确认过就直接不渲染，不做任何后续计算。
    if (_openingDismissed) return false;

    final character = _currentCharacter;
    if (character == null) return false;

    if (_openingCacheCharacterId != character.id ||
        _openingRunnableCache == null) {
      _openingCacheCharacterId = character.id;
      _openingRunnableCache =
          ChatAssemblyMount.hasAssembly(character.meta, 'opening') &&
              // 缺少「确认并关闭」标记时不铺遮罩，
              // 否则会出现点不掉的黑幕。
              ChatAssemblyMount.canRun(character.meta, 'opening');
    }
    if (_openingRunnableCache != true) return false;

    return !OpeningGreetingState.isDismissed(_sessionState);
  }

  /// 让 UI 方案判定缓存失效（开场白 + scene）。
  ///
  /// 角色卡的 UI 方案可能在编辑器里被改过，切回聊天页要重新判定。
  void _invalidateAssemblyCaches() {
    _openingRunnableCache = null;
    _openingCacheCharacterId = null;
    _sceneRunnableCache = null;
    _sceneCacheCharacterId = null;
  }

  Widget _buildOpeningAssembly(Size screen) {
    // 必须**始终**返回 Positioned：Stack 依据非定位子组件决定自身尺寸，
    // 一旦这里返回裸的 SizedBox.shrink()，它就成了唯一的非定位子组件，
    // 整个 Stack 会塌缩成 0×0，聊天页变黑屏。
    if (!_shouldShowOpeningAssembly) {
      return const Positioned.fill(child: IgnorePointer(child: SizedBox()));
    }
    final character = _currentCharacter!;

    return Positioned.fill(
      child: Stack(
        children: [
          // 遮罩：吸收所有点击**与横向拖动**，避免玩家在确认前操作下方聊天。
          // 点遮罩本身不关闭——必须走作者指定的确认按钮。
          //
          // 只写 onTap 拦不住拖动：滑出聊天设置的
          // `onHorizontalDragStart` 挂在最外层 GestureDetector 上，
          // 遮罩不声明同类识别器的话，拖动会穿透过去把设置页滑出来
          // （用户反馈）。这里与 scene 层用同一套办法——
          // 声明空的横向拖动回调，在竞技场里赢下这个手势。
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              onHorizontalDragStart: (_) {},
              onHorizontalDragUpdate: (_) {},
              onHorizontalDragEnd: (_) {},
              child: Container(
                color: Colors.black.withValues(alpha: 0.55),
              ),
            ),
          ),
          // 开场白里常有让玩家填名字的输入框，同样会被键盘盖住。
          // 与 scene 走同一套平移方案（不缩放、可手动上翻）。
          KeyboardAvoidingStage(
            stageHeight: screen.height,
            keyboardInset: _rawKeyboardInset,
            child: Center(
              child: ChatAssemblyMount(
                meta: character.meta,
                mode: 'opening',
                sessionState: _sessionState,
                sessionVersion: _sessionVersion,
                onSessionStateChanged: _onAssemblySessionChanged,
                onUserProfileChanged: _onAssemblyUserProfileChanged,
                maxWidth: screen.width - 32,
                // 开场白是全屏形态，保留页面手势（多页开场白可翻页）。
                enablePageGestures: true,
                onDismissRequested: _dismissOpeningAssembly,
                messages: _flowMessages,
                onSendMessage: _sendMessageFromAssembly,
                characterAvatar: _characterAvatarPath,
                userAvatar: _userAvatarPath,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 确认并关闭开场白 UI，同时落盘，避免重启后又弹出来。
  ///
  /// **先隐藏再落盘**，顺序不能反。
  ///
  /// 旧实现是 `await _saveSessionState()` 之后才 setState——
  /// 那一步是数据库写盘，UI 得等磁盘 IO 完成才消失，
  /// release 下也有半秒左右的可见滞留（用户反馈：确认后会闪一下）。
  ///
  /// 标记已经写进内存里的 _sessionState，判定 `_shouldShowOpeningAssembly`
  /// 读的就是它，所以立即 setState 就能让开场白消失；
  /// 落盘只是为了重启后不再弹，晚几十毫秒没有任何影响。
  Future<void> _dismissOpeningAssembly() async {
    if (!OpeningGreetingState.markDismissed(_sessionState)) return;
    // 置位快速标记：之后 _shouldShowOpeningAssembly 第一行就返回 false，
    // 不再走 JSON 解析那条路（用户建议）。
    _openingDismissed = true;

    // 如果开场白有多个选项（对应分支数 > 1）并且玩家点击了其中一个（更新了 branchIndex），
    // 那么我们在关闭开场白时，执行切换至对应的开场白和初始值！
    final greetings = _getCurrentGreetings();
    if (greetings.length > 1 && _messages.isNotEmpty) {
      final index = _sessionState.branchIndex;
      if (index >= 0 && index < greetings.length) {
        _switchGreeting(_messages.first, greetings, index);
      }
    }

    if (mounted) setState(() {});
    await _saveSessionState();
  }

  /// 折叠常驻 UI 为悬浮球。
  /// 内置按钮与作者标记的「关闭」组件都走这里。
  void _collapseSticky() {
    final screen = MediaQuery.of(context).size;
    setState(() {
      _stickyCollapsed = true;
      // 球出现在挂件右上角附近，位置连续；
      // 随后立即吸边，避免停在屏幕中间。
      _ballPos ??= Offset(
        screen.width - _ballSize - _ballMargin,
        _stickyTopAnchor,
      );
    });
    _snapBallToEdge(screen);
  }

  /// 折叠悬浮球层。独立于挂件层，可自由拖动并吸附到屏幕两侧。
  Widget _buildStickyBallLayer(Size screen) {
    final character = _currentCharacter;
    if (character == null || !_stickyCollapsed) {
      return const SizedBox.shrink();
    }
    if (!ChatAssemblyMount.hasAssembly(character.meta, 'extra_sticky')) {
      return const SizedBox.shrink();
    }

    // 首次折叠时若还没有位置，默认停在右上角。
    final pos = _ballPos ??
        Offset(screen.width - _ballSize - _ballMargin, _stickyTopAnchor);

    // 缩进时露出半个球：向屏幕外侧偏移半个身位。
    final tucked = _ballTucked && !_ballPeeking && !_ballDragging;
    final tuckShift =
        tucked ? (_ballOnLeft ? -_ballSize / 2 : _ballSize / 2) : 0.0;

    return Positioned(
      left: pos.dx + tuckShift,
      top: pos.dy,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 220),
        opacity: tucked ? 0.45 : 1.0,
        // 用抢占式识别器：默认 Pan 要等 18px 才确认，且这段期间会被
        // 外层的 HorizontalDrag 抢走，表现为「不跟手」+「时灵时不灵」。
        child: RawGestureDetector(
          behavior: HitTestBehavior.opaque,
          gestures: <Type, GestureRecognizerFactory>{
            TapGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
              () => TapGestureRecognizer(),
              (instance) {
                instance.onTap = () {
                  if (tucked) {
                    // 两段式：缩进态先冒出来，再点一次才展开。
                    setState(() => _ballPeeking = true);
                    _restartBallTuckTimer();
                    return;
                  }
                  _ballTuckTimer?.cancel();
                  setState(() {
                    _stickyCollapsed = false;
                    _ballPeeking = false;
                    _ballTucked = false;
                    // 展开后 UI 出现在球的附近，位置连续。
                    _stickyOffset = _stickyOffsetForBall(pos, screen);
                  });
                };
              },
            ),
            _EagerPanRecognizer:
                GestureRecognizerFactoryWithHandlers<_EagerPanRecognizer>(
              () => _EagerPanRecognizer(),
              (instance) {
                instance.onStart = (_) {
                  _ballTuckTimer?.cancel();
                  setState(() {
                    _ballDragging = true;
                    _ballTucked = false;
                    _ballPeeking = false;
                    _ballPos = pos;
                  });
                };
                instance.onUpdate = (d) {
                  setState(() {
                    final next = (_ballPos ?? pos) + d.delta;
                    _ballPos = Offset(
                      next.dx
                          .clamp(-_ballSize / 2, screen.width - _ballSize / 2),
                      next.dy
                          .clamp(_stickyTopAnchor, screen.height - 160.0),
                    );
                  });
                };
                instance.onEnd = (_) {
                  setState(() => _ballDragging = false);
                  // 实时贴边：松手立刻吸附到最近一侧。
                  _snapBallToEdge(screen);
                };
              },
            ),
          },
          child: Container(
            width: _ballSize,
            height: _ballSize,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.42),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.22),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: const Icon(
              Icons.widgets_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }

  /// 由悬浮球位置推算展开后挂件应有的偏移。
  ///
  /// 按球所在象限选择展开方向，保证挂件不会跑出屏幕：
  /// 球在左半屏则向右下展开，右半屏则向左下展开；
  /// 贴近底部时改为向上展开。
  Offset _stickyOffsetForBall(Offset ballPos, Size screen) {
    final size = assemblyDesignSize(
          _currentCharacter!.meta,
          'extra_sticky',
        ) ??
        const Size(300, 120);
    final w = min(size.width, screen.width - 16);
    final h = size.height;

    final onLeft = ballPos.dx + _ballSize / 2 < screen.width / 2;
    // 挂件默认水平居中，这里换算成相对默认位置的偏移量。
    final defaultLeft = (screen.width - w) / 2;
    final targetLeft = onLeft
        ? _ballMargin
        : screen.width - w - _ballMargin;

    // 纵向：优先在球下方展开，空间不够则改为上方。
    var targetTop = ballPos.dy + _ballSize + 8;
    if (targetTop + h > screen.height - 120) {
      targetTop = max(_stickyTopAnchor, ballPos.dy - h - 8);
    }

    return Offset(targetLeft - defaultLeft, targetTop - _stickyTopAnchor);
  }

  Widget _buildStickyToggle({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.42),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
        ),
        child: Icon(icon, color: Colors.white, size: 14),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final panelW = panelWidth;

    // 在**进入 Scaffold 之前**把键盘高度取出来。
    //
    // 下面那个 Scaffold 是默认的 resizeToAvoidBottomInset: true，
    // 它会「消费掉」viewInsets：body 被塞进一个矮了一个键盘高度的空间，
    // 同时向下传递的 MediaQuery 里 viewInsets.bottom 被清成 0。
    // 所以 scene / opening 层在 body 内部再读 viewInsetsOf 永远拿到 0，
    // 键盘避让完全不会触发（用户实测：输入框照样被盖住）。
    //
    // 这里读到的才是真实值，用 _rawKeyboardInset 传给全屏 UI 层。
    _rawKeyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    final page = MediaQuery.removePadding(
        context: context,
        removeTop: true,        // ✅ 强制抹掉 Flutter 引擎留出的顶部 inset
        child: Scaffold(
          primary: false,
          backgroundColor: Colors.transparent,
          // scene 接管时**不要**让 Scaffold 压缩 body。
          //
          // 之前靠 `bottom: -keyboardInset` 让背景/场景溢出到键盘区，
          // 但外层 Stack 默认 clipBehavior: Clip.hardEdge，
          // 溢出部分会被裁掉，屏幕底部依旧露出一条黑边，
          // 且随 body 逐帧回弹而抖动（用户反馈两次）。
          //
          // scene 模式下原生输入栏本就不渲染（见 `_sceneTakesOver` 判断），
          // 没有任何东西需要跟着键盘上移，压缩 body 纯属有害：
          // 直接关掉，body 始终保持全屏高度，键盘只是盖在它上面。
          // 输入框的避让完全交给 KeyboardAvoidingStage 的平移。
          //
          // 非 scene 的普通聊天页仍需要 true——那里的输入栏要跟着键盘走。
          // 开场白同理：它也是全屏铺开、且此时原生输入栏被遮罩挡着不可用。
          resizeToAvoidBottomInset:
              !_sceneTakesOver && !_shouldShowOpeningAssembly,
          body: SafeArea(
            top: false, // 不保留顶部安全区
            bottom: false,
            maintainBottomViewPadding: true,
            child: GestureDetector(
              onHorizontalDragStart: _onHorizontalDragStart,
              onHorizontalDragUpdate: _onHorizontalDragUpdate,
              onHorizontalDragEnd: _onHorizontalDragEnd,
              child: Stack(
                children: [
                  // 背景图层（动态）
                  // 背景取自 _background 缓存，不在 build 里发起查询。
                  //
                  // 正常路径下 _seedBackgroundFromCache() 已经在 initState
                  // 同步填好了，这里首帧就是真背景。下面那个空窗分支只在
                  // 缓存预热失败时才会走到，所以用中性深灰而不是纯黑——
                  // 万一真的露出来，也比一块死黑更不显眼。
                  // 铺满即可：scene 模式下 Scaffold 已关掉
                  // resizeToAvoidBottomInset，body 始终是全屏高度，
                  // 底部不会再出现露底的缝隙。
                  //
                  // 曾经改成 `bottom: -_rawKeyboardInset` 想让背景溢出到
                  // 键盘区，但外层 Stack 默认 Clip.hardEdge 会把溢出裁掉，
                  // 治标不治本，已改为从源头不压缩。
                  Positioned.fill(
                    child: !_backgroundLoaded
                        ? const ColoredBox(color: Color(0xFF1A1A1A))
                        : _background == null
                            ? const DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Color(0xFFE3F2FD),
                                      Color(0xFFF3E5F5),
                                    ],
                                  ),
                                ),
                              )
                            : _buildBackground(_background!),
                  ),
                  // 聊天主体 + 右侧面板
                  //
                  // 用 AnimatedBuilder 把「随动画变的壳」与「不变的子树」分开：
                  // 750+ 行的主体作为 child 只构建一次，抽屉滑动时每帧
                  // 只重跑下面这个 builder（几行 Positioned）。
                  //
                  // 之前 _animController 挂的是无条件 setState，
                  // 滑动期间每帧重建整棵 1285 行的树。
                  AnimatedBuilder(
                    animation: _animController,
                    child: Row(
                        children: [
                          // 这一层也依赖动画值，必须自己订阅：外层把子树
                          // 当作静态 child 缓存后，写在子树里的
                          // _animController.value 不会再随动画刷新。
                          AnimatedBuilder(
                            animation: _animController,
                            builder: (context, _) => IgnorePointer(
                              ignoring: _animController.value > 0.5,
                            child: SizedBox(
                              width: screenWidth,
                              child: Column(
                                children: [
                                  // scene 接管时整条消息列表（含头像与气泡）不渲染：
                                  // 聊天页只作为背景蒙版，历史由 scene 内的
                                  // message_flow 组件按作者意愿呈现。
                                  if (_sceneTakesOver)
                                    const Expanded(child: SizedBox())
                                  else
                                  Expanded(
                                    child: ListView.builder(
                                      controller: _scrollController,
                                      // 底部留白要盖住浮在列表之上的输入条
                                      // （42+16+20=78）以及系统底部安全区，
                                      // 否则最后一条气泡会压在输入条下面。
                                      padding: EdgeInsets.only(
                                        top: 50,
                                        bottom: 78 +
                                            MediaQuery.of(context)
                                                .padding
                                                .bottom,
                                      ),
                                      itemCount:
                                      _messages.length + (_isLoading ? 1 : 0),
                                      itemBuilder: (ctx, index) {
                                        if (index < _messages.length) {
                                          final msg = _messages[index];
                                          final isMe = msg['role'] == 'user';
                                          return Padding(
                                            padding: EdgeInsets.only(
                                              top: 4,
                                              bottom: _isLastMessage(index) ? 0 : 4,
                                              left: 8,
                                              right: 8,
                                            ),
                                            child: Row(
                                              crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                              mainAxisAlignment: isMe
                                                  ? MainAxisAlignment.end
                                                  : MainAxisAlignment.start,
                                              children: [
                                                if (!isMe) ...[
                                                  Column(
                                                    crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      // 头像 + 气泡
                                                      Row(
                                                        crossAxisAlignment:
                                                        CrossAxisAlignment.end,
                                                        children: [
                                                          Padding(
                                                            padding:
                                                            const EdgeInsets.only(
                                                              right: 6,
                                                            ),
                                                            child: CircleAvatar(
                                                              radius: 14,
                                                              backgroundColor:
                                                              _currentCharacter
                                                                  ?.avatar !=
                                                                  null &&
                                                                  _currentCharacter!
                                                                      .avatar
                                                                      .isNotEmpty &&
                                                                  _fileExists(_currentCharacter!.avatar)
                                                                  ? null
                                                                  : Colors
                                                                  .grey
                                                                  .shade300,
                                                              backgroundImage:
                                                              _currentCharacter
                                                                  ?.avatar !=
                                                                  null &&
                                                                  _currentCharacter!
                                                                      .avatar
                                                                      .isNotEmpty &&
                                                                  _fileExists(_currentCharacter!.avatar)
                                                                  ? FileImage(
                                                                File(
                                                                  _currentCharacter!
                                                                      .avatar,
                                                                ),
                                                              )
                                                                  : null,
                                                              child:
                                                              _currentCharacter
                                                                  ?.avatar ==
                                                                  null ||
                                                                  _currentCharacter!
                                                                      .avatar
                                                                      .isEmpty ||
                                                                  !_fileExists(_currentCharacter!.avatar)
                                                                  ? Icon(
                                                                Icons.person,
                                                                size: 18,
                                                                color: Colors
                                                                    .grey
                                                                    .shade600,
                                                              )
                                                                  : null,
                                                            ),
                                                          ),
                                                          Container(
                                                            constraints: BoxConstraints(
                                                              maxWidth:
                                                              MediaQuery.of(
                                                                context,
                                                              ).size.width *
                                                                  0.7 -
                                                                  20,
                                                            ),
                                                            padding:
                                                            const EdgeInsets.all(
                                                              10,
                                                            ),
                                                            decoration: BoxDecoration(
                                                              color: Colors
                                                                  .grey
                                                                  .shade200,
                                                              borderRadius: const BorderRadius.only(
                                                                topLeft:
                                                                Radius.circular(
                                                                  12,
                                                                ),
                                                                topRight:
                                                                Radius.circular(
                                                                  12,
                                                                ),
                                                                bottomRight:
                                                                Radius.circular(
                                                                  12,
                                                                ),
                                                                bottomLeft:
                                                                Radius.circular(
                                                                  4,
                                                                ),
                                                              ),
                                                            ),
                                                            // A10-3：伴生 UI 内嵌在气泡最下方，
                                                            // 与正文同属一个气泡容器——
                                                            // 撤回消息时数据记录一并撤回。
                                                            child: Column(
                                                              crossAxisAlignment:
                                                                  CrossAxisAlignment
                                                                      .start,
                                                              mainAxisSize:
                                                                  MainAxisSize.min,
                                                              children: [
                                                                _buildMarkdownWidget(
                                                                  msg['content']!,
                                                                ),
                                                                _buildCompanionAssembly(
                                                                  index,
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                        ],
                                                      ),

                                                      // 功能图标行（仅最新 AI 消息显示）
                                                      if (_isLatestAiMessage(index))
                                                        SizedBox(
                                                          height: 29,
                                                          child: Padding(
                                                            padding:
                                                            const EdgeInsets.only(
                                                              left: 34,
                                                            ),
                                                            child: Row(
                                                              mainAxisSize:
                                                              MainAxisSize.min,
                                                              children: [
                                                                IconButton(
                                                                  icon: const Icon(
                                                                    Icons.refresh,
                                                                    size: 14,
                                                                    color:
                                                                    Colors.grey,
                                                                  ),
                                                                  onPressed: () =>
                                                                      _regenerateMessage(
                                                                        index,
                                                                      ),
                                                                  constraints:
                                                                  const BoxConstraints(
                                                                    minWidth:
                                                                    24,
                                                                    minHeight:
                                                                    24,
                                                                  ),
                                                                  padding:
                                                                  EdgeInsets
                                                                      .zero,
                                                                  splashRadius: 12,
                                                                ),
                                                                const SizedBox(
                                                                  width: 2,
                                                                ),
                                                                IconButton(
                                                                  icon: const Icon(
                                                                    Icons
                                                                        .more_horiz,
                                                                    size: 14,
                                                                    color:
                                                                    Colors.grey,
                                                                  ),
                                                                  onPressed: () =>
                                                                      _continueMessage(
                                                                        index,
                                                                      ),
                                                                  constraints:
                                                                  const BoxConstraints(
                                                                    minWidth:
                                                                    24,
                                                                    minHeight:
                                                                    24,
                                                                  ),
                                                                  padding:
                                                                  EdgeInsets
                                                                      .zero,
                                                                  splashRadius: 12,
                                                                ),
                                                                // 开场白切换（如果该消息是开场白）
                                                                if (_isGreetingMessage(
                                                                  msg,
                                                                ))
                                                                  Builder(
                                                                    builder: (context) {
                                                                      final greetings =
                                                                      _getCurrentGreetings();
                                                                      final currentContent =
                                                                      msg['content']
                                                                      as String;
                                                                      int
                                                                      cur = greetings
                                                                          .indexWhere(
                                                                            (g) =>
                                                                        g.content ==
                                                                            currentContent,
                                                                      );
                                                                      if (cur == -1) {
                                                                        cur = 0;
                                                                      }
                                                                      return Row(
                                                                        mainAxisSize:
                                                                        MainAxisSize
                                                                            .min,
                                                                        children: [
                                                                          const SizedBox(
                                                                            width:
                                                                            4,
                                                                          ),
                                                                          IconButton(
                                                                            icon: const Icon(
                                                                              Icons
                                                                                  .arrow_back_ios,
                                                                              size:
                                                                              10,
                                                                              color:
                                                                              Colors.grey,
                                                                            ),
                                                                            onPressed: () {
                                                                              if (cur >
                                                                                  0) {
                                                                                _switchGreeting(
                                                                                  msg,
                                                                                  greetings,
                                                                                  cur - 1,
                                                                                );
                                                                              }
                                                                            },
                                                                            constraints: const BoxConstraints(
                                                                              minWidth:
                                                                              20,
                                                                              minHeight:
                                                                              20,
                                                                            ),
                                                                            padding:
                                                                            EdgeInsets.zero,
                                                                            splashRadius:
                                                                            10,
                                                                          ),
                                                                          Text(
                                                                            '${cur + 1}/${greetings.length}',
                                                                            style: const TextStyle(
                                                                              fontSize:
                                                                              10,
                                                                              color:
                                                                              Colors.grey,
                                                                            ),
                                                                          ),
                                                                          IconButton(
                                                                            icon: const Icon(
                                                                              Icons
                                                                                  .arrow_forward_ios,
                                                                              size:
                                                                              10,
                                                                              color:
                                                                              Colors.grey,
                                                                            ),
                                                                            onPressed: () {
                                                                              if (cur <
                                                                                  greetings.length -
                                                                                      1) {
                                                                                _switchGreeting(
                                                                                  msg,
                                                                                  greetings,
                                                                                  cur + 1,
                                                                                );
                                                                              }
                                                                            },
                                                                            constraints: const BoxConstraints(
                                                                              minWidth:
                                                                              20,
                                                                              minHeight:
                                                                              20,
                                                                            ),
                                                                            padding:
                                                                            EdgeInsets.zero,
                                                                            splashRadius:
                                                                            10,
                                                                          ),
                                                                        ],
                                                                      );
                                                                    },
                                                                  )
                                                                else if (msg
                                                                    .containsKey(
                                                                  'versions',
                                                                ) &&
                                                                    (msg['versions']
                                                                    as List)
                                                                        .isNotEmpty)
                                                                  Builder(
                                                                    builder: (context) {
                                                                      final versions =
                                                                      List<
                                                                          String
                                                                      >.from(
                                                                        msg['versions']
                                                                        as List,
                                                                      );
                                                                      int cur =
                                                                          (msg['currentVersionIndex']
                                                                          as int?) ??
                                                                              0;
                                                                      return Row(
                                                                        mainAxisSize:
                                                                        MainAxisSize
                                                                            .min,
                                                                        children: [
                                                                          const SizedBox(
                                                                            width:
                                                                            8,
                                                                          ),
                                                                          IconButton(
                                                                            icon: const Icon(
                                                                              Icons
                                                                                  .arrow_back_ios,
                                                                              size:
                                                                              12,
                                                                              color:
                                                                              Colors.grey,
                                                                            ),
                                                                            onPressed: () {
                                                                              if (cur >
                                                                                  0) {
                                                                                setState(() {
                                                                                  msg['currentVersionIndex'] =
                                                                                      cur -
                                                                                          1;
                                                                                  msg['content'] =
                                                                                  versions[cur -
                                                                                      1];
                                                                                  final versionIds =
                                                                                  List<
                                                                                      String
                                                                                  >.from(
                                                                                    msg['versionIds']
                                                                                    as List,
                                                                                  );
                                                                                  msg['id'] =
                                                                                  versionIds[cur -
                                                                                      1];
                                                                                });
                                                                              }
                                                                            },
                                                                            constraints: const BoxConstraints(
                                                                              minWidth:
                                                                              24,
                                                                              minHeight:
                                                                              24,
                                                                            ),
                                                                            padding:
                                                                            EdgeInsets.zero,
                                                                            splashRadius:
                                                                            12,
                                                                          ),
                                                                          Text(
                                                                            '${cur + 1}/${versions.length}',
                                                                            style: const TextStyle(
                                                                              fontSize:
                                                                              11,
                                                                              color:
                                                                              Colors.grey,
                                                                            ),
                                                                          ),
                                                                          IconButton(
                                                                            icon: const Icon(
                                                                              Icons
                                                                                  .arrow_forward_ios,
                                                                              size:
                                                                              12,
                                                                              color:
                                                                              Colors.grey,
                                                                            ),
                                                                            onPressed: () {
                                                                              if (cur <
                                                                                  versions.length -
                                                                                      1) {
                                                                                setState(() {
                                                                                  msg['currentVersionIndex'] =
                                                                                      cur +
                                                                                          1;
                                                                                  msg['content'] =
                                                                                  versions[cur +
                                                                                      1];
                                                                                  final versionIds =
                                                                                  List<
                                                                                      String
                                                                                  >.from(
                                                                                    msg['versionIds']
                                                                                    as List,
                                                                                  );
                                                                                  msg['id'] =
                                                                                  versionIds[cur +
                                                                                      1];
                                                                                });
                                                                              }
                                                                            },
                                                                            constraints: const BoxConstraints(
                                                                              minWidth:
                                                                              24,
                                                                              minHeight:
                                                                              24,
                                                                            ),
                                                                            padding:
                                                                            EdgeInsets.zero,
                                                                            splashRadius:
                                                                            12,
                                                                          ),
                                                                        ],
                                                                      );
                                                                    },
                                                                  ),
                                                              ],
                                                            ),
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                ],
                                                if (isMe) ...[
                                                  Stack(
                                                    clipBehavior: Clip.none,
                                                    alignment:
                                                    Alignment.bottomRight,
                                                    children: [
                                                      // 气泡 + 头像
                                                      Padding(
                                                        padding:
                                                        const EdgeInsets.only(
                                                          bottom: 40,
                                                        ),
                                                        child: Row(
                                                          crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .end,
                                                          mainAxisAlignment:
                                                          MainAxisAlignment.end,
                                                          children: [
                                                            GestureDetector(
                                                              onTap: () =>
                                                                  _startEdit(index),
                                                              behavior:
                                                              HitTestBehavior
                                                                  .opaque,
                                                              // 确保整个区域可点击
                                                              child: Container(
                                                                constraints: BoxConstraints(
                                                                  maxWidth:
                                                                  MediaQuery.of(
                                                                    context,
                                                                  ).size.width *
                                                                      0.7 -
                                                                      20,
                                                                ),
                                                                padding:
                                                                const EdgeInsets.all(
                                                                  10,
                                                                ),
                                                                decoration: BoxDecoration(
                                                                  color:
                                                                  _editingIndex ==
                                                                      index
                                                                      ? Colors
                                                                      .green
                                                                      .shade200
                                                                      : Colors
                                                                      .green
                                                                      .shade100,
                                                                  borderRadius: const BorderRadius.only(
                                                                    topLeft:
                                                                    Radius.circular(
                                                                      12,
                                                                    ),
                                                                    topRight:
                                                                    Radius.circular(
                                                                      12,
                                                                    ),
                                                                    bottomLeft:
                                                                    Radius.circular(
                                                                      12,
                                                                    ),
                                                                    bottomRight:
                                                                    Radius.circular(
                                                                      4,
                                                                    ),
                                                                  ),
                                                                ),
                                                                child: MarkdownBody(
                                                                  data:
                                                                  msg['content']!,
                                                                  selectable: false,
                                                                  // 用户消息不可选，避免阻挡点击
                                                                  extensionSet: md
                                                                      .ExtensionSet
                                                                      .gitHubFlavored,
                                                                  onTapLink: (text, href, title) {
                                                                    if (href !=
                                                                        null &&
                                                                        href.startsWith(
                                                                          'action://',
                                                                        )) {
                                                                      final action =
                                                                      href.substring(
                                                                        'action://'
                                                                            .length,
                                                                      );
                                                                      _handleMarkdownAction(
                                                                        action,
                                                                      );
                                                                    }
                                                                  },
                                                                ),
                                                              ),
                                                            ),
                                                            Padding(
                                                              padding:
                                                              const EdgeInsets.only(
                                                                left: 6,
                                                              ),
                                                              child: CircleAvatar(
                                                                radius: 14,
                                                                backgroundColor:
                                                                Colors
                                                                    .grey
                                                                    .shade300,
                                                                backgroundImage:
                                                                _currentUser
                                                                    .avatarPath
                                                                    .isNotEmpty &&
                                                                    _fileExists(_currentUser.avatarPath)
                                                                    ? FileImage(
                                                                  File(
                                                                    _currentUser
                                                                        .avatarPath,
                                                                  ),
                                                                )
                                                                    : null,
                                                                child:
                                                                _currentUser
                                                                    .avatarPath
                                                                    .isEmpty ||
                                                                    !_fileExists(_currentUser.avatarPath)
                                                                    ? Icon(
                                                                  Icons
                                                                      .person,
                                                                  size: 18,
                                                                  color: Colors
                                                                      .grey
                                                                      .shade600,
                                                                )
                                                                    : null,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                      // 功能图标：放在气泡底部外侧，紧贴但不遮挡
                                                      if (_editingIndex != index &&
                                                          _isLatestUserMessage(
                                                            index,
                                                          ))
                                                        Positioned(
                                                          right: 40,
                                                          bottom: 17,
                                                          width: 20,
                                                          height: 20,
                                                          child: Container(
                                                            width: 20, // 限制点击区域
                                                            height: 20,
                                                            alignment:
                                                            Alignment.center,
                                                            child: IconButton(
                                                              icon: const Icon(
                                                                Icons.shortcut,
                                                                size: 14,
                                                                color: Colors.grey,
                                                              ),
                                                              onPressed: () =>
                                                                  _deleteUserMessage(
                                                                    index,
                                                                  ),
                                                              constraints:
                                                              const BoxConstraints(
                                                                minWidth: 20,
                                                                minHeight: 20,
                                                              ),
                                                              padding:
                                                              EdgeInsets.zero,
                                                              splashRadius: 10,
                                                            ),
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                ],
                                              ],
                                            ),
                                          );
                                        } else {
                                          return const Align(
                                            alignment: Alignment.centerLeft,
                                            child: Padding(
                                              padding: EdgeInsets.all(12),
                                              child: Text('...'),
                                            ),
                                          );
                                        }
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )),
                          // 右侧设置面板
                          SizedBox(
                            width: panelW,
                            child: Container(
                              color: Theme.of(context).scaffoldBackgroundColor,
                              child: Column(
                                children: [
                                  AppBar(
                                    title: const Text('聊天设置'),
                                    automaticallyImplyLeading: false,
                                  ),
                                  Expanded(
                                    child: ListView(
                                      children: [
                                        ListTile(
                                          leading: const Icon(Icons.person),
                                          title: const Text('用户设定'),
                                          onTap: () {
                                            if (_currentCharacter == null) return;
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    RoleUserSettingsPage(
                                                      character: _currentCharacter!,
                                                    ),
                                              ),
                                            ).then((_) => _loadUser()); // 返回后刷新
                                          },
                                        ),
                                        ListTile(
                                          leading: const Icon(Icons.tune),
                                          title: const Text('Prompt 策略'),
                                          onTap: () {
                                            if (_currentCharacter == null) return;

                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => PromptSettingsPage(
                                                  characterId: _currentCharacter!.id,
                                                  characterName: _currentCharacter!.name,
                                                  buildPreview: _buildPromptPreviewData,
                                                ),
                                              ),
                                            ).then((_) => _loadPromptSettings());
                                          },
                                        ),
                                        ListTile(
                                          leading: const Icon(Icons.image),
                                          title: const Text('背景设置'),
                                          onTap: () {
                                            Navigator.push(
                                              context,
                                              PageRouteBuilder(
                                                opaque: false,
                                                // 透明路由
                                                transitionDuration: Duration.zero,
                                                // 无过渡动画（由内部自己做动画）
                                                pageBuilder: (_, _, _) =>
                                                    BackgroundPickerSheet(
                                                      character: _currentCharacter,
                                                    ),
                                              ),
                                            ).then((_) => setState(() {}));
                                          },
                                        ),
                                        ListTile(
                                          leading: const Icon(Icons.clear_all),
                                          title: const Text('清空历史'),
                                          onTap: _clearHistoryWithOptions,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    builder: (context, child) {
                      final v = _animController.value;
                      return Positioned(
                        left: -panelW * v,
                        top: 0,
                        bottom: 0,
                        width: screenWidth + panelW,
                        child: IgnorePointer(
                          // scene 接管时禁用聊天主体的交互，避免玩家隔着
                          // 场景 UI 误触下方内容；但设置页滑出时必须恢复，
                          // 否则「打开聊天设置」进去后所有条目都点不动。
                          ignoring:
                              _showFanPanel || (_sceneTakesOver && v < 0.5),
                          child: child,
                        ),
                      );
                    },
                  ),
                  //扇形面板
                  if (_showFanPanel)
                    Positioned.fill(
                      child: AnimatedBuilder(
                        animation: _fanPanelAnimController,
                        builder: (context, child) {
                          final fade = _fanPanelFadeAnim.value;

                          return Stack(
                            children: [
                              // 背景遮罩渐变
                              Positioned.fill(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: _showCardDetail ? null : _closeFanPanel,
                                  child: Container(
                                    color: Colors.black.withValues(alpha: 0.54 * fade),
                                  ),
                                ),
                              ),

                              // 轮盘从底部升起
                              if (!_showCardDetail)
                                SlideTransition(
                                  position: _fanPanelSlideAnim,
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.translucent,
                                    onHorizontalDragUpdate: (details) {
                                      _inertiaTicker?.stop();
                                      _inertiaTicker?.dispose();
                                      _inertiaTicker = null;
                                      _fanSnapController.stop();

                                      final maxOff =
                                          _halfArcLen + (_cardCount - 1) / 2.0 * _cardDs;

                                      setState(() {
                                        _fanOffset += details.delta.dx;
                                        _fanOffset = _fanOffset.clamp(-maxOff, maxOff);
                                      });
                                    },
                                    onHorizontalDragEnd: (details) {
                                      _startInertia(details.velocity.pixelsPerSecond.dx);
                                    },
                                    child: _buildFanCards(),
                                  ),
                                ),

                              // 详情弹窗层
                              if (_showCardDetail && _detailCard != null)
                                _buildCardDetailOverlay(_detailCard!),
                            ],
                          );
                        },
                      ),
                    ),

                  // 状态栏展开时：点击状态栏以外区域关闭（无蒙版，纯透明捕获）
                  if (_statusBarExpanded)
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: _collapseStatusBar,
                      ),
                    ),
                  // 3. 状态栏（固定长条 + 点击在下方展开详情块网格）
                  // 加宽到几乎贴边，遮住两侧头像，聚焦更强。
                  // scene 接管时不渲染：状态栏属于聊天页外壳，
                  // 场景 UI 需要的状态由作者自己在 PCB 上摆组件呈现。
                  if (!_sceneTakesOver)
                  Positioned(
                    top: 8,
                    left: 6,
                    right: 6,
                    // 淡出要逐帧平滑，所以自己订阅动画。
                    // 外层的整树重建已经按阈值节流，靠它刷新会一卡一卡。
                    child: AnimatedBuilder(
                      animation: _animController,
                      builder: (context, _) => IgnorePointer(
                      ignoring: _showFanPanel || _animController.value > 0.5,
                      child: Opacity(
                        opacity: (_showFanPanel || _showCardDetail)
                            ? 0.0
                            : (1.0 - _animController.value),
                        // 吸收状态栏区域内的横向拖动，避免误触发滑出右侧设置页。
                        child: GestureDetector(
                          behavior: HitTestBehavior.deferToChild,
                          onHorizontalDragStart: (_) {},
                          onHorizontalDragUpdate: (_) {},
                          onHorizontalDragEnd: (_) {},
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: _buildStatusBar(),
                          ),
                        ),
                      ),
                    ),
                    ),
                  ),
                  // 3.5 常驻 UI（extra_sticky）**不在这里渲染**。
                  //
                  // 它必须叠在 scene 场景层之上，否则会被全屏场景盖住，
                  // 因此挪到了下方 scene 之后，见 `_buildStickyAssemblyLayer`。
                  //
                  // 悬浮毛玻璃输入栏（最上层）
                  // scene 接管时禁用：玩家只能通过 scene 内的组件对话。
                  if (_animController.value < 0.1 &&
                      !_showFanPanel &&
                      !_sceneTakesOver)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: IgnorePointer(
                        ignoring: _showFanPanel,
                        child: Padding(
                          padding: EdgeInsets.only(
                            bottom: MediaQuery.of(context).padding.bottom,
                          ),
                          child: SizedBox(
                            width: double.infinity,
                            height: 42 + 16 + 20,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                if (_inputExpanded)
                                  Positioned(
                                    left: 16,
                                    top: -5,
                                    child: Text(
                                      'Tokens: ${_estimateTokens()}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade500,
                                      ),
                                    ),
                                  ),
                                // 底部角色名胶囊：输入框未展开时显示，展开时渐隐
                                AnimatedBuilder(
                                  animation: _inputAnimController,
                                  builder: (context, child) {
                                    final opacity = (1.0 - _inputExpandAnimation.value).clamp(0.0, 1.0);

                                    return Positioned(
                                      left: 66,
                                      right: 66,
                                      top: 16,
                                      height: 36,
                                      child: IgnorePointer(
                                        ignoring: opacity < 0.5 || _showFanPanel,
                                        child: Opacity(
                                          opacity: opacity,
                                          child: Center(
                                            child: GestureDetector(
                                              onTap: () {
                                                if (_showFanPanel) {
                                                  _closeFanPanel();
                                                } else {
                                                  _openFanPanel();
                                                }
                                              },
                                              child: ClipRRect(
                                                borderRadius: BorderRadius.circular(18),
                                                child: BackdropFilter(
                                                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                                                  child: Container(
                                                    constraints: const BoxConstraints(
                                                      minWidth: 72,
                                                      maxWidth: 180,
                                                    ),
                                                    padding: const EdgeInsets.symmetric(
                                                      horizontal: 14,
                                                      vertical: 7,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: Colors.white.withAlpha(95),
                                                      borderRadius: BorderRadius.circular(18),
                                                      border: Border.all(
                                                        color: Colors.white.withAlpha(80),
                                                      ),
                                                      boxShadow: [
                                                        BoxShadow(
                                                          color: Colors.black.withAlpha(14),
                                                          blurRadius: 10,
                                                          offset: const Offset(0, 3),
                                                        ),
                                                      ],
                                                    ),
                                                    child: Text(
                                                      _displayCharacterName(_currentCharacter?.name),
                                                      maxLines: 1,
                                                      softWrap: false,
                                                      overflow: TextOverflow.ellipsis,
                                                      textAlign: TextAlign.center,
                                                      style: const TextStyle(
                                                        fontSize: 14,
                                                        height: 1.0,
                                                        fontWeight: FontWeight.bold,
                                                        color: Colors.black87,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                AnimatedBuilder(
                                  animation: _inputAnimController,
                                  builder: (context, child) {
                                    final animValue = _inputExpandAnimation.value;
                                    final screenWidth = MediaQuery.of(
                                      context,
                                    ).size.width;
                                    const buttonSize = 36.0;
                                    const padding = 12.0;
                                    final buttonLeft =
                                        padding +
                                            (screenWidth - padding * 2 - buttonSize) *
                                                animValue;
                                    final inputWidth =
                                        (screenWidth -
                                            padding * 2 -
                                            buttonSize -
                                            8) *
                                            animValue;

                                    return Stack(
                                      children: [
                                        if (animValue > 0.0)
                                          Positioned(
                                            left: padding,
                                            top: 16,
                                            width: inputWidth,
                                            height: 42,
                                            child: Opacity(
                                              opacity: animValue,
                                              child: ClipRRect(
                                                borderRadius: BorderRadius.circular(
                                                  28,
                                                ),
                                                child: BackdropFilter(
                                                  filter: ImageFilter.blur(
                                                    sigmaX: 20,
                                                    sigmaY: 20,
                                                  ),
                                                  child: Container(
                                                    decoration: BoxDecoration(
                                                      color: Colors.white.withAlpha(
                                                        80,
                                                      ),
                                                      borderRadius:
                                                      BorderRadius.circular(28),
                                                      boxShadow: [
                                                        BoxShadow(
                                                          color: Colors.black12,
                                                          blurRadius: 12,
                                                          offset: const Offset(
                                                            0,
                                                            4,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    child: Row(
                                                      children: [
                                                        if (animValue > 0.3)
                                                          IconButton(
                                                            icon: const Icon(
                                                              Icons.add_outlined,
                                                              color: Colors.grey,
                                                            ),
                                                            onPressed: () =>
                                                                _showExtensionMenu(
                                                                  context,
                                                                ),
                                                            padding:
                                                            EdgeInsets.zero,
                                                            constraints:
                                                            const BoxConstraints(
                                                              minWidth: 32,
                                                              minHeight: 32,
                                                            ),
                                                          ),
                                                        if (animValue > 0.3)
                                                          Flexible(
                                                            child: TextField(
                                                              controller:
                                                              _msgController,
                                                              style:
                                                              const TextStyle(
                                                                fontSize: 15,
                                                              ),
                                                              decoration: const InputDecoration(
                                                                hintText: '输入消息...',
                                                                hintStyle:
                                                                TextStyle(
                                                                  color: Colors
                                                                      .grey,
                                                                ),
                                                                border: InputBorder
                                                                    .none,
                                                                contentPadding:
                                                                EdgeInsets.symmetric(
                                                                  horizontal: 8,
                                                                  vertical: 10,
                                                                ),
                                                              ),
                                                              onChanged: (text) {
                                                                if (_editingIndex !=
                                                                    -1) {
                                                                  setState(() {
                                                                    _messages[_editingIndex]['content'] =
                                                                        text;
                                                                  });
                                                                }
                                                              },
                                                              onSubmitted: (_) =>
                                                                  _sendMessage(),
                                                            ),
                                                          ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        Positioned(
                                          left: buttonLeft,
                                          top: 16,
                                          child: GestureDetector(
                                            onTap: () {
                                              if (!_inputExpanded) {
                                                _inputAnimController.forward();
                                                setState(
                                                      () => _inputExpanded = true,
                                                );
                                              } else {
                                                if (_msgController.text
                                                    .trim()
                                                    .isEmpty) {
                                                  _inputAnimController.reverse();
                                                  setState(
                                                        () => _inputExpanded = false,
                                                  );
                                                } else {
                                                  _sendMessage();
                                                }
                                              }
                                            },
                                            child: ClipOval(
                                              child: BackdropFilter(
                                                filter: ImageFilter.blur(
                                                  sigmaX: 15,
                                                  sigmaY: 15,
                                                ),
                                                child: Container(
                                                  width: buttonSize,
                                                  height: buttonSize,
                                                  decoration: BoxDecoration(
                                                    color: Theme.of(
                                                      context,
                                                    ).primaryColor.withAlpha(220),
                                                    shape: BoxShape.circle,
                                                  ),
                                                  child: Icon(
                                                    !_inputExpanded
                                                        ? Icons.arrow_right_alt
                                                        : _editingIndex != -1
                                                        ? Icons.check
                                                        : Icons.arrow_right_alt,
                                                    color: Colors.white,
                                                    size: 16,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  // ===== scene 场景 UI（顶替聊天页）=====
                  // 排在输入栏之后、开场白之前：
                  // 它要盖住消息流与输入栏，但开场白仍需盖在它上面。
                  _buildSceneAssembly(MediaQuery.of(context).size),
                  // ===== 常驻 UI（extra_sticky）=====
                  // 排在 scene 之后：常驻挂件是「始终可用的工具层」，
                  // 场景再全屏也不该把它埋掉（用户反馈）。
                  // 仍排在开场白之前——开场白要求玩家先确认再进场景。
                  _buildStickyAssemblyLayer(screenWidth),
                  // ===== 伴生叠加层「独立悬浮窗」=====
                  // 排在常驻挂件之后、开场白之前：叠加层要盖住聊天/常驻，
                  // 但开场白仍需优先。
                  _buildCompanionOverlayFloatLayer(
                      MediaQuery.of(context).size),
                  // ===== 开场白 UI（需覆盖输入栏）=====
                  // 必须排在输入栏之后：它要接管整个界面直到玩家确认。
                  _buildOpeningAssembly(MediaQuery.of(context).size),
                  // ===== 状态变化通知（最顶层）=====
                  // 排在最后：升级提示要盖在 scene / 常驻挂件之上，
                  // 被挡住就失去了「告知」的意义。
                  // scene 模式下浮窗照常走顶部（用户确认：盖住就盖住）。
                  StatusNotificationLayer(
                    queue: _notificationQueue,
                    topInset: MediaQuery.of(context).padding.top,
                  ),
                ],
              ),
            ),
          ),
        ),
    );

    return PopScope(
      canPop: true,
      child: Stack(
        children: [
          page,
          if (_guidePhase == _ChatGuidePhase.chat)
            Positioned.fill(
              child: PageGuideOverlay(
                title: '聊天页导览',
                hint: '本页只介绍聊天设置入口。按住细长高光框向左滑动可打开右侧聊天设置页；顶部“退出教程”才会结束教程。',
                targets: _chatGuideTargets(context),
                onExit: _exitGuide,
              ),
            ),
          if (_guidePhase == _ChatGuidePhase.settings)
            Positioned.fill(
              child: PageGuideOverlay(
                title: '聊天设置导览',
                hint: '按住细长高光框向右滑动可返回聊天页；顶部“退出教程”才会结束教程。',
                targets: _chatSettingsGuideTargets(context),
                onExit: _exitGuide,
              ),
            ),
        ],
      ),
    );
  }

  void _startEdit(int index) {
    if (_editingIndex == index) {
      _cancelEdit();
      return;
    }
    if (_editingIndex != -1) {
      _cancelEdit();
    }
    setState(() {
      _editingIndex = index;
      _editingOriginalContent = _messages[index]['content'] as String;
      _msgController.text = _editingOriginalContent;
    });
    if (!_inputExpanded) {
      _inputAnimController.forward();
      setState(() => _inputExpanded = true);
    }
  }

  void _cancelEdit() {
    if (_editingIndex == -1) return;
    setState(() {
      _messages[_editingIndex]['content'] = _editingOriginalContent;
      _msgController.clear();
      _editingIndex = -1;
      _editingOriginalContent = '';
    });
  }

  void _showExtensionMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 24,
              runSpacing: 16,
              children: [
                _buildExtensionItem(
                  icon: Icons.image,
                  label: '图片',
                  onTap: () {
                    Navigator.pop(ctx);
                    // TODO: 接入图片生成/上传
                  },
                ),
                _buildExtensionItem(
                  icon: Icons.mic,
                  label: '语音',
                  onTap: () {
                    Navigator.pop(ctx);
                    // TODO: 接入语音输入
                  },
                ),
                _buildExtensionItem(
                  icon: Icons.camera_alt,
                  label: '拍照',
                  onTap: () {
                    Navigator.pop(ctx);
                    // TODO: 接入拍照功能
                  },
                ),
                _buildExtensionItem(
                  icon: Icons.emoji_emotions,
                  label: '表情',
                  onTap: () {
                    Navigator.pop(ctx);
                    // TODO: 接入表情/贴图
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _openPanel() {
    if (_editingIndex != -1) _cancelEdit(); // ← 新增这一行
    _animController.animateTo(1.0, curve: Curves.easeOut);
  }

  void _closePanel() => _animController.animateTo(0.0, curve: Curves.easeOut);

  void _onHorizontalDragStart(DragStartDetails details) {
    _dragStartOffset = details.globalPosition.dx;
    _panelStartValue = _animController.value;
    _animController.stop();
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    final dx = details.globalPosition.dx - _dragStartOffset;
    final totalMove = panelWidth;
    double newValue = (_panelStartValue - dx / totalMove).clamp(0.0, 1.0);
    _animController.value = newValue;
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (details.primaryVelocity != null && details.primaryVelocity! < -300) {
      _openPanel();
    } else if (details.primaryVelocity != null &&
        details.primaryVelocity! > 300) {
      _closePanel();
    } else if (_animController.value > 0.3) {
      _openPanel();
    } else {
      _closePanel();
    }
  }

  void _exitGuide() {
    setState(() {
      _guidePhase = _ChatGuidePhase.none;
    });
    widget.onExitGuide?.call();
  }

  void _startChatSettingsGuide() {
    _openPanel();
    Future.delayed(const Duration(milliseconds: 320), () {
      if (!mounted) return;
      setState(() {
        _guidePhase = _ChatGuidePhase.settings;
      });
    });
  }

  void _returnToChatGuide() {
    _closePanel();
    Future.delayed(const Duration(milliseconds: 320), () {
      if (!mounted) return;
      setState(() {
        _guidePhase = _ChatGuidePhase.chat;
      });
    });
  }

  Rect _chatSettingsSwipeRect(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Rect.fromLTWH(
      size.width * 0.28,
      size.height * 0.50,
      size.width * 0.44,
      30,
    );
  }

  Rect _chatReturnSwipeRect(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Rect.fromLTWH(
      size.width * 0.28,
      size.height * 0.50,
      size.width * 0.44,
      30,
    );
  }

  Rect _chatCharacterSelectorRect(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bottom = MediaQuery.of(context).padding.bottom;

    // 底部中间的角色名称胶囊区域。
    // 这里不画高光框，只用于放置序号说明，所以取一个更贴近名称胶囊的小区域。
    return Rect.fromLTWH(
      size.width * 0.42,
      size.height - bottom - 60,
      size.width * 0.16,
      34,
    );
  }

  Rect _chatInputAreaRect(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bottom = MediaQuery.of(context).padding.bottom;

    // 底部输入区域。这里只用于放置说明序号，不画高光框。
    return Rect.fromLTWH(
      12,
      size.height - bottom - 66,
      size.width - 24,
      46,
    );
  }

  List<PageGuideTarget> _chatGuideTargets(BuildContext context) {
    return [
      PageGuideTarget(
        id: 'chat_settings_swipe',
        order: 1,
        rect: _chatSettingsSwipeRect(context),
        title: '侧滑打开聊天设置',
        description: '按住这个细长高光框向左滑动，可以打开右侧聊天设置页。聊天设置里可以进入当前角色用户设定、Prompt 策略、背景设置和清空历史。',
        onSwipeLeft: _startChatSettingsGuide,
      ),
      PageGuideTarget(
        id: 'chat_character_selector',
        order: 2,
        rect: _chatCharacterSelectorRect(context),
        title: '当前角色 / 角色切换',
        description: '这里显示当前聊天角色名称。点击角色名称可以打开角色切换轮盘，用来切换当前聊天对象。',
        showHighlight: false,
      ),
      PageGuideTarget(
        id: 'chat_input_area',
        order: 3,
        rect: _chatInputAreaRect(context),
        title: '输入与发送',
        description: '点击底部输入按钮可以展开输入框。输入内容后再次点击发送按钮即可发送消息。这里不做高光框，避免遮挡输入区域。',
        showHighlight: false,
      ),
    ];
  }

  List<PageGuideTarget> _chatSettingsGuideTargets(BuildContext context) {
    return [
      PageGuideTarget(
        id: 'chat_settings_back_swipe',
        order: 1,
        rect: _chatReturnSwipeRect(context),
        title: '滑动返回聊天页',
        description: '按住这个细长高光框向右滑动，可以从聊天设置页返回聊天页。',
        onSwipeRight: _returnToChatGuide,
      ),
    ];
  }

  Widget _buildMarkdownWidget(String text) {
    // 含 HTML 标签（如导入的酒馆卡开场白 <img>/<div>/<h1>/<br>）→ 走 HTML 渲染。
    if (_looksLikeHtml(text)) {
      return _buildHtmlWidget(text);
    }

    if (!_looksLikeComplexMarkdown(text)) {
      return _buildStyledRoleplayText(text);
    }

    return MarkdownBody(
      data: text,
      selectable: true,
      extensionSet: md.ExtensionSet.gitHubFlavored,
      onTapLink: (text, href, title) {
        if (href != null && href.startsWith('action://')) {
          final action = href.substring('action://'.length);
          _handleMarkdownAction(action);
        }
      },
    );
  }

  /// 粗略判断内容是否包含 HTML 标签。只认常见的块/图片/排版标签，
  /// 避免把普通文本里的 < > 误判（比如 "1<2"）。
  bool _looksLikeHtml(String text) {
    return RegExp(
      r'<\s*(img|div|span|h[1-6]|p|br|b|i|strong|em|a|ul|ol|li|center|font|hr|table)'
      r'(\s[^>]*)?/?\s*>',
      caseSensitive: false,
    ).hasMatch(text);
  }

  /// 用 flutter_html 渲染开场白 / 消息里的 HTML（档位 A：图片 / 标题 / 加粗 / 链接 / 简单排版）。
  ///
  /// 本地优先原则：图片仅显示本地资产（file:// 或本地绝对路径），
  /// 外链（http/https）运行时不联网加载，降级为占位文字。
  /// 转译工具会把外链图片下载内嵌成本地路径，届时即可正常显示。
  Widget _buildHtmlWidget(String text) {
    // ① 先做 {{char}} / {{user}} 等宏替换（HTML 路径之前漏了）。
    var html = _renderPromptTemplate(text);
    // ② 规范化无引号属性：第三方卡常写 <img src=data:...> / <div style=a:b;c:d>，
    //    HTML 解析器遇到无引号属性里的特殊字符（; : , 等）会截断，导致 data URI /
    //    样式失效。这里把 src= 与 style= 的无引号值补上引号。
    html = _quoteUnquotedAttrs(html);
    // ③ 把裸换行符转成 <br>：第三方卡常用 \n 换行，但 HTML 不认 \n。
    //    标签之间的 \n（>\s*<）属于排版空白，去掉以免产生多余空行；
    //    其余文本中的 \n 转为 <br>，还原作者的换行意图。
    html = html.replaceAll(RegExp(r'>\s*\n\s*<'), '><');
    html = html.replaceAll('\n', '<br>');

    return fhtml.Html(
      data: html,
      // 禁止渲染脚本 / 样式块等无意义或有风险的标签。
      onLinkTap: (url, attributes, element) {
        if (url == null) return;
        if (url.startsWith('action://')) {
          _handleMarkdownAction(url.substring('action://'.length));
          return;
        }
        // 外部链接：本地优先，不跳转外部浏览器，仅提示链接地址。
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('该链接指向外部网站，已忽略：$url'),
            duration: const Duration(seconds: 3),
          ),
        );
      },
      extensions: [
        fhtml.TagExtension(
          tagsToExtend: {'img'},
          builder: (ctx) {
            final src = ctx.attributes['src'] ?? '';
            return _buildHtmlImage(src);
          },
        ),
      ],
      style: {
        'body': fhtml.Style(
          margin: fhtml.Margins.zero,
          padding: fhtml.HtmlPaddings.zero,
          fontSize: fhtml.FontSize(12.5),
          lineHeight: fhtml.LineHeight(1.25),
          color: Colors.black87,
        ),
        // 标题默认很大很占高度，整体压扁。
        'h1': fhtml.Style(
          fontSize: fhtml.FontSize(17),
          margin: fhtml.Margins.symmetric(vertical: 4),
          lineHeight: fhtml.LineHeight(1.2),
        ),
        'h2': fhtml.Style(
          fontSize: fhtml.FontSize(15),
          margin: fhtml.Margins.symmetric(vertical: 3),
          lineHeight: fhtml.LineHeight(1.2),
        ),
        'h3': fhtml.Style(
          fontSize: fhtml.FontSize(13.5),
          margin: fhtml.Margins.symmetric(vertical: 2),
        ),
        // 段落上下间距收紧。
        'p': fhtml.Style(
          margin: fhtml.Margins.symmetric(vertical: 3),
        ),
        // 分隔线压扁。
        'hr': fhtml.Style(
          margin: fhtml.Margins.symmetric(vertical: 4),
        ),
        // 链接：橙色，贴近常见卡片风格。
        'a': fhtml.Style(
          color: const Color(0xFFE8833A),
          textDecoration: TextDecoration.none,
        ),
      },
    );
  }

  /// HTML 图片：本地路径 / data URI 正常显示；外链降级为占位（不联网）。
  /// 给 src= / style= 等属性的无引号值补上双引号。
  /// HTML 解析器对无引号属性遇到 ; : , 等会截断，导致 data URI / 内联样式失效。
  String _quoteUnquotedAttrs(String html) {
    // 匹配 属性名= 后面紧跟一个非引号、非空白的值（无引号），值取到空白或 > 之前。
    // 适用于 data URI / url() 等不含空格的长值。
    final re = RegExp(
      r'''\b(src|style|href|width|height)\s*=\s*(?!["'])([^\s>]+)''',
      caseSensitive: false,
    );
    return html.replaceAllMapped(re, (m) {
      final name = m.group(1);
      final value = m.group(2)!;
      return '$name="$value"';
    });
  }

  Widget _buildHtmlImage(String src) {
    final s = src.trim();

    // 限制开场白内嵌图片的最大高度，避免单张立绘占满整屏。
    Widget wrap(Widget img) => ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240),
            child: img,
          ),
        );

    // data:image/...;base64,xxxx —— 图片内嵌在文本里，无需联网，直接解码显示。
    if (s.startsWith('data:image')) {
      final idx = s.indexOf('base64,');
      if (idx != -1) {
        try {
          final bytes = base64Decode(s.substring(idx + 7));
          return wrap(Image.memory(bytes, fit: BoxFit.contain));
        } catch (_) {
          return _imagePlaceholder('图片数据无法解码');
        }
      }
    }

    String? localPath;
    if (s.startsWith('file://')) {
      localPath = Uri.tryParse(s)?.toFilePath();
    } else if (s.isNotEmpty &&
        !s.startsWith('http://') &&
        !s.startsWith('https://') &&
        !s.startsWith('data:')) {
      // 直接是本地绝对路径
      localPath = s;
    }

    if (localPath != null && localPath.isNotEmpty) {
      final file = File(localPath);
      if (file.existsSync()) {
        return wrap(Image.file(file, fit: BoxFit.contain));
      }
    }

    // 外链 / 不可用：占位（保持本地、不暴露隐私）。
    return _imagePlaceholder('外链图片（未内嵌）');
  }

  Widget _imagePlaceholder(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black.withAlpha(20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.image_not_supported_outlined,
              size: 16, color: Colors.black.withAlpha(120)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: Colors.black.withAlpha(140)),
            ),
          ),
        ],
      ),
    );
  }

  bool _looksLikeComplexMarkdown(String text) {
    final trimmed = text.trim();

    return trimmed.contains('|') ||
        trimmed.contains('```') ||
        trimmed.contains(RegExp(r'^\s*[-*+]\s+', multiLine: true)) ||
        trimmed.contains(RegExp(r'^\s*#{1,6}\s+', multiLine: true)) ||
        trimmed.contains(RegExp(r'\[[^\]]+\]\([^)]+\)'));
  }

  /// 对白高亮：按角色卡配置的正则规则着色。
  ///
  /// 规则可由作者在「文本着色」页自定义；没配过时用内置默认四条
  /// （台词 / 心理活动 / 书名 / 系统提示），与改造前观感一致。
  Widget _buildStyledRoleplayText(String text) {
    const baseStyle = TextStyle(
      fontSize: 14,
      height: 1.45,
      color: Colors.black87,
      decoration: TextDecoration.none,
    );

    final rules = _currentCharacter?.meta.effectiveHighlightRules ??
        TextHighlightRule.defaults();

    return SelectableText.rich(
      TextHighlightEngine.buildSpan(text, rules, baseStyle),
    );
  }

  List<OpeningGreeting> _getCurrentGreetings() {
    if (_currentCharacter == null) return [];
    try {
      final list =
          jsonDecode(
                _currentCharacter!.openingGreetings.isEmpty
                    ? '[]'
                    : _currentCharacter!.openingGreetings,
              )
              as List;
      return list.map((e) => OpeningGreeting.fromJson(e)).toList();
    } catch (_) {
      return [];
    }
  }

  bool _isGreetingMessage(Map<String, dynamic> msg) {
    if (msg['role'] != 'assistant') return false;
    final content = msg['content'] as String? ?? '';
    if (content.isEmpty) return false;
    final greetings = _getCurrentGreetings();
    return greetings.any((g) => g.content == content);
  }

  /// 处理 Markdown 中 action:// 开头的动作
  void _handleMarkdownAction(String action) {
    switch (action) {
      case 'retry':
        // 重试最后一次 AI 回复（对应你的重新生成逻辑）
        final lastAiIndex = _messages.lastIndexWhere(
          (m) => m['role'] == 'assistant',
        );
        if (lastAiIndex != -1) {
          _regenerateMessage(lastAiIndex);
        }
        break;
      case 'continue':
        final lastAiIndex = _messages.lastIndexWhere(
          (m) => m['role'] == 'assistant',
        );
        if (lastAiIndex != -1) {
          _continueMessage(lastAiIndex);
        }
        break;
      // 后续可扩展更多动作
      default:
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('未知动作: $action')));
    }
  }

  Future<void> _scrollToBottom({bool animated = true}) async {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final double target = position.maxScrollExtent;

    if (animated) {
      await _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } else {
      _scrollController.jumpTo(target);
    }

    await Future.delayed(const Duration(milliseconds: 50));
    if (_scrollController.hasClients) {
      final double stableMax = _scrollController.position.maxScrollExtent;
      if ((stableMax - target).abs() > 1.0) {
        _scrollController.jumpTo(stableMax);
      }
    }
  }

  Future<void> _switchCharacter(CharacterCard newChar) async {
    if (_currentCharacter?.id == newChar.id) return;
    await _setCurrentCharacter(newChar);
    setState(() {}); // 触发背景刷新
  }

  Future<void> _saveEdit() async {
    if (_isLoading) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('正在生成回复，请稍候')),
      );
      return;
    }
    if (_editingIndex == -1) return;
    final newText = _msgController.text.trim();
    if (newText.isEmpty) return;
    if (newText == _editingOriginalContent) {
      _cancelEdit();
      return;
    }

    final userIndex = _editingIndex;

    // 收集从 userIndex 到列表末尾的所有消息索引（整个尾部）
    final List<int> indicesToRemove = List.generate(
      _messages.length - userIndex,
      (i) => userIndex + i,
    );

    // 收集这些消息的数据库 id
    final List<int> idsToDelete = [];
    for (final i in indicesToRemove) {
      final msg = _messages[i];
      if (msg.containsKey('versionIds')) {
        final versionIds = List<String>.from(msg['versionIds'] as List);
        for (final vid in versionIds) {
          final id = int.tryParse(vid);
          if (id != null) idsToDelete.add(id);
        }
      } else {
        final id = int.tryParse(msg['id'] ?? '');
        if (id != null) idsToDelete.add(id);
      }
    }

    // 回滚状态：被删除的这批消息里，取最早那条的「结算前快照」，
    // 把会话状态还原到它们产生之前，避免已撤回回合的状态变化残留。
    await _rollbackSessionStateFor(idsToDelete);

    // 从数据库删除
    for (final id in idsToDelete) {
      await DatabaseService.deleteMessage(id);
    }

    // 从 UI 删除尾部，再插入新用户消息
    setState(() {
      _messages.removeRange(userIndex, _messages.length);
      _messages.insert(userIndex, {'role': 'user', 'content': newText});
      _editingIndex = -1;
      _editingOriginalContent = '';
      _msgController.clear();
    });

    if (_currentCharacter != null) {
      await DatabaseService.insertMessage(
        characterId: _currentCharacter!.id,
        role: 'user',
        content: newText,
      );
    }
    _requestAiReply();
  }

  /// A10-5：由 scene UI 触发发送消息。
  ///
  /// 与 `_sendMessage` 的区别：文本来自 UI 组件而非输入框控制器。
  /// scene 完全顶替聊天页后，原生输入框被禁用，
  /// 玩家只能通过作者摆放的组件与 LLM 对话。
  Future<void> _sendMessageFromAssembly(String rawText) async {
    final text = rawText.trim();
    if (text.isEmpty) return;
    if (_isLoading) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('正在生成回复，请稍候')),
      );
      return;
    }

    setState(() {
      _messages.add({'role': 'user', 'content': text});
      _isLoading = true;
    });

    if (_currentCharacter != null) {
      await DatabaseService.insertMessage(
        characterId: _currentCharacter!.id,
        role: 'user',
        content: text,
      );
    }
    _requestAiReply();
  }

  Future<void> _sendMessage() async {
    if (_isLoading) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('正在生成回复，请稍候')),
      );
      return;
    }

    if (_editingIndex != -1) {
      _saveEdit();
      return;
    }
    final text = _msgController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add({'role': 'user', 'content': text});
      _msgController.clear();
      _isLoading = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });

    // ✅ 修复：使用 _currentCharacter 而不是 widget.character
    if (_currentCharacter != null) {
      await DatabaseService.insertMessage(
        characterId: _currentCharacter!.id,
        role: 'user',
        content: text,
      );
    }
    _requestAiReply();
  }

  Future<void> _requestAiReply() async {
    final config = await ApiConfigService.getActiveConfig();
    if (config == null || config.apiKey.isEmpty) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('请先配置 API')));
      }
      return;
    }
    final module = context.read<ChatModule>();

    // 构建请求消息列表（基于当前对话）
    final requestMessages = _messages
        .map(
          (m) => {
            'role': m['role'] as String,
            'content': m['content'] as String,
          },
        )
        .toList();

    String finalSystemPrompt = await _buildFinalSystemPrompt();

    // 历史后注入：把角色卡的 post_history_instructions 追加到消息末尾
    final requestMessagesWithPhi =
        _withPostHistoryInstructions(requestMessages);

    String aiResponseContent = '';
    setState(() => _isLoading = true);

    await _aiReplySub?.cancel();
    _aiReplySub = null;

    _aiReplySub =
        module.sendMessage(finalSystemPrompt, requestMessagesWithPhi).listen(
          (chunk) {
        if (!mounted) return;

        aiResponseContent += chunk;
        setState(() {});
      },
      onDone: () async {
        if (!mounted) return;

        _aiReplySub = null;

        // 状态栏：解析变化量并算账，得到剥离技术标记后的展示文本。
        // 必须在结算之前取快照：它代表「产生这条消息之前」的状态，
        // 撤回该消息时据此回滚。
        final stateBefore = _sessionState.toJsonString();

        var displayContent = await _processStatusBarReply(aiResponseContent);
        if (!mounted) return;
        // 界面数据通道：同样解析 → 算账 → 按应用策略分流。
        displayContent = await _processUIChannelReply(displayContent);
        if (!mounted) return;

        setState(() {
          _messages.add({
            'role': 'assistant',
            'content': displayContent,
          });
          _isLoading = false;
        });

        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToBottom();
        });

        if (_currentCharacter != null && displayContent.isNotEmpty) {
          DatabaseService.insertMessage(
            characterId: _currentCharacter!.id,
            role: 'assistant',
            content: displayContent,
            stateSnapshot: stateBefore,
          );
        }
      },
      onError: (e) {
        if (!mounted) return;

        _aiReplySub = null;

        setState(() {
          _messages.add({
            'role': 'assistant',
            'content': '错误: $e',
          });
          _isLoading = false;
        });
      },
    );
  }

  Future<void> _scrollToBottomWhenReady() async {
    await Future.delayed(const Duration(milliseconds: 100));
    if (mounted) {
      await _scrollToBottom(animated: false);
    }
  }

  Future<void> _loadHistory() async {
    if (_currentCharacter == null) return;
    final rawMessages = await DatabaseService.getMessages(
      _currentCharacter!.id,
    );
    final List<Map<String, dynamic>> processed = [];

    for (final m in rawMessages) {
      final role = m['role'] as String;
      final content = m['content'] as String;
      final id = m['id'].toString();
      final version = (m['version'] as int?) ?? 1;

      if (role == 'assistant' &&
          processed.isNotEmpty &&
          processed.last['role'] == 'assistant') {
        final last = processed.last;
        if (last['versions'] == null) {
          last['versions'] = <String>[last['content']];
          last['versionIds'] = <String>[last['id'].toString()];
          last['currentVersionIndex'] = 0;
        }
        (last['versions'] as List<String>).add(content);
        (last['versionIds'] as List<String>).add(id);
        last['content'] = content;
        last['id'] = id;
        last['currentVersionIndex'] =
            (last['versions'] as List<String>).length - 1;
      } else {
        processed.add({
          'id': id,
          'role': role,
          'content': content,
          'version': version,
        });
      }
    }

    setState(() {
      _messages.clear();
      _messages.addAll(processed.cast<Map<String, dynamic>>());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottomWhenReady();
    });
  }

  Future<void> _deleteUserMessage(int userIndex) async {
    if (userIndex < 0 || userIndex >= _messages.length) return;
    final userMsg = _messages[userIndex];
    if (userMsg['role'] != 'user') return;

    // 收集要删除的条目索引：从当前用户消息开始，直到下一个用户消息之前
    final List<int> indicesToRemove = [];
    for (int i = userIndex; i < _messages.length; i++) {
      final msg = _messages[i];
      if (msg['role'] == 'user' && i != userIndex) break;
      indicesToRemove.add(i);
    }

    // 收集要删除的数据库 id
    final List<int> idsToDelete = [];
    for (final i in indicesToRemove) {
      final msg = _messages[i];
      if (msg.containsKey('versionIds')) {
        final versionIds = List<String>.from(msg['versionIds'] as List);
        for (final vid in versionIds) {
          final id = int.tryParse(vid);
          if (id != null) idsToDelete.add(id);
        }
      } else {
        final id = int.tryParse(msg['id'] ?? '');
        if (id != null) idsToDelete.add(id);
      }
    }

    // 回滚这轮对话产生的状态变化，避免撤回后残留。
    await _rollbackSessionStateFor(idsToDelete);

    // 从数据库删除
    for (final id in idsToDelete) {
      await DatabaseService.deleteMessage(id);
    }

    // 从 UI 删除
    setState(() {
      _messages.removeRange(indicesToRemove.first, indicesToRemove.last + 1);
    });
  }

  Future<void> _regenerateMessage(int aiIndex) async {
    if (aiIndex <= 0 || aiIndex >= _messages.length) return;

    final prevMsg = _messages[aiIndex - 1];
    if (prevMsg['role'] != 'user') return;

    final oldAiMsg = _messages[aiIndex];

    int newVersion = 2;
    if (oldAiMsg.containsKey('versions')) {
      final versions = oldAiMsg['versions'] as List<String>;
      newVersion = versions.length + 1;
    }

    final module = context.read<ChatModule>();

    // 关键：重新生成也必须使用完整系统提示词
    final systemPrompt = await _buildFinalSystemPrompt();

    // 关键：只取旧 AI 回复之前的上下文，保留之前的 assistant 历史
    final requestMessages = _messages
        .take(aiIndex)
        .where((m) => m['role'] != null)
        .map(
          (m) => {
        'role': m['role'] as String,
        'content': m['content'] as String,
      },
    )
        .toList();

    String aiResponseContent = '';
    setState(() => _isLoading = true);

    module
        .sendMessage(
            systemPrompt, _withPostHistoryInstructions(requestMessages))
        .listen(
          (chunk) {
        aiResponseContent += chunk;
        setState(() {});
      },
      onDone: () async {
        if (aiResponseContent.isEmpty) {
          setState(() => _isLoading = false);
          return;
        }

        // 重新生成：仅剥离状态变化技术标记用于展示，不再次应用变化量，
        // 避免对同一回合重复算账（状态值以首次回复为准）。
        final displayContent = DataChannelUpdateEngine.stripFromReply(
          StatusBarEngine.stripFromReply(aiResponseContent),
        );

        int? newMsgId;
        if (_currentCharacter != null) {
          newMsgId = await DatabaseService.insertMessage(
            characterId: _currentCharacter!.id,
            role: 'assistant',
            content: displayContent,
            version: newVersion,
          );
        }

        setState(() {
          if (oldAiMsg['versions'] == null) {
            oldAiMsg['versions'] = <String>[oldAiMsg['content']];
            oldAiMsg['versionIds'] = <String>[oldAiMsg['id'].toString()];
          }

          (oldAiMsg['versions'] as List<String>).add(displayContent);
          (oldAiMsg['versionIds'] as List<String>).add(
            newMsgId?.toString() ?? '',
          );

          oldAiMsg['content'] = displayContent;
          oldAiMsg['id'] = newMsgId?.toString() ?? '';
          oldAiMsg['currentVersionIndex'] =
              (oldAiMsg['versions'] as List<String>).length - 1;

          _isLoading = false;
        });
      },
      onError: (e) {
        setState(() {
          _isLoading = false;
        });
      },
    );
  }

  Future<void> _continueMessage(int aiIndex) async {
    if (aiIndex < 0 || aiIndex >= _messages.length) return;
    final aiMsg = _messages[aiIndex];
    final currentContent = aiMsg['content'] as String;
    final curIdStr = aiMsg['id'] as String?;
    final curId = curIdStr != null ? int.tryParse(curIdStr) : null;

    final module = context.read<ChatModule>();
    final systemPrompt = await _buildFinalSystemPrompt();

    final requestMessages = _messages
        .where((m) => m['role'] != null && m['role'] != 'assistant')
        .map(
          (m) => {
            'role': m['role'] as String,
            'content': m['content'] as String,
          },
        )
        .toList();
    requestMessages.add({'role': 'assistant', 'content': currentContent});
    requestMessages.add({'role': 'user', 'content': '请接着上面继续写，不要重复，直接续写'});

    String aiResponseContent = '';
    setState(() => _isLoading = true);

    module
        .sendMessage(
            systemPrompt, _withPostHistoryInstructions(requestMessages))
        .listen(
          (chunk) {
            aiResponseContent += chunk;
            setState(() {});
          },
          onDone: () async {
            if (aiResponseContent.isEmpty) {
              setState(() => _isLoading = false);
              return;
            }
            // 续写：剥离续写部分可能出现的状态变化标记（不重复算账）。
            final appended = DataChannelUpdateEngine.stripFromReply(
              StatusBarEngine.stripFromReply(aiResponseContent),
            );
            final newFullContent = '$currentContent\n$appended';
            if (curId != null) {
              await DatabaseService.updateMessageContent(curId, newFullContent);
            }
            setState(() {
              aiMsg['content'] = newFullContent;
              if (aiMsg['versions'] != null) {
                final versions = List<String>.from(aiMsg['versions'] as List);
                final curIdx = aiMsg['currentVersionIndex'] as int? ?? 0;
                if (curIdx >= 0 && curIdx < versions.length) {
                  versions[curIdx] = newFullContent;
                  aiMsg['versions'] = versions;
                }
              }
              _isLoading = false;
            });
          },
          onError: (e) {
            setState(() => _isLoading = false);
          },
        );
  }

  Widget _buildExtensionItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, size: 28, color: Colors.grey[700]),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

class _FanCard {
  final CharacterCard character;
  final double t;
  double _x = 0.0;
  double _y = 0.0;
  double _arcS = 0.0; // 弧长位置
  int _index = 0; // 在 _selectableCharacters 中的索引

  _FanCard({required this.character, required this.t});
}

/// 状态栏块顶部的"固定方向"细滑块。
///
/// - 轨道很细（约 4px），滑块直径不超过轨道直径（4px）。
/// - 三档：左（固定到长条左侧）/ 中（不固定）/ 右（固定到长条右侧）。
/// - 滑块颜色：中为灰，向左 / 向右渐变为两种不同颜色。
/// - 平时隐藏轨道，只露出一个很小的滑块；按下 / 拖动时才显示轨道。
class _PinSlider extends StatefulWidget {
  final String pinSide; // 'none' | 'left' | 'right'
  final ValueChanged<String> onChanged;
  const _PinSlider({required this.pinSide, required this.onChanged});

  @override
  State<_PinSlider> createState() => _PinSliderState();
}

class _PinSliderState extends State<_PinSlider> {
  bool _active = false; // 是否正在交互（显示轨道）
  double? _dragT; // 拖动中的归一化位置 0(左)~0.5(中)~1(右)

  // 触摸热区高度（块上半空白区，便于点中且干扰最小）。
  static const double _hitH = 22;
  // 轨道很细（参考进度条），滑块直径不超过轨道直径。
  static const double _trackH = 5;
  static const double _thumb = 7;
  // 轨道左右内边距（让轨道不顶到块边缘）。
  static const double _padX = 10;

  double _sideToT(String side) {
    switch (side) {
      case 'left':
        return 0.0;
      case 'right':
        return 1.0;
      default:
        return 0.5;
    }
  }

  String _tToSide(double t) {
    if (t < 0.33) return 'left';
    if (t > 0.67) return 'right';
    return 'none';
  }

  Color _colorForT(double t) {
    if (t < 0.33) return const Color(0xFF4F8DF7); // 左：蓝
    if (t > 0.67) return const Color(0xFFF77F4F); // 右：橙
    return Colors.black26; // 中：灰
  }

  void _commit(double t) {
    final side = _tToSide(t);
    if (side != widget.pinSide) widget.onChanged(side);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      // 轨道可用宽度（两侧留 _padX）。
      final trackW = (w - _padX * 2).clamp(0.0, w);
      final usable = (trackW - _thumb).clamp(0.0, trackW);
      final t = _dragT ?? _sideToT(widget.pinSide);
      final thumbLeft = _padX + usable * t;
      final color = _colorForT(t);

      double posToT(double dx) {
        final local = (dx - _padX - _thumb / 2).clamp(0.0, usable);
        return usable == 0 ? 0.5 : local / usable;
      }

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        // 处理横向拖动；放在子节点能赢得手势竞技，阻止冒泡到外层（避免误触发滑出设置页）。
        onHorizontalDragStart: (_) => setState(() => _active = true),
        onHorizontalDragUpdate: (d) {
          setState(() => _dragT = posToT(d.localPosition.dx));
        },
        onHorizontalDragEnd: (_) {
          final cur = _dragT ?? _sideToT(widget.pinSide);
          final snapped = cur < 0.33 ? 0.0 : (cur > 0.67 ? 1.0 : 0.5);
          _commit(snapped);
          setState(() {
            _active = false;
            _dragT = null;
          });
        },
        onHorizontalDragCancel: () => setState(() {
          _active = false;
          _dragT = null;
        }),
        onTapDown: (_) => setState(() => _active = true),
        onTapUp: (d) {
          // 点击三等分直接切换左 / 中 / 右
          final x = d.localPosition.dx;
          final third = w / 3;
          final side = x < third ? 'left' : (x > third * 2 ? 'right' : 'none');
          if (side != widget.pinSide) widget.onChanged(side);
          setState(() => _active = false);
        },
        onTapCancel: () => setState(() => _active = false),
        child: SizedBox(
          height: _hitH,
          width: double.infinity,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              // 轨道：仅在交互时显示
              Positioned(
                left: _padX,
                right: _padX,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 150),
                  opacity: _active ? 1.0 : 0.0,
                  child: Container(
                    height: _trackH,
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(28),
                      borderRadius: BorderRadius.circular(_trackH / 2),
                    ),
                  ),
                ),
              ),
              // 滑块（始终可见，位置反映当前 pinSide）
              Positioned(
                left: thumbLeft,
                child: AnimatedContainer(
                  duration: _dragT == null
                      ? const Duration(milliseconds: 180)
                      : Duration.zero,
                  width: _thumb,
                  height: _thumb,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}

/// 低阈值全向拖动识别器（挂件把手与悬浮球专用）。
///
/// 解决两个连带症状：
///   1. **要拖一段距离才跟手**：默认 Pan 要移动超过 `kTouchSlop`（18px）
///      才确认手势，起手那段位移被吞掉，显得迟钝。
///   2. **有时拖不动**：在那段等待期内，外层的 `HorizontalDragGestureRecognizer`
///      （聊天页滑出侧栏、挂件的水平吸收器）同样在等 18px——
///      两者几乎同时到达阈值，而专用识别器优先于通用 Pan，
///      于是外层常常先赢，表现为时灵时不灵。
///
/// 处理：把自己的判定阈值降到 6px，抢在外层的 18px 之前拿下竞技场。
///
/// 为什么不在 `addAllowedPointer` 里直接 `resolve(accepted)`：
/// 那样会立刻淘汰同一竞技场里的 `TapGestureRecognizer`，
/// 悬浮球的「点击展开」就再也不会触发了。
/// 保留阈值判定，静止时不产生位移 → Tap 正常获胜；
/// 一旦移动超过 6px → 本识别器获胜，两种交互得以共存。
class _EagerPanRecognizer extends PanGestureRecognizer {
  /// 低于系统默认 18px，但高到足以容忍点击时的手指抖动。
  static const double _slop = 6.0;

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) {
    return globalDistanceMoved.abs() > _slop;
  }
}
