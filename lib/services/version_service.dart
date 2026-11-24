import 'package:flutter/services.dart' show rootBundle;

/// 从打包进 assets 的 pubspec.yaml 读取版本，修改 pubspec 后自动生效。
class VersionService {
  static Future<String> load() async {
    try {
      final content = await rootBundle.loadString('pubspec.yaml');
      final match = RegExp(r'^version:\s*(.+)$', multiLine: true)
          .firstMatch(content);
      final version = match?.group(1)?.trim();
      return version == null || version.isEmpty ? '未知版本' : version;
    } catch (_) {
      return '未知版本';
    }
  }
}
