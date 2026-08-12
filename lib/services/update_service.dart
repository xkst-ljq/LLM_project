import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// GitHub 仓库信息：发布 Release 时 tag 用 `vX.Y.Z` 格式。
const String kUpdateRepoOwner = 'xkst-ljq';
const String kUpdateRepoName = 'LLM_project';

/// GitHub Release 下载 / 查看页。
String kReleasePageUrl() =>
    'https://github.com/$kUpdateRepoOwner/$kUpdateRepoName/releases/latest';

/// 更新检查结果。
class UpdateCheckResult {
  final bool hasUpdate;
  final String? latestTag; // 如 "v1.3.0"
  final String? releaseUrl;

  /// 检查是否失败（网络异常 / 没有 Release / 读不到当前版本）。
  final bool error;
  const UpdateCheckResult({
    required this.hasUpdate,
    this.latestTag,
    this.releaseUrl,
    this.error = false,
  });
}

/// 更新检测服务：获取当前版本 → 请求 GitHub 最新 Release → 比较。
class UpdateService {
  static const String _lastNotifiedKey = 'update_last_notified_version';

  /// 读取当前应用版本号（如 "1.2.6"）。
  static Future<String> _currentVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return info.version;
    } catch (_) {
      return '';
    }
  }

  /// 解析版本字符串，返回 [major, minor, patch]。
  ///
  /// 兼容多种 tag 格式：`v1.2.6`、`1.2.6`、`1.26-demo`、`1.2.5-beta.2`。
  /// 每段取**前导数字**（如 `26-demo` → 26），非数字段按 0 处理。
  static List<int> _parseVersion(String version) {
    final v = version.trim().replaceFirst(RegExp(r'^[vV]'), '');
    final parts = v.split('.');
    int seg(String s) {
      final m = RegExp(r'^\d+').firstMatch(s);
      return m == null ? 0 : int.tryParse(m.group(0)!) ?? 0;
    }

    return [
      parts.isNotEmpty ? seg(parts[0]) : 0,
      parts.length > 1 ? seg(parts[1]) : 0,
      parts.length > 2 ? seg(parts[2]) : 0,
    ];
  }

  /// a >= b 时返回 true。
  static bool _versionGte(List<int> a, List<int> b) {
    for (var i = 0; i < 3; i++) {
      if (a[i] != b[i]) return a[i] > b[i];
    }
    return true;
  }

  /// 请求 GitHub 最新 Release。
  ///
  /// 返回 null 表示请求失败或没有 Release（网络异常 / 仓库私有 / 无 tag）。
  static Future<Map<String, dynamic>?> _fetchLatestRelease() async {
    final apiPath = 'api.github.com/repos/'
        '$kUpdateRepoOwner/$kUpdateRepoName/releases/latest';
    // 直连失败时依次尝试的镜像前缀（均为 GitHub API 的代理）。
    const mirrors = <String>[
      'https://ghproxy.com/https://',
      'https://mirror.ghproxy.com/https://',
    ];

    final urls = <String>[
      'https://$apiPath',
      for (final m in mirrors) '$m$apiPath',
    ];

    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
      ),
    );

    for (final url in urls) {
      try {
        final resp = await dio.get<Map<String, dynamic>>(url);
        if (resp.statusCode == 200 && resp.data != null) {
          return resp.data;
        }
      } catch (_) {
        // 当前源失败 → 试下一个。
      }
    }
    return null;
  }

  /// 检查是否有新版本。结果不做记忆，只做单次判断。
  ///
  /// - [error] 为 true：网络失败 / 仓库无 Release / 读不到当前版本，
  ///   此时无法判断是否有更新（不是"没有更新"）。
  static Future<UpdateCheckResult> check() async {
    final current = await _currentVersion();
    final latest = await _fetchLatestRelease();
    if (latest == null || current.isEmpty) {
      return const UpdateCheckResult(hasUpdate: false, error: true);
    }

    final tagName = (latest['tag_name'] as String?) ?? '';
    if (tagName.isEmpty) {
      return const UpdateCheckResult(hasUpdate: false, error: true);
    }

    final hasUpdate = !_versionGte(_parseVersion(current), _parseVersion(tagName));
    return UpdateCheckResult(
      hasUpdate: hasUpdate,
      latestTag: tagName,
      releaseUrl: kReleasePageUrl(),
    );
  }

  /// 是否该提醒（避免每次启动都弹）：距上次提醒的版本有更新才提醒。
  static Future<bool> shouldNotify(UpdateCheckResult result) async {
    if (!result.hasUpdate || result.latestTag == null) return false;
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getString(_lastNotifiedKey) ?? '';
    // 上次提醒过的 tag 与当前相同 → 不重复提醒。
    return last != result.latestTag;
  }

  /// 标记某版本已提醒过。
  static Future<void> markNotified(String tag) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastNotifiedKey, tag);
  }
}
