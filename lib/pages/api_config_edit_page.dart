import 'package:flutter/material.dart';
import '../models/api_config.dart';
import '../services/api_config_service.dart';

class ApiConfigEditPage extends StatefulWidget {
  final ApiConfig? config;
  const ApiConfigEditPage({super.key, this.config});

  @override
  State<ApiConfigEditPage> createState() => _ApiConfigEditPageState();
}

class _ApiConfigEditPageState extends State<ApiConfigEditPage> {
  final _nameCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  bool _obscureKey = true;

  bool _testing = false;
  bool _tested = false;            // 是否已执行过测试
  String? _testError;              // 测试错误信息
  List<String> _availableModels = [];
  String? _selectedModel;          // 当前选中的模型名

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
    '免费 (SiliconFlow)': {                    // 替换为 SiliconFlow
      'name': 'SiliconFlow 免费',
      'url': 'https://api.siliconflow.cn/v1',
      'model': 'Qwen/Qwen2.5-7B-Instruct',    // 免费模型
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
            child: Text('选择预设', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          ..._presets.entries.map((entry) => ListTile(
            title: Text(entry.key),
            onTap: () {
              Navigator.pop(ctx);
              _applyPreset(entry.key);
            },
          )),
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
        // 如果已有选中的模型且在列表中，保留；否则选第一个
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
      id: widget.config?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      baseUrl: _urlCtrl.text.trim(),
      apiKey: _keyCtrl.text.trim(),
      model: _modelCtrl.text.trim(),
    );
    Navigator.pop(context, config);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.config == null ? '添加配置' : '编辑配置'),
        actions: [
          // 显眼的保存按钮
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: FilledButton(
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
            Row(
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
            const SizedBox(height: 12),
            TextField(
              controller: _urlCtrl,
              decoration: const InputDecoration(labelText: 'Base URL'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _keyCtrl,
              obscureText: _obscureKey,
              decoration: InputDecoration(
                labelText: 'API Key',
                suffixIcon: IconButton(
                  icon: Icon(_obscureKey ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscureKey = !_obscureKey),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: _testing ? null : _testAndFetchModels,
                icon: _testing
                    ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
                    : const Icon(Icons.wifi_find),
                label: Text(_testing ? '测试中...' : '测试连接并获取模型'),
              ),
            ),
            const SizedBox(height: 16),

            // 模型选择区域
            if (_availableModels.isNotEmpty) ...[
              const Text('可用模型', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
            ] else if (_tested) ...[
              // 测试过但无模型列表
              Container(
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
                        child: Text(_testError!, style: const TextStyle(fontSize: 12, color: Colors.red)),
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
              ),
            ],
            // 如果还没测试，模型区域不显示，只有测试按钮
          ],
        ),
      ),
    );
  }
}