# LLM Project

一个基于 Flutter 开发的 LLM 角色聊天 App。

## 功能

- 多 API 配置
- 角色卡管理
- 世界书管理
- 背景设置
- 聊天记录保存
- 图片头像与卡片裁剪
- Markdown 消息显示

## 下载

请前往 Releases 页面下载最新 APK。

## 使用说明

用户需要自行配置 API Key。  
API Key 使用 flutter_secure_storage 保存在本地，不会上传到服务器。

## 注意事项

如果在小米 / 澎湃 OS 设备上顶部出现黑框，请在系统设置中将本应用的状态栏/刘海显示设置为“始终显示”或“自动适配”。

## 构建

```bash
flutter pub get
flutter build apk --release --target-platform android-arm64
```
