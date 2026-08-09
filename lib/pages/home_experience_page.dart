import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/character_card.dart';
import '../services/background_service.dart';
import '../services/database_service.dart';
import '../shared/theme/app_theme_manager.dart';
import '../shared/theme/app_theme_tokens.dart';
import 'background_library_page.dart';
import 'character_library_page.dart';
import 'world_book_library_page.dart';
import 'ui_asset_gallery.dart';
import 'chat_page.dart';

/// A mobile-first experience home.
///
/// The page is intentionally a stage rather than a feature dashboard:
/// the current role is the primary entry point, while management modules stay
/// in the lower-right rail. The existing MainMenuPage continues to own the
/// top-level settings side-swipe and guide overlay.
class HomeExperiencePage extends StatefulWidget {
  const HomeExperiencePage({
    super.key,
    this.chatTileKey,
    this.characterTileKey,
    this.worldBookTileKey,
    this.backgroundTileKey,
    this.chatTextKey,
    this.characterTextKey,
    this.worldBookTextKey,
    this.backgroundTextKey,
  });

  final GlobalKey? chatTileKey;
  final GlobalKey? characterTileKey;
  final GlobalKey? worldBookTileKey;
  final GlobalKey? backgroundTileKey;
  final GlobalKey? chatTextKey;
  final GlobalKey? characterTextKey;
  final GlobalKey? worldBookTextKey;
  final GlobalKey? backgroundTextKey;

  @override
  State<HomeExperiencePage> createState() => _HomeExperiencePageState();
}

