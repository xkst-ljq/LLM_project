import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/character_card.dart';
import '../services/database_service.dart';

class RoleUserSettingsPage extends StatefulWidget {
  final CharacterCard character;

  const RoleUserSettingsPage({super.key, required this.character});

  @override
  State<RoleUserSettingsPage> createState() => _RoleUserSettingsPageState();
}

class _RoleUserSettingsPageState extends State<RoleUserSettingsPage> {
  final _nameCtrl = TextEditingController();
  final _detailCtrl = TextEditingController();
  String _avatarPath = '';
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _nameCtrl.text = widget.character.userName;
    _detailCtrl.text = widget.character.userDetailSetting;
    _avatarPath = widget.character.userAvatar;
  }

  Future<void> _pickAvatar() async {
    final source = await showDialog<ImageSource>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择头像来源'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, ImageSource.gallery),
            child: const Text('从相册选择'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, ImageSource.camera),
            child: const Text('拍照'),
          ),
        ],
      ),
    );
    if (source == null) return;

    final XFile? picked = await _picker.pickImage(source: source);
    if (picked == null) return;

    final CroppedFile? cropped = await ImageCropper().cropImage(
      sourcePath: picked.path,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: '裁剪头像',
          toolbarColor: Colors.blue,
          lockAspectRatio: true,
        ),
        IOSUiSettings(title: '裁剪头像'),
      ],
    );
    if (cropped == null) return;

    final dir = await getApplicationDocumentsDirectory();
    final filename =
        'role_user_avatar_${DateTime.now().millisecondsSinceEpoch}.png';
    final dest = p.join(dir.path, filename);
    await File(cropped.path).copy(dest);

    setState(() => _avatarPath = dest);
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final detail = _detailCtrl.text.trim();
    await DatabaseService.updateCharacter({
      'id': widget.character.id,
      'user_name': name,
      'user_avatar': _avatarPath,
      'user_detail_setting': detail,
    });
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _detailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('此角色的用户设定'),
        actions: [
          FilledButton(
            onPressed: _save,
            style: FilledButton.styleFrom(minimumSize: const Size(60, 32)),
            child: const Text('保存'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            GestureDetector(
              onTap: _pickAvatar,
              child: CircleAvatar(
                radius: 40,
                backgroundColor: Colors.grey.shade300,
                backgroundImage: _avatarPath.isNotEmpty
                    ? FileImage(File(_avatarPath))
                    : null,
                child: _avatarPath.isEmpty
                    ? Icon(Icons.person, size: 50, color: Colors.grey.shade600)
                    : null,
              ),
            ),
            const SizedBox(height: 12),
            TextButton(onPressed: _pickAvatar, child: const Text('更换头像')),
            const SizedBox(height: 16),
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: '当前角色的用户昵称'),
            ),
            const SizedBox(height: 16),
            // 新增详细设定输入框
            TextField(
              controller: _detailCtrl,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: '用户详细设定（仅当前角色）',
                hintText: '输入你的详细设定，如：性别、年龄、背景故事等',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
