import 'package:flutter/widgets.dart';

/// A11-2：向 UI 引擎子树传递角色 / 用户头像路径。
///
/// scene 接管聊天页后原生气泡消失，头像也跟着没了。作者需要能在
/// PCB 上摆一个 image 组件来显示头像——但头像路径是**运行时数据**
/// （随角色卡与全局用户设定变化），作者在编辑器里填不出来。
///
/// 走 InheritedWidget 而非 `module.properties`，与 `MessageFlowScope`
/// 同样的理由：写进 properties 会被 `_persistAssemblyElements`
/// 存进角色卡，等于把某台设备上的本地路径固化进可分享的卡片里。
class AvatarScope extends InheritedWidget {
  /// 角色头像的本地路径。空表示未设置。
  final String characterAvatar;

  /// 用户头像的本地路径。空表示未设置。
  final String userAvatar;

  const AvatarScope({
    super.key,
    required this.characterAvatar,
    required this.userAvatar,
    required super.child,
  });

  static AvatarScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AvatarScope>();
  }

  /// 按来源取头像路径；来源无效或作用域缺失时返回 null。
  ///
  /// 注意：读取方必须处在本作用域**之下**的 context——
  /// 用外层 build 的 context 会拿不到（这个坑在 MessageFlowScope 上踩过）。
  static String? resolve(BuildContext context, String? source) {
    if (source == null || source == sourceCustom) return null;
    final scope = maybeOf(context);
    if (scope == null) return null;
    switch (source) {
      case sourceCharacter:
        return scope.characterAvatar.isEmpty ? null : scope.characterAvatar;
      case sourceUser:
        return scope.userAvatar.isEmpty ? null : scope.userAvatar;
      default:
        return null;
    }
  }

  /// 图片来源：作者自己填的地址 / 路径（默认）。
  static const String sourceCustom = 'custom';

  /// 图片来源：角色头像。
  static const String sourceCharacter = 'character_avatar';

  /// 图片来源：用户头像。
  static const String sourceUser = 'user_avatar';

  /// 该来源是否需要从运行时取值。
  static bool isDynamic(String? source) =>
      source == sourceCharacter || source == sourceUser;

  @override
  bool updateShouldNotify(AvatarScope oldWidget) =>
      oldWidget.characterAvatar != characterAvatar ||
      oldWidget.userAvatar != userAvatar;
}