class _HomeExperiencePageState extends State<HomeExperiencePage>
    with TickerProviderStateMixin {
  static const _activeCharacterPreferenceKey = 'home_active_character_id';

  // Entrance choreography timings, mapped from the HTML prototype.
  static const _brandBegin = 0.044;
  static const _themeBegin = 0.100;
  static const _roleBegin = 0.150;
  static const _stageBegin = 0.294;
  static const _railBegin = 0.383;
  static const _itemBase = 0.433;
  static const _itemStep = 0.056;
  static const _span = 0.34;

  List<CharacterCard> _characters = const <CharacterCard>[];
  Map<String, int> _lastMessageAt = const <String, int>{};
  CharacterCard? _activeCharacter;
  int _worldBookCount = 0;
  int _backgroundCount = 0;
  int _uiAssemblyCount = 0;
  bool _loading = true;
  bool _roleSelecting = false;
  String? _pendingRoleId;
  String? _promotingRoleId;
  Object? _error;

  late final AnimationController _entrance;
  late final AnimationController _cover;
  bool _entranceReady = false;
  Timer? _promoteTimer;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _cover = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 16),
    )..repeat(reverse: true);
    _loadHomeData();
  }

  @override
  void dispose() {
    _promoteTimer?.cancel();
    _entrance.dispose();
    _cover.dispose();
    super.dispose();
  }

  Future<void> _loadHomeData() async {
    try {
      final rawCharacters = await DatabaseService.getAllCharacters();
      final timestamps = await DatabaseService.getLatestMessageTimestamps();
      final worldBooks = await DatabaseService.getAllWorldBooks();
      final backgrounds = await BackgroundService.getAll();
      final preferences = await SharedPreferences.getInstance();
      final persistedId = preferences.getString(_activeCharacterPreferenceKey);
      final lastActiveId =
          persistedId ?? await DatabaseService.getLastActiveCharacterId();

      final characters = rawCharacters
          .map(CharacterCard.fromDb)
          .toList(growable: true);
      characters.sort((a, b) {
        final left = timestamps[a.id] ?? 0;
        final right = timestamps[b.id] ?? 0;
        if (left != right) return right.compareTo(left);
        return a.name.compareTo(b.name);
      });

      CharacterCard? active;
      if (lastActiveId != null) {
        for (final character in characters) {
          if (character.id == lastActiveId) {
            active = character;
            break;
          }
        }
      }
      active ??= characters.isNotEmpty ? characters.first : null;

      var uiCount = 0;
      for (final character in characters) {
        uiCount += character.meta.uiAssemblies.length;
      }

      if (!mounted) return;
      setState(() {
        _characters = characters;
        _lastMessageAt = timestamps;
        _activeCharacter = active;
        _worldBookCount = worldBooks.length;
        _backgroundCount = backgrounds.length;
        _uiAssemblyCount = uiCount;
        _loading = false;
        _error = null;
      });
      _scheduleEntrance();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error;
      });
      _scheduleEntrance();
    }
  }

  void _scheduleEntrance() {
    if (_entranceReady) return;
    _entranceReady = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _entrance.forward();
    });
  }

  Future<void> _openCharacterLibrary() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const CharacterLibraryPage()),
    );
    _loadHomeData();
  }

  Future<void> _openWorldBookLibrary() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const WorldBookLibraryPage()),
    );
    _loadHomeData();
  }

  Future<void> _openBackgroundLibrary() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const BackgroundLibraryPage()),
    );
    _loadHomeData();
  }

  Future<void> _openUIAssetGallery() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const UIAssetGallery()),
    );
    _loadHomeData();
  }

  Future<void> _openChat() async {
    final character = _activeCharacter;
    if (character == null) {
      await _openCharacterLibrary();
      return;
    }

    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => ChatPage(character: character)),
    );
    _loadHomeData();
  }

  void _openRoleSelection() {
    final character = _activeCharacter;
    if (character == null) {
      _openCharacterLibrary();
      return;
    }

    setState(() {
      _pendingRoleId = character.id;
      _roleSelecting = true;
    });
  }

  void _cancelRoleSelection() {
    if (!mounted) return;
    _promoteTimer?.cancel();
    setState(() {
      _pendingRoleId = null;
      _promotingRoleId = null;
      _roleSelecting = false;
    });
  }

  Future<void> _selectRolePlane(CharacterCard character) async {
    if (_pendingRoleId == character.id) {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_activeCharacterPreferenceKey, character.id);
      if (!mounted) return;
      setState(() {
        _activeCharacter = character;
        _pendingRoleId = null;
        _promotingRoleId = null;
        _roleSelecting = false;
      });
      return;
    }

    _promoteTimer?.cancel();
    setState(() {
      _pendingRoleId = character.id;
      _promotingRoleId = character.id;
    });
    _promoteTimer = Timer(const Duration(milliseconds: 420), () {
      if (mounted) setState(() => _promotingRoleId = null);
    });
  }

  String _relativeTime(String characterId) {
    final timestamp = _lastMessageAt[characterId];
    if (timestamp == null || timestamp <= 0) return '尚未开始聊天';

    final elapsed = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(timestamp),
    );
    if (elapsed.inMinutes < 1) return '刚刚聊过';
    if (elapsed.inHours < 1) return '${elapsed.inMinutes} 分钟前';
    if (elapsed.inDays < 1) return '${elapsed.inHours} 小时前';
    if (elapsed.inDays < 7) return '${elapsed.inDays} 天前';
    return '${(elapsed.inDays / 7).floor()} 周前';
  }

  HomeState get _homeState {
    if (_loading) return HomeState.loading;
    if (_error != null) return HomeState.error;
    if (_activeCharacter == null) return HomeState.empty;
    if ((_lastMessageAt[_activeCharacter!.id] ?? 0) <= 0) {
      return HomeState.readyToStart;
    }
    return HomeState.resume;
  }

  Widget _buildBrand(AppThemeTokens tokens) {
    return _Staggered(
      animation: _entrance,
      begin: _brandBegin,
      end: (_brandBegin + _span).clamp(0.0, 1.0),
      offset: const Offset(0, -8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _BrandMark(color: tokens.accent, colorSoft: tokens.accentSoft),
          const SizedBox(width: 9),
          Text(
            'LLM PROJECT',
            style: TextStyle(
              color: tokens.accent,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopActions(AppThemeTokens tokens) {
    final themeManager = context.watch<AppThemeManager>();
    return _Staggered(
      animation: _entrance,
      begin: _themeBegin,
      end: (_themeBegin + _span).clamp(0.0, 1.0),
      offset: const Offset(0, -8),
      child: _ThemeToggleButton(
        night: themeManager.isNight,
        onPressed: themeManager.toggle,
        tokens: tokens,
      ),
    );
  }

  Widget _buildRoleEntry(AppThemeTokens tokens, BoxConstraints constraints) {
    final character = _activeCharacter;
    final empty = character == null;
    final roleWidth = (constraints.maxWidth * 0.76)
        .clamp(240.0, constraints.maxWidth - 24)
        .toDouble();
    final roleHeight = 166.0;
    final imagePath = character?.cardImagePath ?? '';
    final hasImage = imagePath.isNotEmpty && File(imagePath).existsSync();
    final stateLabel = empty
        ? 'FIRST EXPERIENCE'
        : _homeState == HomeState.resume
            ? 'CONTINUE EXPERIENCE'
            : 'FIRST EXPERIENCE';
    final title = empty ? '开始第一次体验' : character.name;
    final detail = empty
        ? '从角色库导入或创建一个角色'
        : character.description.trim().isEmpty
            ? (_homeState == HomeState.resume
                ? '距上次聊天 ${_relativeTime(character.id)}'
                : '开始新体验')
            : character.description.trim();

    final cover = hasImage
        ? Image.file(File(imagePath), fit: BoxFit.cover)
        : DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [tokens.accent, tokens.accentStrong],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          );

    return SizedBox(
      width: roleWidth,
      height: roleHeight,
      child: Stack(
        children: [
          // Hard offset shadow backing (12px 17px plane) behind the slanted card.
          Positioned.fill(
            child: Transform.translate(
              offset: const Offset(12, 17),
              child: ClipPath(
                clipper: _SlantedSurfaceClipper(),
                child: ColoredBox(
                  color: tokens.accent.withValues(alpha: 0.10),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: PhysicalShape(
              clipper: _SlantedSurfaceClipper(),
              color: tokens.surfaceElevated,
              shadowColor: tokens.shadow,
              elevation: 6,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  AnimatedBuilder(
                    animation: _cover,
                    builder: (context, child) {
                      final t = Curves.easeInOut.transform(_cover.value);
                      return Opacity(
                        opacity: 0.91 + 0.09 * t,
                        child: Transform.scale(
                          scale: 1.015 + 0.025 * t,
                          child: Transform.translate(
                            offset: Offset(-1.5 * t, -0.6 * t),
                            child: child,
                          ),
                        ),
                      );
                    },
                    child: cover,
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            tokens.accentStrong.withValues(alpha: 0.88),
                            Colors.black.withValues(alpha: 0.32),
                          ],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _ConcentricRingsPainter(
                          ringColor: Colors.white.withValues(alpha: 1.0),
                        ),
                      ),
                    ),
                  ),
                  if (empty)
                    Positioned(
                      right: 26,
                      top: 27,
                      child: RotatedBox(
                        quarterTurns: 1,
                        child: Text(
                          'START HERE',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.52),
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.4,
                          ),
                        ),
                      ),
                    )
                  else
                    Positioned(
                      right: 32,
                      top: 27,
                      child: Text(
                        '01',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.6,
                        ),
                      ),
                    ),
                  if (empty)
                    Positioned.fill(
                      child: _RoleEntryHitArea(
                        onTap: _openCharacterLibrary,
                        child: _roleText(
                          tokens,
                          stateLabel: stateLabel,
                          title: title,
                          detail: detail,
                        ),
                      ),
                    )
                  else ...[
                    Positioned.fill(
                      child: IgnorePointer(
                        child: _roleText(
                          tokens,
                          stateLabel: stateLabel,
                          title: title,
                          detail: detail,
                          titleKey: widget.chatTextKey,
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      top: 0,
                      right: 72,
                      bottom: 0,
                      child: _RoleEntryHitArea(
                        onTap: _openRoleSelection,
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ],
                  Positioned(
                    right: 29,
                    bottom: 17,
                    child: empty
                        ? IgnorePointer(
                            child: _EnterChatButton(
                              onPressed: null,
                              color: tokens.onAccent,
                              foreground: tokens.textPrimary,
                            ),
                          )
                        : _EnterChatButton(
                            key: widget.chatTileKey,
                            onPressed: _openChat,
                            color: tokens.onAccent,
                            foreground: tokens.textPrimary,
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _roleText(
    AppThemeTokens tokens, {
    required String stateLabel,
    required String title,
    required String detail,
    GlobalKey? titleKey,
  }) {
    return Stack(
      children: [
        Positioned(
          top: 25,
          left: 24,
          child: Text(
            stateLabel,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.6,
            ),
          ),
        ),
        Positioned(
          top: 44,
          left: 24,
          right: 34,
          child: Text(
            title,
            key: titleKey,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.5,
            ),
          ),
        ),
        Positioned(
          left: 24,
          right: 94,
          bottom: 20,
          child: Text(
            detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ),
      ],
    );
  }

  List<CharacterCard> get _rolePlaneOrder {
    final selectedId = _pendingRoleId;
    if (selectedId == null) return const <CharacterCard>[];

    final ordered = <CharacterCard>[];
    for (final character in _characters) {
      if (character.id == selectedId) ordered.insert(0, character);
    }
    for (final character in _characters) {
      if (character.id != selectedId) ordered.add(character);
    }
    return ordered;
  }

  Widget _buildRoleSelectionLayer(
    AppThemeTokens tokens, {
    required double roleTop,
    required double roleWidth,
    required double roleHeight,
  }) {
    final planes = _rolePlaneOrder;
    return Positioned.fill(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 330),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) {
          return Opacity(
            opacity: value,
            child: Transform.scale(
              scale: 0.96 + 0.04 * value,
              alignment: Alignment.topLeft,
              child: child,
            ),
          );
        },
        child: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: roleTop - 14,
              height: roleHeight + 28,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _cancelRoleSelection,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        tokens.scrim.withValues(alpha: 0.16),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 12,
              right: 0,
              top: roleTop,
              height: roleHeight,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.zero,
                physics: const BouncingScrollPhysics(),
                itemCount: planes.length,
                separatorBuilder: (context, index) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final character = planes[index];
                  final active = index == 0;
                  return Align(
                    alignment: Alignment.center,
                    child: _RolePlane(
                      character: character,
                      active: active,
                      promoting: active && _promotingRoleId == character.id,
                      width: active ? roleWidth : roleWidth * 0.7,
                      height: active ? roleHeight : roleHeight * 0.7,
                      recentLabel: _relativeTime(character.id),
                      tokens: tokens,
                      onTap: () => _selectRolePlane(character),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModuleRail(AppThemeTokens tokens) {
    final entries = <_HomeModuleEntry>[
      _HomeModuleEntry(
        title: '角色库',
        symbol: '♟',
        preview: _characters.isEmpty
            ? '从这里开始 · 导入或创建'
            : '${_characters.length} 个角色',
        previewKind: 'people',
        onTap: _openCharacterLibrary,
        key: widget.characterTileKey,
        textKey: widget.characterTextKey,
        accent: const Color(0xFFB99756),
      ),
      _HomeModuleEntry(
        title: '世界书库',
        symbol: '◇',
        preview: '$_worldBookCount 种世界书',
        previewKind: 'lines',
        onTap: _openWorldBookLibrary,
        key: widget.worldBookTileKey,
        textKey: widget.worldBookTextKey,
        accent: const Color(0xFF5E8EDB),
      ),
      _HomeModuleEntry(
        title: '背景图库',
        symbol: '▧',
        preview: '$_backgroundCount 个背景',
        previewKind: 'images',
        onTap: _openBackgroundLibrary,
        key: widget.backgroundTileKey,
        textKey: widget.backgroundTextKey,
        accent: const Color(0xFFD97176),
      ),
      _HomeModuleEntry(
        title: 'UI 模组库',
        symbol: '✦',
        preview: '$_uiAssemblyCount 个模组',
        previewKind: 'chips',
        onTap: _openUIAssetGallery,
        accent: const Color(0xFF536366),
      ),
    ];

    return _Staggered(
      animation: _entrance,
      begin: _railBegin,
      end: (_railBegin + _span).clamp(0.0, 1.0),
      offset: const Offset(22, 0),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 10, bottom: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'MODULES',
                      style: TextStyle(
                        color: tokens.textSecondary,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.4,
                      ),
                    ),
                    Text(
                      entries.length.toString().padLeft(2, '0'),
                      style: TextStyle(
                        color: tokens.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.only(right: 4, bottom: 16),
                  itemCount: entries.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final begin =
                        (_itemBase + index * _itemStep).clamp(0.0, 1.0);
                    return _Staggered(
                      animation: _entrance,
                      begin: begin,
                      end: (begin + _span).clamp(0.0, 1.0),
                      offset: const Offset(18, 0),
                      child: _ModulePreviewTile(entry: entries[index], tokens: tokens),
                    );
                  },
                ),
              ),
            ],
          ),
          Positioned(
            right: 1,
            bottom: 1,
            child: _RailScrollHint(tokens: tokens),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return LayoutBuilder(
      builder: (context, constraints) {
        final railWidth = (constraints.maxWidth * 0.45)
            .clamp(170.0, 230.0)
            .toDouble();
        final roleTop = 88.0;
        final roleHeight = 166.0;
        final roleWidth = (constraints.maxWidth * 0.76)
            .clamp(240.0, constraints.maxWidth - 24)
            .toDouble();
        final stageTop = math.min(320.0, constraints.maxHeight * 0.42);
        final railHeight = (constraints.maxHeight * 0.48)
            .clamp(200.0, double.infinity)
            .toDouble();
        final railBottom = 12.0 + bottomInset;
        final lineSoft = tokens.outline.withValues(alpha: 0.55);

        return Stack(
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: _HomeBackground(tokens: tokens),
              ),
            ),
            Positioned(
              top: stageTop,
              left: 12,
              right: railWidth + 15,
              bottom: railBottom,
              child: _Staggered(
                animation: _entrance,
                begin: _stageBegin,
                end: (_stageBegin + _span).clamp(0.0, 1.0),
                offset: const Offset(0, 13),
                scaleFrom: 0.96,
                child: RepaintBoundary(
                  child: _AvatarStage(
                    tokens: tokens,
                    empty: _activeCharacter == null,
                  ),
                ),
              ),
            ),
            Positioned(
              top: roleTop,
              left: 12,
              child: _Staggered(
                animation: _entrance,
                begin: _roleBegin,
                end: (_roleBegin + _span).clamp(0.0, 1.0),
                offset: const Offset(-24, -8),
                child: _loading
                    ? _LoadingRoleEntry(tokens: tokens)
                    : _buildRoleEntry(tokens, constraints),
              ),
            ),
            Positioned(
              top: null,
              right: 12,
              bottom: railBottom,
              width: railWidth,
              height: railHeight,
              child: _buildModuleRail(tokens),
            ),
            Positioned(
              top: constraints.maxHeight * 0.43,
              right: 0,
              child: Opacity(
                opacity: 0.52,
                child: _EdgeGestureHint(
                  accent: tokens.accent,
                  line: lineSoft.withValues(alpha: 0.6),
                ),
              ),
            ),
            Positioned(
              top: 17,
              left: 22,
              child: _buildBrand(tokens),
            ),
            Positioned(
              top: 14,
              right: 18,
              child: _buildTopActions(tokens),
            ),
            if (_roleSelecting)
              _buildRoleSelectionLayer(
                tokens,
                roleTop: roleTop,
                roleWidth: roleWidth,
                roleHeight: roleHeight,
              ),
            if (_error != null)
              Positioned(
                left: 24,
                right: railWidth + 24,
                bottom: 24,
                child: Text(
                  '主页数据读取失败，请稍后重试',
                  style: TextStyle(color: tokens.danger, fontSize: 11),
                ),
              ),
          ],
        );
      },
    );
  }
}

enum HomeState { loading, empty, readyToStart, resume, selectingRole, error }

class _HomeModuleEntry {
  const _HomeModuleEntry({
    required this.title,
    required this.symbol,
    required this.preview,
    required this.previewKind,
    required this.onTap,
    required this.accent,
    this.key,
    this.textKey,
  });

  final String title;
  final String symbol;
  final String preview;
  final String previewKind;
  final VoidCallback onTap;
  final Color accent;
  final GlobalKey? key;
  final GlobalKey? textKey;
}

class _ModulePreviewTile extends StatelessWidget {
  const _ModulePreviewTile({required this.entry, required this.tokens});

  final _HomeModuleEntry entry;
  final AppThemeTokens tokens;

  static const _radius = BorderRadius.only(
    topLeft: Radius.circular(13),
    topRight: Radius.circular(6),
    bottomRight: Radius.circular(13),
    bottomLeft: Radius.circular(6),
  );

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: entry.key,
      height: 84,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.surface,
          borderRadius: _radius,
          border: Border.all(color: tokens.outline.withValues(alpha: 0.6)),
          boxShadow: [
            BoxShadow(
              color: const Color.fromRGBO(48, 60, 84, 0.07),
              offset: const Offset(5, 6),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: _radius,
            onTap: entry.onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(9, 8, 7, 7),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      _ModuleSymbol(glyph: entry.symbol, color: entry.accent),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          entry.title,
                          key: entry.textKey,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: tokens.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Text(
                        '›',
                        style: TextStyle(
                          color: entry.accent,
                          fontSize: 18,
                          height: 1,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _ModulePreviewVisual(
                    kind: entry.previewKind,
                    label: entry.preview,
                    color: entry.accent,
                    textColor: tokens.textMuted,
                  ),
                  const SizedBox(height: 3),
                  Padding(
                    padding: const EdgeInsets.only(left: 3, right: 2),
                    child: Container(
                      height: 1,
                      color: entry.accent.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ModuleSymbol extends StatelessWidget {
  const _ModuleSymbol({required this.glyph, required this.color});

  final String glyph;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        border: Border.all(color: color),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(9),
          topRight: Radius.circular(4),
          bottomRight: Radius.circular(9),
          bottomLeft: Radius.circular(4),
        ),
      ),
      child: Text(
        glyph,
        style: TextStyle(color: color, fontSize: 14),
      ),
    );
  }
}

class _ModulePreviewVisual extends StatelessWidget {
  const _ModulePreviewVisual({
    required this.kind,
    required this.label,
    required this.color,
    required this.textColor,
  });

  final String kind;
  final String label;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    final glyphs = switch (kind) {
      'people' => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PreviewGlyph(type: 'person', color: color),
            const SizedBox(width: 3),
            _PreviewGlyph(type: 'person', color: color),
            const SizedBox(width: 3),
            _PreviewGlyph(type: 'person', color: color),
          ],
        ),
      'images' => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PreviewGlyph(type: 'image', color: color),
            const SizedBox(width: 3),
            _PreviewGlyph(type: 'image', color: color),
            const SizedBox(width: 3),
            _PreviewGlyph(type: 'image', color: color),
          ],
        ),
      'lines' => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 24, height: 3, decoration: BoxDecoration(color: color.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(4))),
            const SizedBox(width: 4),
            Container(width: 14, height: 3, decoration: BoxDecoration(color: color.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(4))),
          ],
        ),
      'chips' => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PreviewChip(label: 'SCENE', color: color),
            const SizedBox(width: 4),
            _PreviewChip(label: 'OPEN', color: color),
          ],
        ),
      _ => const SizedBox.shrink(),
    };

    return Row(
      children: [
        glyphs,
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: textColor, fontSize: 9),
          ),
        ),
      ],
    );
  }
}

