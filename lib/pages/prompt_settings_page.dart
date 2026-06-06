import 'package:flutter/material.dart';
import '../models/prompt_settings.dart';
import '../services/prompt_settings_service.dart';
import 'prompt_preview_page.dart';

class PromptSettingsPage extends StatefulWidget {
  final String? characterId;
  final String? characterName;
  final Future<PromptPreviewData> Function(PromptSettings settings)? buildPreview;

  const PromptSettingsPage({
    super.key,
    this.characterId,
    this.characterName,
    this.buildPreview,
  });

  bool get isCharacterMode => characterId != null && characterId!.isNotEmpty;

  @override
  State<PromptSettingsPage> createState() => _PromptSettingsPageState();
}

class _PromptSettingsPageState extends State<PromptSettingsPage> {
  PromptSettings _settings = PromptSettings();
  PromptSettings _globalSettings = PromptSettings();

  bool _loading = true;
  bool _saving = false;

  /// 仅在聊天页角色模式下使用。
  /// 默认 false：所有角色默认使用全局 Prompt 策略。
  bool _useCharacterSettings = false;

  late TextEditingController _characterRulesCtrl;
  late TextEditingController _systemRulesCtrl;
  late TextEditingController _continuityCtrl;

  bool get _canEditSettings {
    if (!widget.isCharacterMode) return true;
    return _useCharacterSettings;
  }

  @override
  void initState() {
    super.initState();
    _characterRulesCtrl = TextEditingController();
    _systemRulesCtrl = TextEditingController();
    _continuityCtrl = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _characterRulesCtrl.dispose();
    _systemRulesCtrl.dispose();
    _continuityCtrl.dispose();
    super.dispose();
  }

  void _setEditorsFromSettings(PromptSettings settings) {
    _characterRulesCtrl.text = settings.characterRoleplayRules;
    _systemRulesCtrl.text = settings.systemRoleplayRules;
    _continuityCtrl.text = settings.continuityReminder;
  }

  void _syncTextEditorsToSettings() {
    _settings.characterRoleplayRules = _characterRulesCtrl.text.trim().isEmpty
        ? PromptSettings.defaultCharacterRoleplayRules
        : _characterRulesCtrl.text.trim();

    _settings.systemRoleplayRules = _systemRulesCtrl.text.trim().isEmpty
        ? PromptSettings.defaultSystemRoleplayRules
        : _systemRulesCtrl.text.trim();

    _settings.continuityReminder = _continuityCtrl.text.trim().isEmpty
        ? PromptSettings.defaultContinuityReminder
        : _continuityCtrl.text.trim();
  }

  Future<void> _load() async {
    final globalSettings = await PromptSettingsService.getSettings();

    PromptSettings pageSettings = globalSettings.copy();
    bool useCharacterSettings = false;

    if (widget.isCharacterMode) {
      final characterId = widget.characterId!;

      useCharacterSettings =
          await PromptSettingsService.isCharacterSettingsEnabled(characterId);

      if (useCharacterSettings) {
        final characterSettings =
            await PromptSettingsService.getCharacterSettings(characterId);
        pageSettings = characterSettings ?? globalSettings.copy();
      }
    }

    if (!mounted) return;

    setState(() {
      _globalSettings = globalSettings;
      _settings = pageSettings;
      _useCharacterSettings = useCharacterSettings;
      _setEditorsFromSettings(_settings);
      _loading = false;
    });
  }

  Future<void> _toggleCharacterSettings(bool value) async {
    if (!widget.isCharacterMode) return;

    if (value) {
      final characterId = widget.characterId!;
      final savedCharacterSettings =
          await PromptSettingsService.getCharacterSettings(characterId);
      final nextSettings = savedCharacterSettings ?? _globalSettings.copy();

      if (!mounted) return;

      setState(() {
        _useCharacterSettings = true;
        _settings = nextSettings;
        _setEditorsFromSettings(_settings);
      });
    } else {
      setState(() {
        _useCharacterSettings = false;
        _settings = _globalSettings.copy();
        _setEditorsFromSettings(_settings);
      });
    }
  }

