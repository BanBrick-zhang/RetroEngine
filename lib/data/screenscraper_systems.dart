/// ScreenScraper 平台 systemeid 表。
///
/// 数据文件为 `assets/screenscraper_systems.json`，由
/// `dart run tool/fetch_screenscraper_systems.dart` 调用
/// `systemesListe.php` 生成；应用启动时加载到内存供平台匹配使用。
///
/// 资源缺失或加载失败时，[PlatformCatalog.ssIdFor] 会回退到内置平台表。
import 'dart:convert';

import 'package:flutter/services.dart';

/// 单个 ScreenScraper 平台条目。
class ScreenscraperSystemInfo {
  final int id;
  final String code;
  final List<String> names;
  final List<String> extensions;

  const ScreenscraperSystemInfo({
    required this.id,
    required this.code,
    required this.names,
    required this.extensions,
  });

  factory ScreenscraperSystemInfo.fromMap(Map<String, dynamic> map) {
    return ScreenscraperSystemInfo(
      id: int.tryParse(map['id']?.toString() ?? '') ?? 0,
      code: map['code']?.toString() ?? '',
      names: (map['names'] as List? ?? const <dynamic>[])
          .map((e) => e.toString())
          .where((e) => e.isNotEmpty)
          .toList(),
      extensions: (map['extensions'] as List? ?? const <dynamic>[])
          .map((e) => e.toString().toLowerCase())
          .where((e) => e.isNotEmpty)
          .toList(),
    );
  }
}

/// 平台 systemeid 的加载与查询。
class ScreenscraperSystems {
  static const String assetPath = 'assets/screenscraper_systems.json';

  static List<ScreenscraperSystemInfo> _systems = const <ScreenscraperSystemInfo>[];
  static final Map<String, int> _nameIndex = <String, int>{};
  static final Map<String, int?> _resolveCache = <String, int?>{};
  static Future<void>? _loading;

  static List<ScreenscraperSystemInfo> get systems => _systems;

  static bool get isLoaded => _systems.isNotEmpty;

  /// 加载平台表（幂等）。失败时静默保留内置回退。
  static Future<void> load() => _loading ??= _load();

  static Future<void> _load() async {
    try {
      final text = await rootBundle.loadString(assetPath);
      final decoded = jsonDecode(text);
      if (decoded is! Map) return;
      final list = decoded['systems'];
      if (list is! List) return;

      final systems = list
          .whereType<Map>()
          .map((e) => ScreenscraperSystemInfo.fromMap(Map<String, dynamic>.from(e)))
          .where((e) => e.id > 0)
          .toList();
      if (systems.isEmpty) return;

      // 同一 systemeid 可能存在多个别名条目（如 MAME / NeoGeo 共用 142），
      // 按 id 合并，避免扩展名投票被重复计数。
      final merged = <int, ScreenscraperSystemInfo>{};
      for (final system in systems) {
        final existing = merged[system.id];
        if (existing == null) {
          merged[system.id] = system;
        } else {
          merged[system.id] = ScreenscraperSystemInfo(
            id: system.id,
            code: existing.code.isEmpty ? system.code : existing.code,
            names: <String>{...existing.names, ...system.names}.toList(),
            extensions:
                <String>{...existing.extensions, ...system.extensions}.toList(),
          );
        }
      }

      _systems = merged.values.toList();
      _buildIndex();
    } catch (_) {
      // 资源缺失或格式异常：交由调用方回退到内置表。
    }
  }

  static void _buildIndex() {
    _nameIndex.clear();
    _resolveCache.clear();
    for (final system in _systems) {
      final keys = <String>{
        normalize(system.code),
        ...system.names.map(normalize),
      };
      for (final key in keys) {
        if (key.isEmpty) continue;
        _nameIndex.putIfAbsent(key, () => system.id);
      }
    }
  }

  /// 按平台代码、目录名或别名解析 systemeid。
  static int? resolveId(String name) {
    if (!isLoaded) return null;
    final key = normalize(name);
    if (key.isEmpty) return null;
    if (_resolveCache.containsKey(key)) return _resolveCache[key];

    var result = _nameIndex[key];
    if (result == null) {
      // 目录名可能带额外前后缀（如 "GBA-roms"、"roms-gba"），
      // 仅在首尾前缀匹配时采用，避免内部包含造成误判。
      for (final entry in _nameIndex.entries) {
        if (entry.key.length < 3) continue;
        if (key.startsWith(entry.key) || key.endsWith(entry.key)) {
          result = entry.value;
          break;
        }
      }
    }

    _resolveCache[key] = result;
    return result;
  }

  /// 按 ROM 扩展名推断 systemeid，仅在唯一最高票时返回。
  static int? resolveByExtensions(Iterable<String> extensions) {
    if (!isLoaded) return null;
    final votes = <int, int>{};
    for (final ext in extensions) {
      final key = ext.toLowerCase().replaceFirst('.', '');
      if (key.isEmpty) continue;
      for (final system in _systems) {
        if (system.extensions.contains(key)) {
          votes[system.id] = (votes[system.id] ?? 0) + 1;
        }
      }
    }
    if (votes.isEmpty) return null;

    final sorted = votes.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (sorted.length > 1 && sorted[1].value == sorted.first.value) {
      // 并列命中时不猜测，交由调用方回退。
      return null;
    }
    return sorted.first.key;
  }

  /// 归一化名称：小写并去掉空格、连字符与常见分隔符。
  static String normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[\s\-_\.:：/（）()\[\]]'), '')
      .trim();
}