class _PreviewChip extends StatelessWidget {
  const _PreviewChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.65)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 7, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _PreviewGlyph extends StatelessWidget {
  const _PreviewGlyph({required this.type, required this.color});

  final String type;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 16,
      height: 14,
      child: CustomPaint(painter: _PreviewGlyphPainter(type, color)),
    );
  }
}

class _PreviewGlyphPainter extends CustomPainter {
  const _PreviewGlyphPainter(this.type, this.color);

  final String type;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    if (type == 'person') {
      paint.style = PaintingStyle.fill;
      canvas.drawCircle(const Offset(8, 3.5), 2.4, paint);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(3.3, 7, 9.4, 6),
          const Radius.circular(3),
        ),
        paint,
      );
      return;
    }

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0.8, 0.8, 14.4, 12.2),
        const Radius.circular(2),
      ),
      paint,
    );
    paint.style = PaintingStyle.fill;
    canvas.drawCircle(const Offset(11.4, 4), 1.2, paint);
    final mountain = Path()
      ..moveTo(2.2, 11.1)
      ..lineTo(5.8, 6.8)
      ..lineTo(8.2, 9.1)
      ..lineTo(10.2, 7.1)
      ..lineTo(13.7, 11.1)
      ..close();
    canvas.drawPath(mountain, paint);
  }

  @override
  bool shouldRepaint(covariant _PreviewGlyphPainter oldDelegate) {
    return oldDelegate.type != type || oldDelegate.color != color;
  }
}

