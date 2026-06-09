import 'package:flutter/material.dart';

import '../models/api_config.dart';
import '../services/api_config_service.dart';
import '../utils/id_utils.dart';
import '../widgets/page_guide_overlay.dart';

class ApiConfigEditPage extends StatefulWidget {
  final ApiConfig? config;
  final bool startGuide;
  final VoidCallback? onExitGuide;

  const ApiConfigEditPage({
    super.key,
    this.config,
    this.startGuide = false,
    this.onExitGuide,
  });

  @override
  State<ApiConfigEditPage> createState() => _ApiConfigEditPageState();
}

class _ApiConfigEditPageState extends State<ApiConfigEditPage> {
  final _nameCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();

  final _saveButtonKey = GlobalKey();
  final _nameAreaKey = GlobalKey();
  final _urlAreaKey = GlobalKey();
  final _keyAreaKey = GlobalKey();
  final _testButtonKey = GlobalKey();
  final _modelAreaKey = GlobalKey();

  late bool _showGuide;
  bool _obscureKey = true;

  bool _testing = false;
  bool _tested = false;
  String? _testError;
  List<String> _availableModels = [];
  String? _selectedModel;

  final Map<String, Map<String, String>> _presets = {
    'DeepSeek': {
      'name': 'DeepSeek',
      'url': 'https://api.deepseek.com',
      'model': 'deepseek-chat',
    },
    'OpenAI (GPT)': {
      'name': 'OpenAI',
      'url': 'https://api.openai.com',
      'model': 'gpt-3.5-turbo',
    },
    'Gemini (兼容)': {
      'name': 'Gemini',
      'url': 'https://generativelanguage.googleapis.com',
      'model': 'gemini-1.5-flash',
    },
    '免费 (SiliconFlow)': {
      'name': 'SiliconFlow 免费',
      'url': 'https://api.siliconflow.cn/v1',
      'model': 'Qwen/Qwen2.5-7B-Instruct',
    },
    '自定义': {
      'name': '',
      'url': '',
      'model': '',
    },
  };

