import 'package:flutter/material.dart';

import '../core/api_service.dart';
import '../core/app_settings.dart';

/// AI API 配置弹窗（单套，不做多配置管理）。
///
/// - 预设厂家：选择后自动填入 Base URL（与默认模型）
/// - 填 Key 后「获取模型」自动拉取可用模型列表供选择
/// - 服务商不返回列表时可手动输入模型名
class ApiConfigDialog extends StatefulWidget {
  const ApiConfigDialog({super.key});

  /// 打开弹窗；返回 true 表示已保存。
  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (_) => const ApiConfigDialog(),
    );
  }

  @override
  State<ApiConfigDialog> createState() => _ApiConfigDialogState();
}

class _ApiConfigDialogState extends State<ApiConfigDialog> {
  // 预设厂家：名称 -> (url, 默认模型)
  static const Map<String, Map<String, String>> _presets = {
    'DeepSeek': {
      'url': 'https://api.deepseek.com',
      'model': 'deepseek-chat',
    },
    'OpenAI': {
      'url': 'https://api.openai.com',
      'model': 'gpt-4o-mini',
    },
    'SiliconFlow（含免费模型）': {
      'url': 'https://api.siliconflow.cn',
      'model': 'Qwen/Qwen2.5-7B-Instruct',
    },
    'OpenRouter': {
      'url': 'https://openrouter.ai/api',
      'model': '',
    },
    '自定义': {
      'url': '',
      'model': '',
    },
  };

  final _urlCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();

  String? _preset;
  List<String> _models = [];
  String? _selectedModel;
  bool _fetching = false;
  String? _fetchMsg;
  bool _obscureKey = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = await AppSettings.getApiConfig();
    if (!mounted) return;
    setState(() {
      _urlCtrl.text = c.baseUrl;
      _keyCtrl.text = c.apiKey;
      _modelCtrl.text = c.model;
      _selectedModel = c.model.isEmpty ? null : c.model;
    });
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _keyCtrl.dispose();
    _modelCtrl.dispose();
    super.dispose();
  }

  void _applyPreset(String key) {
    final p = _presets[key]!;
    setState(() {
      _preset = key;
      _urlCtrl.text = p['url'] ?? '';
      if ((p['model'] ?? '').isNotEmpty) {
        _modelCtrl.text = p['model']!;
        _selectedModel = p['model'];
      }
      _models = [];
      _fetchMsg = null;
    });
  }

  Future<void> _fetchModels() async {
    final url = _urlCtrl.text.trim();
    final key = _keyCtrl.text.trim();
    if (url.isEmpty || key.isEmpty) {
      setState(() => _fetchMsg = '请先填写 Base URL 和 API Key');
      return;
    }
    setState(() {
      _fetching = true;
      _fetchMsg = null;
    });
    try {
      final models = await ApiService.fetchModels(url, key);
      if (!mounted) return;
      setState(() {
        _models = models;
        _fetchMsg = '获取到 ${models.length} 个模型';
        if (models.isNotEmpty) {
          if (_selectedModel == null || !models.contains(_selectedModel)) {
            _selectedModel = models.first;
            _modelCtrl.text = models.first;
          }
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fetchMsg = '获取失败：$e\n可手动填写模型名。';
        _models = [];
      });
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  Future<void> _save() async {
    final model = (_selectedModel ?? _modelCtrl.text).trim();
    await AppSettings.setApiConfig(ApiConfig(
      baseUrl: _urlCtrl.text.trim(),
      apiKey: _keyCtrl.text.trim(),
      model: model,
    ));
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('AI 配置'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('用于第二步「AI 智能归类」与第三步「检查精修」。',
                  style: TextStyle(fontSize: 12, color: Colors.black54)),
              const SizedBox(height: 4),
              const Text(
                '提示：转译含 NSFW 内容的角色卡时，建议使用无审核的 API 或本地模型'
                    '（如 Ollama / LM Studio），以免被内容审核拒绝。AI 步骤失败时会自动'
                    '回退到规则转译，不影响出卡。',
                style: TextStyle(fontSize: 11, color: Colors.orange),
              ),
              const SizedBox(height: 12),

              // 预设厂家
              DropdownButtonFormField<String>(
                initialValue: _preset,
                decoration: const InputDecoration(
                  labelText: '预设厂家',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: _presets.keys
                    .map((k) => DropdownMenuItem(value: k, child: Text(k)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) _applyPreset(v);
                },
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _urlCtrl,
                decoration: const InputDecoration(
                  labelText: 'Base URL',
                  hintText: '如 https://api.deepseek.com',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _keyCtrl,
                obscureText: _obscureKey,
                decoration: InputDecoration(
                  labelText: 'API Key',
                  isDense: true,
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureKey
                        ? Icons.visibility_off
                        : Icons.visibility),
                    onPressed: () =>
                        setState(() => _obscureKey = !_obscureKey),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  FilledButton.icon(
                    onPressed: _fetching ? null : _fetchModels,
                    icon: _fetching
                        ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.sync, size: 18),
                    label: Text(_fetching ? '获取中…' : '获取模型'),
                  ),
                  const SizedBox(width: 12),
                  if (_fetchMsg != null)
                    Expanded(
                      child: Text(_fetchMsg!,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.black54)),
                    ),
                ],
              ),
              const SizedBox(height: 12),

              // 模型：有列表用下拉，否则手动输入
              if (_models.isNotEmpty)
                DropdownButtonFormField<String>(
                  initialValue: _selectedModel,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: '选择模型',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: _models
                      .map((m) =>
                      DropdownMenuItem(value: m, child: Text(m)))
                      .toList(),
                  onChanged: (v) {
                    setState(() {
                      _selectedModel = v;
                      if (v != null) _modelCtrl.text = v;
                    });
                  },
                )
              else
                TextField(
                  controller: _modelCtrl,
                  decoration: const InputDecoration(
                    labelText: '模型名称（手动）',
                    hintText: '如 deepseek-chat',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => _selectedModel = v.trim(),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('保存'),
        ),
      ],
    );
  }
}