class _RoleEntryHitArea extends StatelessWidget {
  const _RoleEntryHitArea({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(onTap: onTap, behavior: HitTestBehavior.opaque, child: child);
  }
}

class _RolePlane extends StatelessWidget {
  const _RolePlane({
    required this.character,
    required this.active,
    required this.promoting,
    required this.width,
    required this.height,
    required this.recentLabel,
    required this.tokens,
    required this.onTap,
  });

  final CharacterCard character;
  final bool active;
  final bool promoting;
  final double width;
  final double height;
  final String recentLabel;
  final AppThemeTokens tokens;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final imagePath = character.cardImagePath;
    final hasImage = imagePath.isNotEmpty && File(imagePath).existsSync();
    final fallback = active ? tokens.accent : tokens.surfaceElevated;

    Widget card = GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        width: width,
        height: height,
        child: PhysicalShape(
          clipper: _SlantedSurfaceClipper(),
          color: fallback,
          shadowColor: tokens.shadow,
          elevation: active ? 5 : 1,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (hasImage)
                Image.file(File(imagePath), fit: BoxFit.cover)
              else
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: active
                          ? [tokens.accent, tokens.accentStrong]
                          : [
                              tokens.surfaceElevated,
                              tokens.surfaceInteractive,
                            ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      active
                          ? tokens.accentStrong.withValues(alpha: 0.72)
                          : Colors.black.withValues(alpha: 0.2),
                      Colors.black.withValues(alpha: active ? 0.28 : 0.08),
                    ],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                ),
              ),
              if (active)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _ConcentricRingsPainter(
                        ringColor: Colors.white.withValues(alpha: 1.0),
                      ),
                    ),
                  ),
                ),
              IgnorePointer(
                child: Stack(
                  children: [
                    Positioned(
                      top: active ? 25 : 15,
                      left: active ? 24 : 15,
                      child: Text(
                        recentLabel,
                        style: TextStyle(
                          color: active ? Colors.white70 : tokens.textMuted,
                          fontSize: active ? 9 : 8,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                    Positioned(
                      top: active ? 44 : 32,
                      left: active ? 24 : 15,
                      right: 12,
                      child: Text(
                        character.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: active ? Colors.white : tokens.textPrimary,
                          fontSize: active ? 32 : 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: active ? -1.5 : -0.6,
                        ),
                      ),
                    ),
                    Positioned(
                      left: active ? 24 : 15,
                      right: 12,
                      bottom: active ? 20 : 13,
                      child: Text(
                        '${character.name} · $recentLabel',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: active ? Colors.white70 : tokens.textMuted,
                          fontSize: active ? 11 : 8,
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

    if (active && promoting) {
      card = TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.96, end: 1.0),
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) {
          return Transform.scale(scale: value, child: child);
        },
        child: card,
      );
    }

    return card;
  }
}

class _EnterChatButton extends StatelessWidget {
  const _EnterChatButton({
    super.key,
    required this.onPressed,
    required this.color,
    required this.foreground,
  });

  final VoidCallback? onPressed;
  final Color color;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: ClipPath(
        clipper: _ParallelogramClipper(),
        child: Container(
          width: 49,
          height: 38,
          alignment: Alignment.center,
          color: color,
          child: Icon(Icons.arrow_forward_rounded, color: foreground, size: 23),
        ),
      ),
    );
  }
}

