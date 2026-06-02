class BackgroundCard {
  final String id;
  String name;
  String type;                // "color" / "gradient" / "image"
  String colorValue;          // 纯色值或渐变 JSON
  String originalImagePath;   // 母体原图路径（唯一图片）
  String sceneSetting;        // 场景设定描述
  bool isPreset;              // 是否为预设

  BackgroundCard({
    required this.id,
    required this.name,
    required this.type,
    this.colorValue = '',
    this.originalImagePath = '',
    this.sceneSetting = '',
    this.isPreset = false,
  });

  factory BackgroundCard.fromDb(Map<String, dynamic> data) {
    return BackgroundCard(
      id: data['id'] as String,
      name: data['name'] as String,
      type: data['type'] as String,
      colorValue: data['color_value'] as String? ?? '',
      originalImagePath: data['original_image_path'] as String? ?? '',
      sceneSetting: data['scene_setting'] as String? ?? '',
      isPreset: (data['is_preset'] as int?) == 1,
    );
  }

  Map<String, dynamic> toDb() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'color_value': colorValue,
      'original_image_path': originalImagePath,
      'scene_setting': sceneSetting,
      'is_preset': isPreset ? 1 : 0,
    };
  }
}