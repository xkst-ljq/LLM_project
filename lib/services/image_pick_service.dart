import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../utils/id_utils.dart';

enum PickImageType {
  avatar,
  characterCard,
  background,
}

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
      type: PickImageType.avatar,
      title: '选择头像来源',
      filePrefix: 'avatar',
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      maxWidth: 512,
      maxHeight: 512,
      pickMaxWidth: 1024,
      cropTitle: '裁剪头像',
    );
  }

  static Future<String?> pickCharacterCard(BuildContext context) async {
    return _pickCropAndSave(
      context,
      type: PickImageType.characterCard,
      title: '选择卡片来源',
      filePrefix: 'card',
      aspectRatio: const CropAspectRatio(ratioX: 2, ratioY: 3),
      maxWidth: 1200,
      maxHeight: 1800,
      pickMaxWidth: 2048,
      cropTitle: '裁剪卡片',
    );
  }

  /// 背景图保留原图比例，不裁剪。
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

      return _saveImageToLocal(
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
        required PickImageType type,
        required String title,
        required String filePrefix,
        required CropAspectRatio aspectRatio,
        required int maxWidth,
        required int maxHeight,
        required double pickMaxWidth,
        required String cropTitle,
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
        imageQuality: 90,
        maxWidth: pickMaxWidth,
      );

      if (picked == null) return null;

      CroppedFile? cropped;

      try {
        cropped = await ImageCropper().cropImage(
          sourcePath: picked.path,
          aspectRatio: aspectRatio,
          maxWidth: maxWidth,
          maxHeight: maxHeight,
          compressQuality: 90,
          compressFormat: ImageCompressFormat.jpg,
          uiSettings: [
            AndroidUiSettings(
              toolbarTitle: cropTitle,
              toolbarColor: Colors.blue,
              toolbarWidgetColor: Colors.white,
              lockAspectRatio: true,
            ),
            IOSUiSettings(title: cropTitle),
          ],
        );
      } catch (e, s) {
        debugPrint('裁剪失败，使用原图: $e');
        debugPrint('$s');
      }

      final sourcePath = cropped?.path ?? picked.path;

      // 裁剪输出指定为 jpg，因此保存扩展名统一为 .jpg
      return _saveImageToLocal(
        sourcePath: sourcePath,
        filePrefix: filePrefix,
        extension: '.jpg',
      );
    } catch (e, s) {
      debugPrint('选择图片失败: $e');
      debugPrint('$s');
      return null;
    }
  }

  static Future<String?> _saveImageToLocal({
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
}