import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../utils/id_utils.dart';
import '../widgets/image_crop_page.dart';

class ImagePickService {
  static final ImagePicker _picker = ImagePicker();

  static Future<ImageSource?> _showSourceDialog(
      BuildContext context, {
        required String title,
        bool allowCamera = true,
      }) {
    return showDialog<ImageSource>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(title),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, ImageSource.gallery),
            child: const Text('从相册选择'),
          ),
          if (allowCamera)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, ImageSource.camera),
              child: const Text('拍照'),
            ),
        ],
      ),
    );
  }

  static Future<String?> pickAvatar(BuildContext context) async {
    return _pickCropAndSave(
      context,
      title: '选择头像来源',
      filePrefix: 'avatar',
      aspectRatio: 1.0,
      pickMaxWidth: 1024,
      cropTitle: '裁剪头像',
      guideText: '拖动或缩放图片，将头像主体放入裁剪区域。',
    );
  }

  static Future<String?> pickCharacterCard(BuildContext context) async {
    return _pickCropAndSave(
      context,
      title: '选择卡片来源',
      filePrefix: 'card',
      aspectRatio: 2 / 3,
      pickMaxWidth: 2048,
      cropTitle: '裁剪角色卡封面',
      guideText: '角色卡封面将保存为 2:3 竖卡比例。拖动或缩放图片调整构图。',
    );
  }

  /// 背景图保留原图比例，不裁剪。
  /// 选择一张本地图片并保存到应用文档目录，返回本地绝对路径。
  /// 用于「开场白 / 描述里插入图片」：不裁剪，纯本地，符合本地优先理念。
  static Future<String?> pickInsertImage(BuildContext context) async {
    try {
      final source = await _showSourceDialog(
        context,
        title: '选择图片来源',
        allowCamera: false,
      );

      if (source == null) return null;

      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 95,
      );

      if (picked == null) return null;

      return _saveFileToLocal(
        sourcePath: picked.path,
        filePrefix: 'embedded_image',
        extension: p.extension(picked.path).isEmpty
            ? '.png'
            : p.extension(picked.path),
      );
    } catch (e, s) {
      debugPrint('选择插入图片失败: $e');
      debugPrint('$s');
      return null;
    }
  }

  static Future<String?> pickBackgroundImage(BuildContext context) async {
    try {
      final source = await _showSourceDialog(
        context,
        title: '选择背景来源',
        allowCamera: false,
      );

      if (source == null) return null;

      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 95,
      );

      if (picked == null) return null;

      return _saveFileToLocal(
        sourcePath: picked.path,
        filePrefix: 'background_original',
        extension: p.extension(picked.path).isEmpty
            ? '.jpg'
            : p.extension(picked.path),
      );
    } catch (e, s) {
      debugPrint('选择背景图片失败: $e');
      debugPrint('$s');
      return null;
    }
  }

  static Future<String?> _pickCropAndSave(
      BuildContext context, {
        required String title,
        required String filePrefix,
        required double aspectRatio,
        required double pickMaxWidth,
        required String cropTitle,
        required String guideText,
      }) async {
    try {
      final source = await _showSourceDialog(
        context,
        title: title,
        allowCamera: true,
      );

      if (source == null) return null;

      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 95,
        maxWidth: pickMaxWidth,
      );

      if (picked == null) return null;

      final originalBytes = await File(picked.path).readAsBytes();

      if (!context.mounted) return null;

      final croppedBytes = await Navigator.push<Uint8List>(
        context,
        MaterialPageRoute(
          builder: (_) => ImageCropPage(
            imageBytes: originalBytes,
            aspectRatio: aspectRatio,
            title: cropTitle,
            guideText: guideText,
          ),
        ),
      );

      if (croppedBytes == null) return null;

      return _saveCroppedJpgToLocal(
        imageBytes: croppedBytes,
        filePrefix: filePrefix,
      );
    } catch (e, s) {
      debugPrint('选择图片失败: $e');
      debugPrint('$s');
      return null;
    }
  }

  static Future<String?> _saveCroppedJpgToLocal({
    required Uint8List imageBytes,
    required String filePrefix,
  }) async {
    try {
      final decoded = img.decodeImage(imageBytes);

      final Uint8List outputBytes;

      if (decoded != null) {
        outputBytes = Uint8List.fromList(
          img.encodeJpg(decoded, quality: 92),
        );
      } else {
        outputBytes = imageBytes;
      }

      return _saveBytesToLocal(
        bytes: outputBytes,
        filePrefix: filePrefix,
        extension: '.jpg',
      );
    } catch (e, s) {
      debugPrint('保存裁剪图片失败: $e');
      debugPrint('$s');
      return null;
    }
  }

  static Future<String?> _saveFileToLocal({
    required String sourcePath,
    required String filePrefix,
    required String extension,
  }) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final safeExt = extension.startsWith('.') ? extension : '.$extension';
      final fileName = '${filePrefix}_${IdUtils.timestampId()}$safeExt';
      final destPath = p.join(dir.path, fileName);

      await File(sourcePath).copy(destPath);

      return destPath;
    } catch (e, s) {
      debugPrint('保存图片失败: $e');
      debugPrint('$s');
      return null;
    }
  }

  static Future<String?> _saveBytesToLocal({
    required Uint8List bytes,
    required String filePrefix,
    required String extension,
  }) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final safeExt = extension.startsWith('.') ? extension : '.$extension';
      final fileName = '${filePrefix}_${IdUtils.timestampId()}$safeExt';
      final destPath = p.join(dir.path, fileName);

      await File(destPath).writeAsBytes(bytes, flush: true);

      return destPath;
    } catch (e, s) {
      debugPrint('保存图片失败: $e');
      debugPrint('$s');
      return null;
    }
  }
}