  Future<void> _save() async {
    if (_saving) return;

    if (_canEditSettings) {
      _syncTextEditorsToSettings();
    }

    setState(() => _saving = true);

    try {
      if (widget.isCharacterMode) {
        final characterId = widget.characterId!;

        await PromptSettingsService.setCharacterSettingsEnabled(
          characterId,
          _useCharacterSettings,
        );

        if (_useCharacterSettings) {
          await PromptSettingsService.saveCharacterSettings(
            characterId,
            _settings,
          );
        }
      } else {
        await PromptSettingsService.saveSettings(_settings);
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          widget.isCharacterMode
              ? '当前角色 Prompt 策略已保存'
              : '全局 Prompt 策略已保存',
        ),
      ),
    );
  }

  Future<void> _reset() async {
    if (widget.isCharacterMode) {
      final characterId = widget.characterId!;
      await PromptSettingsService.setCharacterSettingsEnabled(
        characterId,
        false,
      );

      final globalSettings = await PromptSettingsService.getSettings();
      if (!mounted) return;

      setState(() {
        _globalSettings = globalSettings;
        _settings = globalSettings.copy();
        _useCharacterSettings = false;
        _setEditorsFromSettings(_settings);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前角色已恢复使用全局 Prompt 策略')),
      );
      return;
    }

    final settings = PromptSettings();

    setState(() {
      _settings = settings;
      _globalSettings = settings.copy();
      _setEditorsFromSettings(settings);
    });

    await PromptSettingsService.saveSettings(settings);

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已恢复全局默认 Prompt 策略')),
    );
  }

  Future<void> _preview() async {
    final builder = widget.buildPreview;
    if (builder == null) return;

    try {
      if (_canEditSettings) {
        _syncTextEditorsToSettings();
      }

      final data = await builder(_settings.copy());
      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => PromptPreviewPage(data: data)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Prompt 预览失败：$e')),
      );
    }
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildInfoCard() {
    final text = widget.isCharacterMode
        ? '这里显示当前角色实际使用的 Prompt 策略。默认情况下角色使用全局默认策略；只有开启“当前角色使用单独 Prompt 策略”后，本页修改才只影响当前角色。'
        : '这里是全局默认 Prompt 策略。所有未开启单独策略的角色都会使用这里的配置。滑动条为推荐范围，右侧数字框可手动输入自定义数值。';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 13, height: 1.4),
      ),
    );
  }

  Widget _buildReadonlyHint() {
    if (!widget.isCharacterMode || _useCharacterSettings) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blueGrey.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blueGrey.withValues(alpha: 0.16)),
      ),
      child: const Text(
        '当前角色正在使用全局默认 Prompt 策略。若要只调整这个角色，请开启上方开关。',
        style: TextStyle(fontSize: 13, height: 1.4),
      ),
    );
  }

  Widget _buildRuleEditor({
    required String title,
    required TextEditingController controller,
    int minLines = 3,
  }) {
    return TextField(
      controller: controller,
      enabled: _canEditSettings,
      minLines: minLines,
      maxLines: minLines + 5,
      decoration: InputDecoration(
        labelText: title,
        alignLabelWithHint: true,
        border: const OutlineInputBorder(),
        helperText: '可使用 {{char}} 表示当前角色名，{{user}} 表示当前用户名称。',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isCharacterMode ? '角色 Prompt 策略' : '全局 Prompt 策略'),
        actions: [
          if (widget.buildPreview != null)
            IconButton(
              tooltip: '预览当前 Prompt',
              icon: const Icon(Icons.remove_red_eye_outlined),
              onPressed: _preview,
            ),
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('保存'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildInfoCard(),
          if (widget.isCharacterMode) ...[
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('当前角色使用单独 Prompt 策略'),
              subtitle: Text(
                _useCharacterSettings
                    ? '开启后，本页修改只影响 ${widget.characterName ?? '当前角色'}。'
                    : '关闭时，当前角色使用主菜单中的全局默认 Prompt 策略。',
              ),
              value: _useCharacterSettings,
              onChanged: _toggleCharacterSettings,
            ),
            _buildReadonlyHint(),
          ],
          _sectionTitle('基础规则'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('注入角色扮演规则'),
            subtitle: const Text('控制人物卡第一人称、禁止代替用户行动等规则。'),
            value: _settings.injectRoleplayRules,
            onChanged: _canEditSettings
                ? (v) => setState(() => _settings.injectRoleplayRules = v)
                : null,
          ),
          if (_settings.injectRoleplayRules) ...[
            const SizedBox(height: 8),
            _buildRuleEditor(
              title: '人物卡规则',
              controller: _characterRulesCtrl,
              minLines: 5,
            ),
            const SizedBox(height: 12),
            _buildRuleEditor(
              title: '系统卡规则',
              controller: _systemRulesCtrl,
              minLines: 4,
            ),
          ],
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('注入连续性提醒'),
            subtitle: const Text('每轮提醒模型保持角色身份、上下文和设定连续性。'),
            value: _settings.injectContinuityReminder,
            onChanged: _canEditSettings
                ? (v) => setState(() => _settings.injectContinuityReminder = v)
                : null,
          ),
          if (_settings.injectContinuityReminder) ...[
            const SizedBox(height: 8),
            _buildRuleEditor(
              title: '连续性提醒',
              controller: _continuityCtrl,
              minLines: 3,
            ),
          ],
          _sectionTitle('周期注入'),
          PromptNumberSliderTile(
            title: '摘要设定注入间隔',
            description: '每隔多少个用户回合注入一次行为摘要。0 表示关闭。',
            value: _settings.summaryInterval,
            min: 0,
            max: 12,
            recommendedMin: 0,
            recommendedMax: 12,
            enabled: _canEditSettings,
            onChanged: (v) => setState(() => _settings.summaryInterval = v),
          ),
          PromptNumberSliderTile(
            title: '完整设定注入间隔',
            description: '每隔多少个用户回合注入一次完整详细设定。0 表示关闭。',
            value: _settings.fullDetailInterval,
            min: 0,
            max: 36,
            recommendedMin: 0,
            recommendedMax: 36,
            enabled: _canEditSettings,
            onChanged: (v) => setState(() => _settings.fullDetailInterval = v),
          ),
          _sectionTitle('世界书'),
          PromptNumberSliderTile(
            title: '世界书扫描深度',
            description: '用于触发世界书的最近消息数量。推荐 4。',
            value: _settings.worldBookScanDepth,
            min: 1,
            max: 12,
            recommendedMin: 1,
            recommendedMax: 12,
            enabled: _canEditSettings,
            onChanged: (v) => setState(() => _settings.worldBookScanDepth = v),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _reset,
            icon: const Icon(Icons.restore),
            label: Text(widget.isCharacterMode ? '恢复使用全局策略' : '恢复默认'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class PromptNumberSliderTile extends StatefulWidget {
  final String title;
  final String description;
  final int value;
  final int min;
  final int max;
  final int recommendedMin;
  final int recommendedMax;
  final bool enabled;
  final ValueChanged<int> onChanged;

  const PromptNumberSliderTile({
    super.key,
    required this.title,
    required this.description,
    required this.value,
    required this.min,
    required this.max,
    required this.recommendedMin,
    required this.recommendedMax,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  State<PromptNumberSliderTile> createState() => _PromptNumberSliderTileState();
}

class _PromptNumberSliderTileState extends State<PromptNumberSliderTile> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value.toString());
  }

  @override
  void didUpdateWidget(covariant PromptNumberSliderTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value &&
        _controller.text != widget.value.toString()) {
      _controller.text = widget.value.toString();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _commitTextValue(String text) {
    if (!widget.enabled) return;

    final value = int.tryParse(text.trim());
    if (value == null) {
      _controller.text = widget.value.toString();
      return;
    }
    widget.onChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.value;
    final sliderValue = value.clamp(widget.min, widget.max).toDouble();
    final outOfRecommended =
        value < widget.recommendedMin || value > widget.recommendedMax;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: widget.enabled ? Colors.grey.shade100 : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: outOfRecommended ? Colors.orange.shade300 : Colors.grey.shade200,
        ),
      ),
      child: Opacity(
        opacity: widget.enabled ? 1.0 : 0.68,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.description,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 58,
                  child: TextField(
                    enabled: widget.enabled,
                    controller: _controller,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 8,
                      ),
                    ),
                    onSubmitted: widget.enabled ? _commitTextValue : null,
                    onEditingComplete: widget.enabled
                        ? () => _commitTextValue(_controller.text)
                        : null,
                  ),
                ),
              ],
            ),
            Slider(
              value: sliderValue,
              min: widget.min.toDouble(),
              max: widget.max.toDouble(),
              divisions: widget.max - widget.min,
              label: value.toString(),
              onChanged: widget.enabled
                  ? (v) => widget.onChanged(v.round())
                  : null,
            ),
            Row(
              children: [
                Text(
                  '${widget.min}',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
                const Spacer(),
                Text(
                  '${widget.max}',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
            if (outOfRecommended) ...[
              const SizedBox(height: 6),
              Text(
                '当前值超出推荐范围 ${widget.recommendedMin}~${widget.recommendedMax}，可能导致 token 开销异常或设定保持效果下降。',
                style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
