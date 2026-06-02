import 'package:flutter/material.dart';
import '../models/api_config.dart';
import '../services/api_config_service.dart';
import 'api_config_edit_page.dart';

class ApiConfigPage extends StatefulWidget {
  const ApiConfigPage({super.key});

  @override
  State<ApiConfigPage> createState() => _ApiConfigPageState();
}

class _ApiConfigPageState extends State<ApiConfigPage> {
  List<ApiConfig> _configs = [];

  @override
  void initState() {
    super.initState();
    _loadConfigs();
  }

  Future<void> _loadConfigs() async {
    final configs = await ApiConfigService.getAllConfigs();
    setState(() => _configs = configs);
  }

  void _addConfig() async {
    final result = await Navigator.push<ApiConfig>(
      context,
      MaterialPageRoute(builder: (_) => const ApiConfigEditPage()),
    );
    if (result != null) {
      try {
        await ApiConfigService.addConfig(result);
        _loadConfigs();  // 重新加载
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('保存失败: $e')),
          );
        }
      }
    }
  }

  void _editConfig(ApiConfig config) async {
    final result = await Navigator.push<ApiConfig>(
      context,
      MaterialPageRoute(builder: (_) => ApiConfigEditPage(config: config)),
    );
    if (result != null) {
      await ApiConfigService.updateConfig(result);
      _loadConfigs();
    }
  }

  void _deleteConfig(ApiConfig config) async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除配置“${config.name}”吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await ApiConfigService.deleteConfig(config.id);
              _loadConfigs();
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _setActive(ApiConfig config) async {
    await ApiConfigService.setActiveConfigId(config.id);
    _loadConfigs();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已切换到 ${config.name}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('API 配置管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _addConfig,
          ),
        ],
      ),
      body: _configs.isEmpty
          ? const Center(child: Text('暂无配置，点击 + 添加'))
          : ListView.builder(
        itemCount: _configs.length,
        itemBuilder: (ctx, index) {
          final config = _configs[index];
          return ListTile(
            leading: Icon(
              Icons.api,
              color: config.apiKey.isNotEmpty ? Colors.blue : Colors.grey,
            ),
            title: Text(config.name),
            subtitle: Text(config.baseUrl),
            trailing: PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'edit') {
                  _editConfig(config);
                } else if (value == 'delete') {
                  _deleteConfig(config);
                } else if (value == 'activate') {
                  _setActive(config);
                }
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(value: 'activate', child: Text('设为当前')),
                const PopupMenuItem(value: 'edit', child: Text('编辑')),
                const PopupMenuItem(value: 'delete', child: Text('删除')),
              ],
            ),
          );
        },
      ),
    );
  }
}