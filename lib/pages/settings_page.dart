import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../modules/chat_module.dart';

class SettingsPage extends StatefulWidget {
  final VoidCallback? onBack; // 可选的回调，目前滑动面板不需要
  const SettingsPage({super.key, this.onBack});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _keyController = TextEditingController();
  final _urlController = TextEditingController();
  bool _obscureKey = true;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final module = context.read<ChatModule>();
    final savedKey = await module.apiKey;
    final savedUrl = await module.baseUrl;
    setState(() {
      _keyController.text = savedKey ?? '';//临时填入，即时删除
      _urlController.text = savedUrl ?? 'https://api.deepseek.com';
      _loaded = true;
    });
  }

  Future<void> _save() async {
    final module = context.read<ChatModule>();
    await module.saveSettings(_keyController.text.trim(), _urlController.text.trim());
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _keyController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('API 设置')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(labelText: 'Base URL'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _keyController,
              obscureText: _obscureKey,
              decoration: InputDecoration(
                labelText: 'API Key',
                suffixIcon: IconButton(
                  icon: Icon(_obscureKey ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscureKey = !_obscureKey),
                ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(onPressed: _save, child: const Text('保存并返回')),
          ],
        ),
      ),
    );
  }
}