class _LoadingRoleEntry extends StatelessWidget {
  const _LoadingRoleEntry({required this.tokens});

  final AppThemeTokens tokens;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 300,
      height: 150,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.surfaceElevated,
          borderRadius: BorderRadius.circular(tokens.radiusMedium),
        ),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: tokens.accent,
            ),
          ),
        ),
      ),
    );
  }
}

class _AvatarStage extends StatefulWidget {
  const _AvatarStage({required this.tokens, required this.empty});

  final AppThemeTokens tokens;
  final bool empty;

  @override
  State<_AvatarStage> createState() => _AvatarStageState();
}

class _AvatarStageState extends State<_AvatarStage>
    with TickerProviderStateMixin {
  late final AnimationController _breathe;
  late final AnimationController _orbit;

  @override
  void initState() {
    super.initState();
    _breathe = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat(reverse: true);
    _orbit = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 9),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _breathe.dispose();
    _orbit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stage = widget.tokens.stage;
    return AnimatedBuilder(
      animation: Listenable.merge([_breathe, _orbit]),
      builder: (context, child) {
        final b = Curves.easeInOut.transform(_breathe.value);
        final o = Curves.easeInOut.transform(_orbit.value);
        return Stack(
          alignment: Alignment.bottomCenter,
          children: [
            Opacity(
              opacity: 0.55 + 0.45 * b,
              child: Transform.scale(
                scale: 0.96 + 0.09 * b,
                child: Container(
                  width: 205,
                  height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        stage.withValues(alpha: 0.16),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Transform.rotate(
              angle: -0.227 + o * 0.105,
              child: Container(
                width: 158 + b * 5,
                height: 55 + b * 2,
                decoration: BoxDecoration(
                  border: Border.all(color: stage.withValues(alpha: 0.42)),
                  borderRadius: const BorderRadius.all(
                    Radius.elliptical(80, 28),
                  ),
                ),
              ),
            ),
            Transform.rotate(
              angle: 0.384,
              child: Container(
                width: 158 - 44,
                height: 55 + 32,
                decoration: BoxDecoration(
                  border: Border.all(color: stage.withValues(alpha: 0.18)),
                  borderRadius: BorderRadius.all(
                    Radius.elliptical((158 - 44) / 2, (55 + 32) / 2),
                  ),
                ),
              ),
            ),
            Transform.rotate(
              angle: -0.489,
              child: Container(
                width: 158 + 42,
                height: 55 - 26,
                decoration: BoxDecoration(
                  border: Border.all(color: stage.withValues(alpha: 0.18)),
                  borderRadius: BorderRadius.all(
                    Radius.elliptical((158 + 42) / 2, (55 - 26) / 2),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 3,
              child: widget.empty
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'YOUR STAGE',
                          style: TextStyle(
                            color: stage,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.0,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '等待第一个角色登场',
                          style: TextStyle(
                            color: widget.tokens.textMuted,
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                    )
                  : Text(
                      'AVATAR STAGE · RESERVED',
                      style: TextStyle(
                        color: widget.tokens.textMuted,
                        fontSize: 8,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.4,
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _SlantedSurfaceClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width * 0.94, 0)
      ..lineTo(size.width, size.height * 0.12)
      ..lineTo(size.width * 0.92, size.height)
      ..lineTo(size.width * 0.02, size.height * 0.94)
      ..close();
    return path;
  }

  @override
  bool shouldReclip(covariant _SlantedSurfaceClipper oldClipper) => false;
}

class _ParallelogramClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    return Path()
      ..moveTo(size.width * 0.13, 0)
      ..lineTo(size.width, size.height * 0.10)
      ..lineTo(size.width * 0.88, size.height)
      ..lineTo(0, size.height * 0.88)
      ..close();
  }

  @override
  bool shouldReclip(covariant _ParallelogramClipper oldClipper) => false;
}

class _ConcentricRingsPainter extends CustomPainter {
  const _ConcentricRingsPainter({required this.ringColor});

  final Color ringColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width - 107, 22);
    void ring(double radius, double alpha) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = ringColor.withValues(alpha: alpha),
      );
    }

    ring(86, 0.17);
    ring(86 + 18, 0.035);
    ring(86 + 42, 0.025);
  }

  @override
  bool shouldRepaint(covariant _ConcentricRingsPainter oldDelegate) {
    return oldDelegate.ringColor != ringColor;
  }
}

class _DiagonalRingsPainter extends CustomPainter {
  const _DiagonalRingsPainter({required this.line});

  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    // Mirrors .screen::before in the HTML prototype: a large ellipse that
    // starts 21% in from the left edge, extends 36% past the right edge,
    // and sits from 19% to 64% of the height, rotated -57deg about center.
    final rect = Rect.fromLTWH(
      size.width * 0.21,
      size.height * 0.19,
      size.width * 1.15,
      size.height * 0.45,
    );
    canvas.save();
    canvas.translate(rect.center.dx, rect.center.dy);
    canvas.rotate(-57 * math.pi / 180);

    void ellipse(double inset) {
      final r = Rect.fromCenter(
        center: Offset.zero,
        width: rect.width + inset * 2,
        height: rect.height + inset * 2,
      );
      canvas.drawOval(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = line,
      );
    }

    ellipse(0);
    ellipse(25);
    ellipse(75);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _DiagonalRingsPainter oldDelegate) {
    return oldDelegate.line != line;
  }
}

class _DiagonalLinePainter extends CustomPainter {
  const _DiagonalLinePainter({required this.line});

  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    // Mirrors .screen::after in the HTML prototype: a 150%-wide, 1px line
    // centered around (55%, 50%) and rotated -57deg.
    const angle = -57 * math.pi / 180;
    final halfWidth = size.width * 0.75;
    final center = Offset(size.width * 0.55, size.height * 0.5);
    final dir = Offset(math.cos(angle), math.sin(angle));
    final from = center - dir * halfWidth;
    final to = center + dir * halfWidth;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = LinearGradient(
        colors: [Colors.transparent, line, Colors.transparent],
      ).createShader(Rect.fromPoints(from, to));
    canvas.drawLine(from, to, paint);
  }

  @override
  bool shouldRepaint(covariant _DiagonalLinePainter oldDelegate) {
    return oldDelegate.line != line;
  }
}

class _HomeBackground extends StatelessWidget {
  const _HomeBackground({required this.tokens});

  final AppThemeTokens tokens;

  @override
  Widget build(BuildContext context) {
    // The HTML prototype draws its ring decoration with a faint dark line in
    // day and a faint light line in night; textPrimary flips correctly for
    // both, so we derive the decorative line from it rather than from outline.
    final rings = tokens.textPrimary.withValues(alpha: 0.24);
    final diagonal = tokens.textPrimary.withValues(alpha: 0.55);
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: tokens.canvas,
            gradient: RadialGradient(
              center: const Alignment(-0.92, 0.52),
              radius: 0.9,
              colors: [
                tokens.stage.withValues(alpha: 0.14),
                tokens.canvas,
              ],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.transparent, tokens.canvasDeep],
              stops: const [0.6, 1.0],
            ),
          ),
        ),
        Opacity(
          opacity: 0.45,
          child: CustomPaint(painter: _DiagonalRingsPainter(line: rings)),
        ),
        Opacity(
          opacity: 0.5,
          child: CustomPaint(painter: _DiagonalLinePainter(line: diagonal)),
        ),
      ],
    );
  }
}

