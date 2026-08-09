import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/character_card.dart';
import '../services/background_service.dart';
import '../services/database_service.dart';
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

class _HomeExperiencePageState extends State<HomeExperiencePage> {
  static const _activeCharacterPreferenceKey = 'home_active_character_id';

  List<CharacterCard> _characters = const <CharacterCard>[];
  Map<String, int> _lastMessageAt = const <String, int>{};
  CharacterCard? _activeCharacter;
  int _worldBookCount = 0;
  int _backgroundCount = 0;
  int _uiAssemblyCount = 0;
  bool _loading = true;
  bool _roleSelecting = false;
  String? _pendingRoleId;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _loadHomeData();
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
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error;
      });
    }
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
    setState(() {
      _pendingRoleId = null;
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
        _roleSelecting = false;
      });
      return;
    }

    setState(() => _pendingRoleId = character.id);
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: tokens.accent,
            borderRadius: BorderRadius.circular(2),
            boxShadow: [
              BoxShadow(
                color: tokens.accent.withValues(alpha: 0.42),
                blurRadius: 10,
              ),
            ],
          ),
          transform: Matrix4.rotationZ(math.pi / 4),
        ),
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

    return SizedBox(
      width: roleWidth,
      height: roleHeight,
      child: ClipPath(
        clipper: _SlantedSurfaceClipper(),
        child: Stack(
          children: [
            Positioned.fill(
              child: hasImage
                  ? Image.file(File(imagePath), fit: BoxFit.cover)
                  : DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [tokens.accent, tokens.accentStrong],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                    ),
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
            if (empty)
              Positioned.fill(
                child: _RoleEntryHitArea(
                  onTap: _openCharacterLibrary,
                  child: _roleText(
                    tokens,
                    stateLabel: stateLabel,
                    title: '开始第一次体验',
                    detail: '从角色库导入或创建一个角色',
                    showEnter: false,
                  ),
                ),
              )
            else ...[
              Positioned.fill(
                child: IgnorePointer(
                  child: _roleText(
                    tokens,
                    stateLabel: stateLabel,
                    title: character.name,
                    detail:
                        '${character.name} · ${character.description.trim().isEmpty ? '当前角色' : character.description.trim()}',
                    showEnter: true,
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
            if (!empty)
              Positioned(
                right: 29,
                bottom: 17,
                child: _EnterChatButton(
                  key: widget.chatTileKey,
                  onPressed: _openChat,
                  color: tokens.onAccent,
                  foreground: tokens.textPrimary,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _roleText(
    AppThemeTokens tokens, {
    required String stateLabel,
    required String title,
    required String detail,
    required bool showEnter,
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
          right: showEnter ? 94 : 24,
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
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final character = planes[index];
                final active = index == 0;
                return _RolePlane(
                  character: character,
                  active: active,
                  width: active ? roleWidth : roleWidth * 0.7,
                  height: active ? roleHeight : roleHeight * 0.7,
                  recentLabel: _relativeTime(character.id),
                  tokens: tokens,
                  onTap: () => _selectRolePlane(character),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModuleRail(AppThemeTokens tokens) {
    final entries = <_HomeModuleEntry>[
      _HomeModuleEntry(
        title: '角色库',
        icon: Icons.person_outline_rounded,
        preview: '${_characters.length} 个角色',
        previewKind: 'people',
        onTap: _openCharacterLibrary,
        key: widget.characterTileKey,
        textKey: widget.characterTextKey,
        accent: const Color(0xFFB99756),
      ),
      _HomeModuleEntry(
        title: '世界书库',
        icon: Icons.auto_stories_outlined,
        preview: '$_worldBookCount 种世界书',
        previewKind: 'lines',
        onTap: _openWorldBookLibrary,
        key: widget.worldBookTileKey,
        textKey: widget.worldBookTextKey,
        accent: const Color(0xFF5E8EDB),
      ),
      _HomeModuleEntry(
        title: '背景图库',
        icon: Icons.image_outlined,
        preview: '$_backgroundCount 个背景',
        previewKind: 'images',
        onTap: _openBackgroundLibrary,
        key: widget.backgroundTileKey,
        textKey: widget.backgroundTextKey,
        accent: const Color(0xFFD97176),
      ),
      _HomeModuleEntry(
        title: 'UI 模组库',
        icon: Icons.auto_awesome_outlined,
        preview: '$_uiAssemblyCount 个模组',
        previewKind: 'chips',
        onTap: _openUIAssetGallery,
        accent: const Color(0xFF536366),
      ),
    ];

    return ListView.separated(
      padding: const EdgeInsets.only(right: 4, bottom: 16),
      itemCount: entries.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) => _ModulePreviewTile(
        entry: entries[index],
        tokens: tokens,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);

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
        final railTop = math.max(stageTop + 110, constraints.maxHeight * 0.48);

        return Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: tokens.canvas,
                  gradient: RadialGradient(
                    center: const Alignment(-0.8, 0.7),
                    radius: 1.2,
                    colors: [
                      tokens.success.withValues(alpha: 0.08),
                      tokens.canvas,
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 17,
              left: 22,
              child: _buildBrand(tokens),
            ),
            Positioned(
              top: roleTop,
              left: 12,
              child: _loading
                  ? _LoadingRoleEntry(tokens: tokens)
                  : _buildRoleEntry(tokens, constraints),
            ),
            Positioned(
              top: stageTop,
              left: 12,
              right: railWidth + 15,
              bottom: 12,
              child: _AvatarStage(tokens: tokens, empty: _activeCharacter == null),
            ),
            Positioned(
              top: railTop,
              right: 10,
              bottom: 12,
              width: railWidth,
              child: Column(
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
                          '04',
                          style: TextStyle(
                            color: tokens.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(child: _buildModuleRail(tokens)),
                ],
              ),
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
    required this.icon,
    required this.preview,
    required this.previewKind,
    required this.onTap,
    required this.accent,
    this.key,
    this.textKey,
  });

  final String title;
  final IconData icon;
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

  @override
  Widget build(BuildContext context) {
    return PhysicalShape(
      key: entry.key,
      clipper: _SlantedSurfaceClipper(),
      color: tokens.surfaceElevated,
      shadowColor: tokens.shadow,
      elevation: tokens.elevationLow,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: entry.onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 8, 7),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(entry.icon, color: entry.accent, size: 20),
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
                    Icon(Icons.chevron_right, color: entry.accent, size: 19),
                  ],
                ),
                const Spacer(),
                _ModulePreviewVisual(
                  kind: entry.previewKind,
                  label: entry.preview,
                  color: entry.accent,
                  textColor: tokens.textMuted,
                ),
                const SizedBox(height: 3),
                Container(height: 1, color: entry.accent.withValues(alpha: 0.55)),
              ],
            ),
          ),
        ),
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
  const _RoleEntryHitArea({super.key, required this.onTap, required this.child});

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
    required this.width,
    required this.height,
    required this.recentLabel,
    required this.tokens,
    required this.onTap,
  });

  final CharacterCard character;
  final bool active;
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

    return GestureDetector(
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
          elevation: active ? 4 : 1,
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
                        '${character.title} · $recentLabel',
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
  }
}

class _EnterChatButton extends StatelessWidget {
  const _EnterChatButton({super.key, required this.onPressed, required this.color, required this.foreground});

  final VoidCallback onPressed;
  final Color color;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: Container(
          width: 49,
          height: 38,
          alignment: Alignment.center,
          decoration: ShapeDecoration(
            color: color,
            shape: const BeveledRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(9)),
            ),
          ),
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
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
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
        return Stack(
          alignment: Alignment.bottomCenter,
          children: [
            Opacity(
              opacity: 0.08 + t * 0.08,
              child: Container(
                width: 200 + t * 12,
                height: 125 + t * 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      widget.tokens.success.withValues(alpha: 0.24),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Transform.rotate(
              angle: -0.14 + t * 0.05,
              child: Container(
                width: 158 + t * 5,
                height: 55 + t * 2,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: widget.tokens.success.withValues(alpha: 0.35),
                  ),
                  borderRadius: const BorderRadius.all(
                    Radius.elliptical(80, 28),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 3,
              child: Text(
                widget.empty ? 'YOUR STAGE · RESERVED' : 'AVATAR STAGE',
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
