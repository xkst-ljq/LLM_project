class ApiConfig {
  final String id;         // 唯一标识（时间戳）
  String name;             // 配置名称，如 "DeepSeek工作号"
  String baseUrl;          // API 地址
  String apiKey;           // API Key（实际存储时用安全存储，这里只存引用）
  String model;            // 模型名称，如 "deepseek-v4-flash"

  ApiConfig({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
  });

  // 从 JSON 反序列化
  factory ApiConfig.fromJson(Map<String, dynamic> json) {
    return ApiConfig(
      id: json['id'] as String,
      name: json['name'] as String,
      baseUrl: json['base_url'] as String,
      apiKey: '', // Key 不存明文，从安全存储读取
      model: json['model'] as String,
    );
  }

  // 序列化为 JSON（不包含 Key）
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'base_url': baseUrl,
      'model': model,
    };
  }
}