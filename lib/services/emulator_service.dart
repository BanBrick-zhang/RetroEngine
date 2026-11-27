import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../data/emulator_catalog.dart';
import '../models/emulator.dart';
import '../models/library.dart';
import 'preferences_service.dart';

/// 模拟器相关错误（未配置、未安装、启动失败等）。
class EmulatorException implements Exception {
  final String message;

  const EmulatorException(this.message);

  @override
  String toString() => message;
}

/// 尚未为平台指定默认模拟器，界面可据此直接弹出选择框。
class EmulatorNotConfiguredException extends EmulatorException {
  final String platformKey;

  const EmulatorNotConfiguredException(this.platformKey)
      : super('尚未为该平台设置默认模拟器');
}

/// 一次启动的结果。
///
/// [direct] 为 false 表示目标应用不支持直接加载 ROM，只被打开了主界面，
/// 界面应据此提示用户（而不是误报“正在启动游戏”）。
class EmulatorLaunchOutcome {
  final EmulatorConfig config;
  final bool direct;

  const EmulatorLaunchOutcome(this.config, {required this.direct});
}

/// 通过 Android 原生层启动外部模拟器。
class EmulatorService {
  EmulatorService._();

  static final EmulatorService instance = EmulatorService._();

  static const MethodChannel _channel =
      MethodChannel('com.savedeck.toolkit/launcher');

  Future<List<InstalledApp>>? _appsFuture;

  /// 读取全部平台配置（平台标准名 -> 配置）。
  ///
  /// 旧版本会把 AetherSX2 系模拟器存成 ACTION_VIEW，这里就地升级，
  /// 避免升级应用后已有的 PS2 默认模拟器仍然启动不到游戏。
  Future<Map<String, EmulatorConfig>> loadConfigs() async {
    final raw = await PreferencesService.emulatorConfigs;
    if (raw == null || raw.isEmpty) return <String, EmulatorConfig>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, EmulatorConfig>{};
      final result = <String, EmulatorConfig>{};
      decoded.forEach((key, value) {
        if (value is Map) {
          final config = EmulatorConfig.fromJson(
              Map<String, dynamic>.from(value));
          result[key.toString()] = upgradeLegacyConfig(config) ?? config;
        }
      });
      return result;
    } catch (_) {
      return <String, EmulatorConfig>{};
    }
  }

  Future<void> _saveConfigs(Map<String, EmulatorConfig> configs) async {
    final map = <String, dynamic>{
      for (final entry in configs.entries) entry.key: entry.value.toJson(),
    };
    await PreferencesService.setEmulatorConfigs(jsonEncode(map));
  }

  Future<EmulatorConfig?> configFor(String platformName) async {
    final configs = await loadConfigs();
    return configs[emulatorPlatformKey(platformName)];
  }

  Future<void> saveConfig(String platformName, EmulatorConfig? config) async {
    final key = emulatorPlatformKey(platformName);
    final configs = await loadConfigs();
    if (config == null) {
      configs.remove(key);
    } else {
      configs[key] = config;
    }
    await _saveConfigs(configs);
  }

  /// 已安装的桌面应用（含包名与显示名），失败时返回空列表。
  Future<List<InstalledApp>> installedApps({bool refresh = false}) {
    if (refresh || _appsFuture == null) {
      _appsFuture = _queryInstalledApps();
    }
    return _appsFuture!;
  }

  Future<List<InstalledApp>> _queryInstalledApps() async {
    try {
      final result = await _channel.invokeListMethod<dynamic>('listApps');
      if (result == null) return <InstalledApp>[];
      final apps = <InstalledApp>[];
      for (final item in result) {
        if (item is Map) {
          final app = InstalledApp.fromMap(item);
          if (app.packageName.isNotEmpty) apps.add(app);
        }
      }
      apps.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
      return apps;
    } on MissingPluginException {
      return <InstalledApp>[];
    } on PlatformException {
      return <InstalledApp>[];
    }
  }

  /// 过滤出该平台已安装的推荐模拟器。
  Future<List<EmulatorCandidate>> installedCandidates(
      String platformName) async {
    final candidates = emulatorCandidates(platformName);
    if (candidates.isEmpty) return <EmulatorCandidate>[];
    final installed = await installedApps();
    final packages = installed.map((a) => a.packageName).toSet();
    return candidates.where((c) => packages.contains(c.packageName)).toList();
  }

  /// 启动游戏；未配置或目标应用未安装时抛出 [EmulatorException]。
  ///
  /// 返回的 [EmulatorLaunchOutcome.direct] 表示 ROM 是否真的交给了模拟器：
  /// 多数模拟器支持直接加载，个别只有主界面的应用会退化为“仅打开应用”。
  Future<EmulatorLaunchOutcome> launchGame({
    required PlatformLibrary platform,
    required GameEntry game,
  }) async {
    final platformKey = emulatorPlatformKey(platform.platform);
    final config = await configFor(platform.platform);
    if (config == null) {
      throw EmulatorNotConfiguredException(platformKey);
    }
    final installed = await installedApps();
    if (installed.isNotEmpty &&
        !installed.any((a) => a.packageName == config.packageName)) {
      throw EmulatorException('「${config.label}」未安装，请在游戏库管理中重新选择');
    }

    final romPath = _absolutePath(platform.directory, game.file);
    final args = <String, dynamic>{
      'package': config.packageName,
      'activity': config.activity,
      // 使用稳定的线上标识，避免 Dart 枚举名与原生分支大小写不一致。
      'mode': config.mode.wireName,
      'filePath': romPath,
      'mime': mimeTypeForRom(romPath),
      'core': config.core,
      // 该平台的核心候选：原生层按顺序挑选实际存在的核心文件。
      'cores': coresFor(platformKey),
      'platform': platformKey,
    };
    try {
      final result = await _channel.invokeMethod<dynamic>('launch', args);
      // 新版原生返回 {direct: bool}；旧实现返回 bool（true 表示已启动）。
      var direct = true;
      if (result is Map) {
        direct = result['direct'] == true;
      } else if (result is bool) {
        direct = result;
      }
      return EmulatorLaunchOutcome(config, direct: direct);
    } on MissingPluginException {
      throw const EmulatorException('当前平台不支持启动外部模拟器');
    } on PlatformException catch (e) {
      throw EmulatorException(e.message ?? '启动失败（${e.code}）');
    }
  }

  /// 检查包是否已安装（用于界面提示）。
  Future<bool> isInstalled(String packageName) async {
    final apps = await installedApps();
    if (apps.isEmpty) return false;
    return apps.any((a) => a.packageName == packageName);
  }

  static String _absolutePath(String directory, String file) {
    if (file.startsWith('/')) return file;
    return p.join(directory, file);
  }
}