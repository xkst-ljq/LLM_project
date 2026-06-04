import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AndroidDownloadService {
  static const MethodChannel _channel =
  MethodChannel('llm_project/download_saver');

  static Future<String?> saveFileToDownloads({
    required String sourcePath,
    required String fileName,
    String subDir = 'LLM Project/Backups',
    String mimeType = 'application/octet-stream',
  }) async {
    if (!Platform.isAndroid) return null;

    try {
      final result = await _channel.invokeMethod<String>(
        'saveFileToDownloads',
        {
          'sourcePath': sourcePath,
          'fileName': fileName,
          'subDir': subDir,
          'mimeType': mimeType,
        },
      );

      return result;
    } catch (e, s) {
      debugPrint('保存到系统下载目录失败: $e');
      debugPrint('$s');
      return null;
    }
  }
}