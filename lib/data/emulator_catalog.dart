/// 预置模拟器目录：按平台给出推荐模拟器、RetroArch 核心，以及常见包名。
import '../models/emulator.dart';
import '../models/library.dart';

/// RetroArch 启动游戏所用的 Activity（32/64 位版本的类名相同）。
const String retroArchActivity =
    'com.retroarch.browser.retroactivity.RetroActivityFuture';

/// RetroArch 的发行包名（依次为 64 位、通用、32 位）。
const List<String> retroArchPackages = <String>[
  'com.retroarch.aarch64',
  'com.retroarch',
  'com.retroarch.ra32',
];

/// AetherSX2 系模拟器包名（PCSX2 Android 沿用同一套启动方式）。
///
/// 这些应用不响应普通的 ACTION_VIEW，而是接收 `bootPath` 额外参数（文档 URI），
/// 因此单独使用 [LaunchMode.aetherSx2] 启动。
const List<String> aetherSx2Packages = <String>[
  'xyz.aethersx2.android',
  'org.pcsx2.pcsx2',
];

/// 是否为 AetherSX2 系模拟器（旧配置里可能仍记为 [LaunchMode.view]）。
bool isAetherSx2Package(String packageName) =>
    aetherSx2Packages.contains(packageName.trim());

/// 把旧配置中误记为 ACTION_VIEW 的 AetherSX2 系配置升级为专用启动方式。
EmulatorConfig? upgradeLegacyConfig(EmulatorConfig config) {
  if (config.mode != LaunchMode.view) return null;
  if (!isAetherSx2Package(config.packageName)) return null;
  return config.copyWith(mode: LaunchMode.aetherSx2);
}

/// 各平台常用的 RetroArch 核心（第一个作为默认值）。
const Map<String, List<String>> retroArchCores = <String, List<String>>{
  'FC': <String>[
    'fceumm_libretro_android.so',
    'nestopia_libretro_android.so',
    'quicknes_libretro_android.so',
  ],
  'SFC': <String>[
    'snes9x2005_plus_libretro_android.so',
    'snes9x_libretro_android.so',
    'bsnes_libretro_android.so',
  ],
  'GB': <String>[
    'gambatte_libretro_android.so',
    'sameboy_libretro_android.so',
  ],
  'GBC': <String>[
    'gambatte_libretro_android.so',
    'sameboy_libretro_android.so',
  ],
  'GBA': <String>[
    'mgba_libretro_android.so',
    'gpsp_libretro_android.so',
    'vba_next_libretro_android.so',
  ],
  'PSX': <String>[
    'pcsx_rearmed_libretro_android.so',
    'swanstation_libretro_android.so',
    'mednafen_psx_libretro_android.so',
  ],
  'PS2': <String>[
    // Android 端没有 pcsx2 核心，PS2 实际可用的是 Play!。
    'play_libretro_android.so',
  ],
};

/// 平台别名 -> 目录中使用的标准平台名。
String emulatorPlatformKey(String platformName) {
  final info = PlatformCatalog.byFolderName(platformName);
  return info?.name ?? platformName.trim().toUpperCase();
}

/// 该平台是否有预置推荐（决定界面上是否显示「推荐模拟器」分组）。
bool hasEmulatorPreset(String platformKey) =>
    emulatorCandidates(platformKey).isNotEmpty;

/// 指定平台的模拟器候选列表（含包名不同的多个变体）。
List<EmulatorCandidate> emulatorCandidates(String platformKey) {
  final key = emulatorPlatformKey(platformKey);
  final cores = retroArchCores[key] ?? const <String>[];
  final list = <EmulatorCandidate>[];

  // 仅在知道可用核心时推荐 RetroArch，避免列出一个无法直接启动的选项。
  // 无预置核心的平台仍可从「其他已安装应用」中手动选择。
  if (cores.isNotEmpty) {
    for (final pkg in retroArchPackages) {
      list.add(EmulatorCandidate(
        label: 'RetroArch (${_archLabel(pkg)})',
        packageName: pkg,
        activity: retroArchActivity,
        mode: LaunchMode.retroArch,
        core: cores.first,
      ));
    }
  }

  switch (key) {
    case '3DS':
      list.add(const EmulatorCandidate(
        label: 'Citra',
        packageName: 'org.citra_emu.citra',
        mode: LaunchMode.view,
      ));
      list.add(const EmulatorCandidate(
        label: 'Citra Canary',
        packageName: 'org.citra_emu.citra.canary',
        mode: LaunchMode.view,
      ));
      list.add(const EmulatorCandidate(
        label: 'Azahar',
        packageName: 'org.azahar_emu.azahar',
        mode: LaunchMode.view,
      ));
      // Azahar 早期版本沿用 Lime3DS 的包名。
      list.add(const EmulatorCandidate(
        label: 'Azahar / Lime3DS（旧包名）',
        packageName: 'io.github.lime3ds.android',
        mode: LaunchMode.view,
      ));
      break;
    case 'PS2':
      // PCSX2 / AetherSX2 不支持 ACTION_VIEW，必须用 EmulationActivity 接收
      // bootPath（文档 URI），否则只会打开应用主界面。
      list.add(const EmulatorCandidate(
        label: 'PCSX2',
        packageName: 'org.pcsx2.pcsx2',
        mode: LaunchMode.aetherSx2,
      ));
      list.add(const EmulatorCandidate(
        label: 'AetherSX2',
        packageName: 'xyz.aethersx2.android',
        mode: LaunchMode.aetherSx2,
      ));
      break;
    case 'PSP':
      list.add(const EmulatorCandidate(
        label: 'PPSSPP',
        packageName: 'org.ppsspp.ppsspp',
        mode: LaunchMode.view,
      ));
      list.add(const EmulatorCandidate(
        label: 'PPSSPP Gold',
        packageName: 'org.ppsspp.ppssppgold',
        mode: LaunchMode.view,
      ));
      break;
    case 'PSX':
      list.add(const EmulatorCandidate(
        label: 'DuckStation',
        packageName: 'com.github.stenzek.duckstation',
        mode: LaunchMode.view,
      ));
      break;
  }
  return list;
}

/// 该平台的推荐核心列表；无预置时返回空列表。
List<String> coresFor(String platformKey) =>
    retroArchCores[emulatorPlatformKey(platformKey)] ?? const <String>[];

String _archLabel(String packageName) {
  if (packageName.endsWith('aarch64')) return '64 位';
  if (packageName.endsWith('ra32')) return '32 位';
  return '通用';
}

/// 根据 ROM 扩展名给出 ACTION_VIEW 的 MIME 类型。
String mimeTypeForRom(String filePath) {
  final dot = filePath.lastIndexOf('.');
  final ext = dot < 0 ? '' : filePath.substring(dot + 1).toLowerCase();
  switch (ext) {
    case 'zip':
      return 'application/zip';
    case '7z':
      return 'application/x-7z-compressed';
    case 'iso':
    case 'cso':
    case 'chd':
    case 'gdi':
      return 'application/octet-stream';
    case '3ds':
    case 'cci':
    case 'cxi':
    case 'cia':
      return 'application/x-nintendo-3ds-rom';
    case 'nes':
      return 'application/x-nes-rom';
    case 'sfc':
    case 'smc':
      return 'application/x-snes-rom';
    case 'gba':
      return 'application/x-gba-rom';
    case 'gb':
    case 'gbc':
      return 'application/x-gameboy-rom';
    case 'n64':
    case 'z64':
      return 'application/x-n64-rom';
    case 'nds':
      return 'application/x-nds-rom';
  }
  return '*/*';
}