  @override
  void initState() {
    super.initState();
    _showGuide = widget.startGuide;
    if (widget.config != null) {
      _nameCtrl.text = widget.config!.name;
      _urlCtrl.text = widget.config!.baseUrl;
      _keyCtrl.text = widget.config!.apiKey;
      _modelCtrl.text = widget.config!.model;
      _selectedModel = widget.config!.model;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _urlCtrl.dispose();
    _keyCtrl.dispose();
    _modelCtrl.dispose();
    super.dispose();
  }

  void _applyPreset(String presetKey) {
    final preset = _presets[presetKey]!;
    _nameCtrl.text = preset['name']!;
    _urlCtrl.text = preset['url']!;
    _modelCtrl.text = preset['model']!;
    setState(() {
      _availableModels = [];
      _selectedModel = preset['model']!.isEmpty ? null : preset['model']!;
      _tested = false;
      _testError = null;
    });
  }

  void _showPresetPicker() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              '选择预设',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          ..._presets.entries.map(
            (entry) => ListTile(
              title: Text(entry.key),
              onTap: () {
                Navigator.pop(ctx);
                _applyPreset(entry.key);
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _testAndFetchModels() async {
    final url = _urlCtrl.text.trim();
    final key = _keyCtrl.text.trim();
    if (url.isEmpty || key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先填写 Base URL 和 API Key')),
      );
      return;
    }
    setState(() {
      _testing = true;
      _tested = false;
      _testError = null;
      _availableModels = [];
    });
    try {
      final models = await ApiConfigService.fetchModels(url, key);
      setState(() {
        _availableModels = models;
        _tested = true;
        if (_selectedModel != null && models.contains(_selectedModel)) {
          _modelCtrl.text = _selectedModel!;
        } else if (models.isNotEmpty) {
          _selectedModel = models.first;
          _modelCtrl.text = _selectedModel!;
        }
      });
    } catch (e) {
      setState(() {
        _tested = true;
        _testError = e.toString();
      });
    } finally {
      setState(() => _testing = false);
    }
  }

  void _save() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('配置名称不能为空')),
      );
      return;
    }
    final config = ApiConfig(
      id: widget.config?.id ?? IdUtils.timestampId(),
      name: name,
      baseUrl: _urlCtrl.text.trim(),
      apiKey: _keyCtrl.text.trim(),
      model: _modelCtrl.text.trim(),
    );
    Navigator.pop(context, config);
  }

  void _exitGuide() {
    setState(() => _showGuide = false);
    widget.onExitGuide?.call();
  }

  Rect? _rectForKey(GlobalKey key) {
    final keyContext = key.currentContext;
    if (keyContext == null) return null;

    final renderObject = keyContext.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return null;

    return renderObject.localToGlobal(Offset.zero) & renderObject.size;
  }

  Rect _backButtonRect(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Rect.fromLTWH(4, top + 2, 58, kToolbarHeight);
  }

  List<PageGuideTarget> _guideTargets(BuildContext context) {
    final targets = <PageGuideTarget>[
      PageGuideTarget(
        id: 'api_edit_back',
        order: 0,
        rect: _backButtonRect(context),
        title: '返回上一页',
        description: '点击这里返回 API 配置页。返回不会关闭教程模式。',
        actionLabel: '返回上一页',
        onAction: () => Navigator.of(context).maybePop(),
        showBadge: false,
      ),
    ];

    void addTarget({
      required GlobalKey key,
      required int order,
      required String id,
      required String title,
      required String description,
      String? actionLabel,
      VoidCallback? onAction,
    }) {
      final rect = _rectForKey(key);
      if (rect == null) return;
      targets.add(
        PageGuideTarget(
          id: id,
          order: order,
          rect: rect,
          title: title,
          description: description,
          actionLabel: actionLabel,
          onAction: onAction,
        ),
      );
    }

    addTarget(
      key: _nameAreaKey,
      order: 1,
      id: 'api_edit_name',
      title: '配置名称与预设',
      description: '这里填写配置名称。右侧“预设”可以快速填入常见服务商的 Base URL 和默认模型。',
    );
    addTarget(
      key: _urlAreaKey,
      order: 2,
      id: 'api_edit_base_url',
      title: 'Base URL',
      description: '这里填写服务商提供的接口地址，例如 https://api.example.com/v1。',
    );
    addTarget(
      key: _keyAreaKey,
      order: 3,
      id: 'api_edit_key',
      title: 'API Key',
      description: '这里填写你从服务商控制台获取的 API Key。请不要把 Key 分享给别人。',
    );
    addTarget(
      key: _testButtonKey,
      order: 4,
      id: 'api_edit_test',
      title: '测试连接并获取模型',
      description: '填写 Base URL 和 API Key 后，点击这里测试连接，并尝试获取可用模型列表。',
      actionLabel: '测试连接',
      onAction: _testing ? null : _testAndFetchModels,
    );
    addTarget(
      key: _modelAreaKey,
      order: 5,
      id: 'api_edit_model',
      title: '模型选择',
      description: _availableModels.isNotEmpty
          ? '测试成功后，可在这里选择一个可用模型。'
          : _tested
              ? '如果获取模型列表失败，可以在这里手动输入服务商文档中的模型名称。'
              : '测试连接后，这里会显示可用模型；如果服务商不返回列表，也可以手动填写模型名称。',
    );
    addTarget(
      key: _saveButtonKey,
      order: 6,
      id: 'api_edit_save',
      title: '保存配置',
      description: '填写并测试完成后，点击这里保存 API 配置。',
      actionLabel: '保存配置',
      onAction: _save,
    );

    return targets;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      child: Stack(
        children: [
          Scaffold(
            appBar: AppBar(
              title: Text(widget.config == null ? '添加配置' : '编辑配置'),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: FilledButton(
                    key: _saveButtonKey,
                    onPressed: _save,
                    child: const Text('保存'),
                  ),
                ),
              ],
            ),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    key: _nameAreaKey,
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _nameCtrl,
                            decoration: const InputDecoration(labelText: '配置名称'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: _showPresetPicker,
                          icon: const Icon(Icons.auto_awesome),
                          label: const Text('预设'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    key: _urlAreaKey,
                    child: TextField(
                      controller: _urlCtrl,
                      decoration: const InputDecoration(labelText: 'Base URL'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    key: _keyAreaKey,
                    child: TextField(
                      controller: _keyCtrl,
                      obscureText: _obscureKey,
                      decoration: InputDecoration(
                        labelText: 'API Key',
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureKey ? Icons.visibility_off : Icons.visibility,
                          ),
                          onPressed: () => setState(() => _obscureKey = !_obscureKey),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton.icon(
                      key: _testButtonKey,
                      onPressed: _testing ? null : _testAndFetchModels,
                      icon: _testing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.wifi_find),
                      label: Text(_testing ? '测试中...' : '测试连接并获取模型'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    key: _modelAreaKey,
                    child: _buildModelArea(),
                  ),
                ],
              ),
            ),
          ),
          if (_showGuide)
            Positioned.fill(
              child: PageGuideOverlay(
                title: 'API 编辑页导览',
                hint: '按顺序填写配置名称、Base URL、API Key，测试连接后选择模型，最后保存。',
                targets: _guideTargets(context),
                onExit: _exitGuide,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildModelArea() {
    if (_availableModels.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '可用模型',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: _availableModels.map((model) {
              final selected = model == _selectedModel;
              return ChoiceChip(
                label: Text(model),
                selected: selected,
                onSelected: (val) {
                  setState(() {
                    _selectedModel = model;
                    _modelCtrl.text = model;
                  });
                },
              );
            }).toList(),
          ),
        ],
      );
    }

    if (_tested) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('获取模型列表失败', style: TextStyle(color: Colors.red.shade700)),
            if (_testError != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _testError!,
                  style: const TextStyle(fontSize: 12, color: Colors.red),
                ),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _modelCtrl,
              decoration: const InputDecoration(
                labelText: '手动输入模型名称',
                hintText: '例如 deepseek-chat',
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text(
        '测试连接后，这里会显示可用模型；如果服务商不返回模型列表，也可以稍后手动填写模型名称。',
        style: TextStyle(fontSize: 13, height: 1.4),
      ),
    );
  }
}