class _Staggered extends StatelessWidget {
  const _Staggered({
    required this.animation,
    required this.begin,
    required this.end,
    required this.offset,
    this.scaleFrom = 1.0,
    required this.child,
  });

  final Animation<double> animation;
  final double begin;
  final double end;
  final Offset offset;
  final double scaleFrom;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final raw = (animation.value - begin) / (end - begin);
        final t = Curves.easeOutCubic.transform(raw.clamp(0.0, 1.0));
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: offset * (1 - t),
            child: Transform.scale(
              scale: scaleFrom + (1.0 - scaleFrom) * t,
              child: child,
            ),
          ),
        );
      },
      child: child,
    );
  }
}

class _BrandMark extends StatefulWidget {
  const _BrandMark({required this.color, required this.colorSoft});

  final Color color;
  final Color colorSoft;

  @override
  State<_BrandMark> createState() => _BrandMarkState();
}

class _BrandMarkState extends State<_BrandMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_controller.value);
        return Opacity(
          opacity: 0.72 + 0.28 * t,
          child: Container(
            width: 8,
            height: 8,
            transform: Matrix4.rotationZ(math.pi / 4),
            decoration: BoxDecoration(
              color: widget.color,
              borderRadius: BorderRadius.circular(2),
              boxShadow: [
                BoxShadow(
                  color: widget.color.withValues(alpha: 0.45 + 0.55 * t),
                  blurRadius: 5 + 11 * t,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ThemeToggleButton extends StatelessWidget {
  const _ThemeToggleButton({
    required this.night,
    required this.onPressed,
    required this.tokens,
  });

  final bool night;
  final VoidCallback onPressed;
  final AppThemeTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: Container(
          width: 35,
          height: 35,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: tokens.surface,
            border: Border.all(color: tokens.outline),
          ),
          child: Icon(
            night ? Icons.wb_sunny_rounded : Icons.nightlight_round,
            size: 16,
            color: tokens.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _RailScrollHint extends StatelessWidget {
  const _RailScrollHint({required this.tokens});

  final AppThemeTokens tokens;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: tokens.outline),
          color: tokens.canvas,
        ),
        child: Text(
          '⌄',
          style: TextStyle(color: tokens.textMuted, fontSize: 12),
        ),
      ),
    );
  }
}

class _EdgeGestureHint extends StatefulWidget {
  const _EdgeGestureHint({required this.accent, required this.line});

  final Color accent;
  final Color line;

  @override
  State<_EdgeGestureHint> createState() => _EdgeGestureHintState();
}

class _EdgeGestureHintState extends State<_EdgeGestureHint>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3800),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final phase = _controller.value;
        double pulse;
        if (phase < 0.7) {
          pulse = 0.12;
        } else if (phase < 0.84) {
          pulse = 0.12 + 0.73 * (phase - 0.7) / 0.14;
        } else {
          pulse = 0.85 - 0.73 * (phase - 0.84) / 0.16;
        }
        return IgnorePointer(
          child: Container(
            width: 15,
            height: 72,
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: widget.line)),
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: 1,
                height: 48,
                color: widget.accent.withValues(alpha: pulse),
              ),
            ),
          ),
        );
      },
    );
  }
}
