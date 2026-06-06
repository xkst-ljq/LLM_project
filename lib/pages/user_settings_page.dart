import 'dart:io';
import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import '../services/user_service.dart';
import '../services/image_pick_service.dart';

class UserSettingsPage extends StatefulWidget {
  const UserSettingsPage({super.key});

  @override
  State<UserSettingsPage> createState() => _UserSettingsPageState();
}

class _UserSettingsPageState extends State<UserSettingsPage> {
  final _nameCtrl = TextEditingController();
  String _avatarPath = '';

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
    final savedPath = await ImagePickService.pickAvatar(context);

    if (!mounted) return;

    if (savedPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未选择头像或头像保存失败')),
      );
      return;
    }

    setState(() => _avatarPath = savedPath);
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