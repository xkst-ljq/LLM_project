import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// 生成一张纯色图片并保存到应用目录，返回文件路径
Future<String> generateDefaultCardImage({
  String colorHex = '#E0E0E0',
  int width = 400,
  int height = 600,
  String? fileName,
}) async {
  // 1. 获取应用文档目录
  final dir = await getApplicationDocumentsDirectory();
  final filename = fileName ?? 'default_card.png';
  final filePath = p.join(dir.path, filename);

  // 如果文件已存在，直接返回
  if (await File(filePath).exists()) {
    return filePath;
  }

  // 2. 解析颜色
  final color = _hexToColor(colorHex);



  // 3. 用 Canvas 绘制纯色矩形
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = color,
  );
  final picture = recorder.endRecording();

  // 4. 转为 Image，再转 PNG 字节
  final img = await picture.toImage(width, height);
  final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
  final pngBytes = byteData!.buffer.asUint8List();

  // 5. 写入文件
  await File(filePath).writeAsBytes(pngBytes);
  return filePath;
}

// 辅助：将 #RRGGBB 字符串转为 ui.Color
ui.Color _hexToColor(String hex) {
  hex = hex.replaceFirst('#', '');
  if (hex.length == 6) hex = 'FF$hex';
  return ui.Color(int.parse(hex, radix: 16));
}