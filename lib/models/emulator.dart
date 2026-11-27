/// 模拟器启动配置与相关模型。

/// 模拟器的启动方式。
enum LaunchMode {
  /// RetroArch：通过 RetroActivityFuture 组件 + ROM/LIBRETRO 额外参数启动。
  retroArch,

  /// AetherSX2 系（含 PCSX2 Android）：EmulationActivity + bootPath 文档 URI。
  aetherSx2,

  /// 通用 ACTION_VIEW：把 ROM 以 content:// 形式交给目标应用。
  view,

  /// 仅拉起目标应用主界面。
  app,
}

/// 传给原生层的启动方式标识。
///
/// 原生侧按小写字符串分支（`retroarch` / `aethersx2` / `view` / `app`），
/// 这里统一转换，避免枚举名大小写与原生判断不一致导致启动方式被忽略。
extension LaunchModeWire on LaunchMode {
  String get wireName {
    switch (this) {
      case LaunchMode.retroArch:
        return 'retroarch';
      case LaunchMode.aetherSx2:
        return 'aethersx2';
      case LaunchMode.view:
        return 'view';
      case LaunchMode.app:
        return 'app';
    }
  }
}

LaunchMode launchModeFromName(String? value) {
  switch ((value ?? '').trim().toLowerCase()) {
    case 'retroarch':
      return LaunchMode.retroArch;
    case 'aethersx2':
      return LaunchMode.aetherSx2;
    case 'view':
      return LaunchMode.view;
    default:
      return LaunchMode.app;
  }
}

/// 某个平台的默认模拟器配置（持久化到 SharedPreferences）。
class EmulatorConfig {
  /// 展示名称，例如「RetroArch (mgba)」「PPSSPP」。
  final String label;

  /// 目标应用包名。
  final String packageName;

  /// 指定 Activity 类名（不带包名的相对或全限定名，可空）。
  final String? activity;

  final LaunchMode mode;

  /// RetroArch 核心文件（形如 `mgba_libretro_android.so`，也允许绝对路径）。
  final String? core;

  const EmulatorConfig({
    required this.label,
    required this.packageName,
    this.activity,
    this.mode = LaunchMode.app,
    this.core,
  });

  EmulatorConfig copyWith({
    String? label,
    String? packageName,
    String? activity,
    LaunchMode? mode,
    String? core,
  }) {
    return EmulatorConfig(
      label: label ?? this.label,
      packageName: packageName ?? this.packageName,
      activity: activity ?? this.activity,
      mode: mode ?? this.mode,
      core: core ?? this.core,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'label': label,
        'package': packageName,
        'activity': activity,
        'mode': mode.name,
        'core': core,
      };

  factory EmulatorConfig.fromJson(Map<String, dynamic> json) {
    return EmulatorConfig(
      label: (json['label'] ?? '').toString(),
      packageName: (json['package'] ?? '').toString(),
      activity: json['activity']?.toString(),
      mode: launchModeFromName(json['mode']?.toString()),
      core: json['core']?.toString(),
    );
  }
}

/// 手机上已安装的可启动应用。
class InstalledApp {
  final String packageName;
  final String label;

  const InstalledApp({required this.packageName, required this.label});

  static InstalledApp fromMap(Map<dynamic, dynamic> map) => InstalledApp(
        packageName: (map['package'] ?? '').toString(),
        label: (map['label'] ?? '').toString(),
      );
}

/// 目录里预置的模拟器候选（用于过滤「已安装」与生成默认配置）。
class EmulatorCandidate {
  final String label;
  final String packageName;
  final String? activity;
  final LaunchMode mode;
  final String? core;

  const EmulatorCandidate({
    required this.label,
    required this.packageName,
    this.activity,
    this.mode = LaunchMode.app,
    this.core,
  });

  EmulatorConfig toConfig() => EmulatorConfig(
        label: label,
        packageName: packageName,
        activity: activity,
        mode: mode,
        core: core,
      );
}