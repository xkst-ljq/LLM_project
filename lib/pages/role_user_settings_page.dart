import 'dart:io';
import 'package:flutter/material.dart';
import '../models/character_card.dart';
import '../services/database_service.dart';
import '../utils/protagonist_setting_utils.dart';
import '../services/user_service.dart';
import '../services/image_pick_service.dart';

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
  bool _usingOverride = false;
  String _sourceLabel = '';

  @override
  void initState() {
    super.initState();
    _loadInitialSettings();
  }

  Future<void> _loadInitialSettings() async {
    final globalUser = await UserService.getUser();

    if (!mounted) return;

    final localName = widget.character.userName;
    final localAvatar = widget.character.userAvatar;
    final localDetail = widget.character.userDetailSetting;

    final protagonistName =
    ProtagonistSettingUtils.getProtagonistName(widget.character);

    final protagonistDetail =
    ProtagonistSettingUtils.formatProtagonistDetail(widget.character);

    final hasOverride =
        localName.isNotEmpty || localAvatar.isNotEmpty || localDetail.isNotEmpty;

    final hasProtagonistDefault =
        protagonistName.isNotEmpty || protagonistDetail.isNotEmpty;

    final effectiveName = localName.isNotEmpty
        ? localName
        : protagonistName.isNotEmpty
        ? protagonistName
        : globalUser.name;

    final effectiveAvatar = localAvatar.isNotEmpty
        ? localAvatar
        : globalUser.avatarPath;

    final effectiveDetail = localDetail.isNotEmpty
        ? localDetail
        : protagonistDetail;

    setState(() {
      _usingOverride = hasOverride;

      _nameCtrl.text = effectiveName;
      _detailCtrl.text = effectiveDetail;
      _avatarPath = effectiveAvatar;

      _sourceLabel = hasOverride
          ? '当前使用：本卡对话覆盖设定'
          : hasProtagonistDefault
          ? '当前使用：角色卡默认主角设定'
          : '当前使用：全局用户设定';
    });
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
    final name = _nameCtrl.text.trim();
    final detail = _detailCtrl.text.trim();

    await DatabaseService.updateCharacter({
      'id': widget.character.id,
      'user_name': name,
      'user_avatar': _avatarPath,
      'user_detail_setting': detail,
    });

    widget.character.userName = name;
    widget.character.userAvatar = _avatarPath;
    widget.character.userDetailSetting = detail;

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已保存为当前对话用户设定')),
    );

    Navigator.pop(context);
  }

  Future<void> _resetToDefaultSetting() async {
    final globalUser = await UserService.getUser();

    final protagonistName =
    ProtagonistSettingUtils.getProtagonistName(widget.character);

    final protagonistDetail =
    ProtagonistSettingUtils.formatProtagonistDetail(widget.character);

    final hasProtagonistDefault =
        protagonistName.isNotEmpty || protagonistDetail.isNotEmpty;

    await DatabaseService.updateCharacter({
      'id': widget.character.id,
      'user_name': '',
      'user_avatar': '',
      'user_detail_setting': '',
    });

    widget.character.userName = '';
    widget.character.userAvatar = '';
    widget.character.userDetailSetting = '';

    if (!mounted) return;

    setState(() {
      _usingOverride = false;

      _nameCtrl.text =
      protagonistName.isNotEmpty ? protagonistName : globalUser.name;

      _detailCtrl.text = protagonistDetail;

      // 主角设定没有头像，所以恢复默认时头像回到全局头像
      _avatarPath = globalUser.avatarPath;

      _sourceLabel = hasProtagonistDefault
          ? '当前使用：角色卡默认主角设定'
          : '当前使用：全局用户设定';
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          hasProtagonistDefault
              ? '已恢复为角色卡默认主角设定'
              : '已恢复为全局用户设定',
        ),
      ),
    );
  }

  Future<void> _saveAsCardDefault() async {
    if (widget.character.cardType != 'system') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('只有系统卡可以保存为主角默认设定')),
      );
      return;
    }

    final name = _nameCtrl.text.trim();
    final detailText = _detailCtrl.text.trim();

    final detailMap = ProtagonistSettingUtils.parseDetailText(detailText);

    final newEntriesJson =
    ProtagonistSettingUtils.updateEntriesJsonWithProtagonist(
      entriesJson: widget.character.entriesJson,
      name: name,
      detail: detailMap,
    );

    await DatabaseService.updateCharacter({
      'id': widget.character.id,
      'entries_json': newEntriesJson,

      // 当前内容已经保存为默认值，所以清空覆盖设定，避免两份数据不一致
      'user_name': '',
      'user_avatar': '',
      'user_detail_setting': '',
    });

    widget.character.entriesJson = newEntriesJson;
    widget.character.userName = '';
    widget.character.userAvatar = '';
    widget.character.userDetailSetting = '';

    final globalUser = await UserService.getUser();

    if (!mounted) return;

    setState(() {
      _usingOverride = false;
      _sourceLabel = '当前使用：角色卡默认主角设定';

      // 名称和详细设定已经写入角色卡默认值，所以界面继续显示当前内容
      _avatarPath = globalUser.avatarPath;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已保存为角色卡默认主角设定')),
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _detailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      appBar: AppBar(
        title: const Text('当前对话用户设定'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(
                minimumSize: const Size(60, 32),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              child: const Text('保存'),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: GestureDetector(
                onTap: _pickAvatar,
                child: CircleAvatar(
                  radius: 40,
                  backgroundColor: Colors.grey.shade300,
                  backgroundImage:
                  _avatarPath.isNotEmpty ? FileImage(File(_avatarPath)) : null,
                  child: _avatarPath.isEmpty
                      ? Icon(Icons.person, size: 50, color: Colors.grey.shade600)
                      : null,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: _pickAvatar,
                child: const Text('更换头像'),
              ),
            ),
            const SizedBox(height: 12),

            // 当前设定来源提示
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: primaryColor.withValues(alpha: 0.16),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _usingOverride
                        ? Icons.edit_note_rounded
                        : Icons.auto_stories_rounded,
                    size: 18,
                    color: primaryColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _sourceLabel,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: primaryColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: '当前对话中的用户昵称',
                hintText: '例如：主角、旅行者、你的名字',
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 16),

            TextField(
              controller: _detailCtrl,
              minLines: 5,
              maxLines: 10,
              decoration: const InputDecoration(
                labelText: '用户详细设定',
                hintText: '例如：\n种族：人类\n性别：男\n年龄：17\n身体：普通高中生体型\n背景：被召唤到异世界',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),

            const SizedBox(height: 12),

            // 两个辅助按钮，用 Wrap 防止小屏幕横向溢出
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _resetToDefaultSetting,
                  icon: const Icon(Icons.restore, size: 16),
                  label: const Text('恢复默认设定'),
                ),

                // 只有系统卡才显示“保存为角色卡默认”
                if (widget.character.cardType == 'system')
                  OutlinedButton.icon(
                    onPressed: _saveAsCardDefault,
                    icon: const Icon(Icons.save_as, size: 16),
                    label: const Text('保存为角色卡默认'),
                  ),
              ],
            ),

            const SizedBox(height: 12),

            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                widget.character.cardType == 'system'
                    ? '说明：\n'
                    '1. 点击右上角“保存”会保存为当前卡的对话覆盖设定，不会修改角色卡默认主角设定。\n'
                    '2. “恢复默认设定”会清空当前覆盖设定，并重新使用角色卡主角设定；如果角色卡没有主角设定，则使用全局用户设定。\n'
                    '3. “保存为角色卡默认”会把当前内容写回角色卡的主角设定，并清空覆盖设定。'
                    : '说明：\n'
                    '1. 点击右上角“保存”会保存为当前人物卡的用户覆盖设定。\n'
                    '2. “恢复默认设定”会清空当前覆盖设定，并重新使用主菜单里的全局用户设定。\n'
                    '3. 人物卡没有主角默认设定，因此不会显示“保存为角色卡默认”。',
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.45,
                  color: Colors.black54,
                ),
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
