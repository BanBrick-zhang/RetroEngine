// 调用 ScreenScraper systemesListe.php，生成 assets/screenscraper_systems.json。
//
// 用法（在项目根目录执行）：
//   dart run tool/fetch_screenscraper_systems.dart
//
// 注意：需要有效的开发者凭据。若接口返回 "Erreur de login"，
// 说明 devid/devpassword 未通过校验，脚本会保留原文件并退出。
import 'dart:convert';
import 'dart:io';

/// 与 lib/services/screenscraper_service.dart 中的 ScreenscraperConfig 保持一致。
const String devId = '';
const String devPassword = '';

const String outputPath = 'assets/screenscraper_systems.json';

Future<void> main() async {
  final uri = Uri.https('api.screenscraper.fr', '/api2/systemesListe.php', <String, String>{
    'devid': devId,
    'devpassword': devPassword,
    'output': 'json',
  });

  stdout.writeln('请求：$uri');
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.userAgentHeader, 'SaveDeckToolkit/1.0');
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();

    if (body.trimLeft().startsWith('Erreur')) {
      stderr.writeln('接口返回错误，未更新文件：\n$body');
      exitCode = 1;
      return;
    }
    if (response.statusCode != 200) {
      stderr.writeln('HTTP ${response.statusCode}，未更新文件。');
      exitCode = 1;
      return;
    }

    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      stderr.writeln('返回格式异常，未更新文件。');
      exitCode = 1;
      return;
    }

    final responseMap = decoded['response'];
    final rawList = responseMap is Map ? responseMap['systemes'] : null;
    if (rawList is! List) {
      stderr.writeln('未找到 systemes 列表，未更新文件。');
      exitCode = 1;
      return;
    }

    final systems = <Map<String, dynamic>>[];
    for (final raw in rawList) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      final id = int.tryParse(map['id']?.toString() ?? '');
      if (id == null || id <= 0) continue;

      final names = <String>{};
      var code = '';
      final noms = map['noms'];
      if (noms is Map) {
        // 单个字段可能是逗号分隔的多个别名（如 nom_retropie: "genesis,megadrive"）。
        void addNames(String? value) {
          final text = value?.trim() ?? '';
          if (text.isEmpty) return;
          for (final part in text.split(',')) {
            final name = part.trim();
            if (name.isNotEmpty) names.add(name);
          }
        }

        for (final value in noms.values) {
          addNames(value?.toString());
        }
        code = (noms['nom_recalbox'] ??
                noms['nom_retropie'] ??
                noms['nom_eu'] ??
                noms['nom_us'] ??
                '')
            .toString()
            .split(',')
            .first
            .trim();
      }

      final extensions = <String>{};
      final ext = map['extensions'];
      if (ext is List) {
        for (final item in ext) {
          final text = item.toString().trim().toLowerCase();
          if (text.isNotEmpty) extensions.add(text.replaceFirst('.', ''));
        }
      } else if (ext is String) {
        for (final item in ext.split(RegExp(r'[,\s]+'))) {
          final text = item.trim().toLowerCase().replaceFirst('.', '');
          if (text.isNotEmpty) extensions.add(text);
        }
      }

      systems.add(<String, dynamic>{
        'id': id,
        'code': code,
        'names': names.toList()..sort(),
        'extensions': extensions.toList()..sort(),
      });
    }

    if (systems.isEmpty) {
      stderr.writeln('解析结果为空，未更新文件。');
      exitCode = 1;
      return;
    }

    systems.sort((a, b) => (a['id'] as int).compareTo(b['id'] as int));
    final output = <String, dynamic>{
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
      'source': 'https://api.screenscraper.fr/api2/systemesListe.php',
      'systems': systems,
    };

    final file = File(outputPath);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(output),
      flush: true,
    );
    stdout.writeln('已写入 ${systems.length} 个平台 -> $outputPath');
  } catch (e) {
    stderr.writeln('请求失败：$e');
    exitCode = 1;
  } finally {
    client.close(force: true);
  }
}
