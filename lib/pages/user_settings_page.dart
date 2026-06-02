import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/user_profile.dart';
import '../services/user_service.dart';

class UserSettingsPage extends StatefulWidget {
  const UserSettingsPage({super.key});

  @override
  State<UserSettingsPage> createState() => _UserSettingsPageState();
}

class _UserSettingsPageState extends State<UserSettingsPage> {
  final _nameCtrl = TextEditingController();
  String _avatarPath = '';
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final user = await UserService.getUser();
    _nameCtrl.text = user.name;
    _avatarPath = user.avatarPath;
    setState(() {});
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
        AndroidUiSettings(toolbarTitle: '裁剪头像', toolbarColor: Colors.blue, lockAspectRatio: true),
        IOSUiSettings(title: '裁剪头像'),
      ],
    );
    if (cropped == null) return;

    final dir = await getApplicationDocumentsDirectory();
    final filename = 'user_avatar_${DateTime.now().millisecondsSinceEpoch}.png';
    final dest = p.join(dir.path, filename);
    await File(cropped.path).copy(dest);

    setState(() => _avatarPath = dest);
  }

  Future<void> _save() async {
    final user = UserProfile(
      name: _nameCtrl.text.trim().isEmpty ? '我' : _nameCtrl.text.trim(),
      avatarPath: _avatarPath,
    );
    await UserService.saveUser(user);
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('用户设定'),
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
                backgroundImage: _avatarPath.isNotEmpty ? FileImage(File(_avatarPath)) : null,
                child: _avatarPath.isEmpty ? const Icon(Icons.person, size: 50) : null,
              ),
            ),
            const SizedBox(height: 12),
            TextButton(onPressed: _pickAvatar, child: const Text('更换头像')),
            const SizedBox(height: 16),
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: '用户昵称'),
            ),
          ],
        ),
      ),
    );
  }
}