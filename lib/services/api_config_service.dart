import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import '../models/api_config.dart';
import 'package:flutter/foundation.dart';

class ApiConfigService {
  static const String _configsKey = 'api_configs';
  static const String _activeConfigKey = 'active_api_config_id';
  static final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  /// 获取所有配置列表
  static Future<List<ApiConfig>> getAllConfigs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_configsKey) ?? '[]';
      final List<dynamic> jsonList = jsonDecode(jsonString);
      final configs = <ApiConfig>[];
      for (final json in jsonList) {
        final config = ApiConfig.fromJson(json as Map<String, dynamic>);
        final key = await _secureStorage.read(key: 'api_key_${config.id}');
        config.apiKey = key ?? '';
        configs.add(config);
      }
      return configs;
    } catch (e) {
      debugPrint('读取 API 配置失败: $e');
      return [];
    }
  }

  /// 保存所有配置（非敏感字段存 SharedPreferences，Key 存安全存储）
  static Future<void> saveAllConfigs(List<ApiConfig> configs) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = configs.map((c) => c.toJson()).toList();
      await prefs.setString(_configsKey, jsonEncode(jsonList));
      for (final config in configs) {
        if (config.apiKey.isNotEmpty) {
          await _secureStorage.write(key: 'api_key_${config.id}', value: config.apiKey);
        }
      }
      debugPrint('API 配置已保存，共 ${configs.length} 条');
    } catch (e) {
      debugPrint('保存 API 配置失败: $e');
    }
  }

  /// 添加配置
  static Future<void> addConfig(ApiConfig config) async {
    final configs = await getAllConfigs();
    configs.add(config);
    await saveAllConfigs(configs);
  }

  /// 更新配置
  static Future<void> updateConfig(ApiConfig config) async {
    final configs = await getAllConfigs();
    final index = configs.indexWhere((c) => c.id == config.id);
    if (index != -1) {
      configs[index] = config;
      await saveAllConfigs(configs);
    }
  }

  /// 删除配置
  static Future<void> deleteConfig(String id) async {
    final configs = await getAllConfigs();
    configs.removeWhere((c) => c.id == id);
    await saveAllConfigs(configs);
    await _secureStorage.delete(key: 'api_key_$id');
  }

  /// 获取当前激活的配置 ID
  static Future<String?> getActiveConfigId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_activeConfigKey);
  }

  /// 设置激活的配置 ID
  static Future<void> setActiveConfigId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeConfigKey, id);
  }

  /// 获取当前激活的配置
  static Future<ApiConfig?> getActiveConfig() async {
    final configs = await getAllConfigs();
    if (configs.isEmpty) return null;
    final activeId = await getActiveConfigId();
    if (activeId != null) {
      return configs.firstWhere((c) => c.id == activeId, orElse: () => configs.first);
    }
    return configs.first;
  }

  /// 测试连接并获取模型列表
  static Future<List<String>> fetchModels(String baseUrl, String apiKey) async {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
    ));
    final response = await dio.get(
      '$baseUrl/v1/models',
      options: Options(headers: {'Authorization': 'Bearer $apiKey'}),
    );
    if (response.statusCode == 200) {
      final data = response.data['data'] as List;
      return data.map<String>((m) => m['id'] as String).toList();
    } else {
      throw Exception('请求失败: ${response.statusCode}');
    }
  }
}