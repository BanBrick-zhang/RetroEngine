import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/cloud_save.dart';

/// 模拟器存档目录检测与文件过滤。
class EmulatorSaveService {
  EmulatorSaveService._();

  /// Android 共享存储根目录候选。
  static const List<String> _roots = <String>[
    '/storage/emulated/0',
    '/sdcard',
  ];

  /// 自动检测用到的路径模板，使用 `{root}` 占位。
  static const List<_Candidate> _candidates = <_Candidate>[
    // RetroArch：存档与即时存档分开同步。
    _Candidate(
      EmulatorKind.retroArch,
      'RetroArch 存档',
      'RetroArch-saves',
      '{root}/RetroArch/saves',
      includeAll: true,
    ),
    _Candidate(
      EmulatorKind.retroArch,
      'RetroArch 即时存档',
      'RetroArch-states',
      '{root}/RetroArch/states',
      includeAll: true,
    ),
    _Candidate(
      EmulatorKind.retroArch,
      'RetroArch 存档',
      'RetroArch-saves',
      '{root}/Android/data/com.retroarch/files/saves',
      includeAll: true,
    ),
    _Candidate(
      EmulatorKind.retroArch,
      'RetroArch 存档',
      'RetroArch-saves',
      '{root}/Android/data/com.retroarch.aarch64/files/saves',
      includeAll: true,
    ),
    // PPSSPP：SAVEDATA 与 PPSSPP_STATE。
    _Candidate(
      EmulatorKind.ppsspp,
      'PPSSPP 存档',
      'PPSSPP-SAVEDATA',
      '{root}/PSP/SAVEDATA',
      includeAll: true,
    ),
    _Candidate(
      EmulatorKind.ppsspp,
      'PPSSPP 即时存档',
      'PPSSPP-states',
      '{root}/PSP/PPSSPP_STATE',
      includeAll: true,
    ),
    _Candidate(
      EmulatorKind.ppsspp,
      'PPSSPP 存档',
      'PPSSPP-SAVEDATA',
      '{root}/Android/data/org.ppsspp.ppsspp/files/PSP/SAVEDATA',
      includeAll: true,
    ),
    // Citra：优先只同步 3DS 标题数据，避免把整个 sdmc 都传上去。
    _Candidate(
      EmulatorKind.citra,
      'Citra 存档',
      'Citra-Nintendo3DS',
      '{root}/citra-emu/sdmc/Nintendo 3DS',
      includeAll: true,
    ),
    _Candidate(
      EmulatorKind.citra,
      'Citra 存档',
      'Citra-sdmc',
      '{root}/citra-emu/sdmc',
      includeAll: true,
    ),
    // Azahar（Citra 继任者）：新版目录名为 azahar-emu。
    _Candidate(
      EmulatorKind.azahar,
      'Azahar 存档',
      'Azahar-Nintendo3DS',
      '{root}/azahar-emu/sdmc/Nintendo 3DS',
      includeAll: true,
    ),
    _Candidate(
      EmulatorKind.azahar,
      'Azahar 存档',
      'Azahar-sdmc',
      '{root}/azahar-emu/sdmc',
      includeAll: true,
    ),
    _Candidate(
      EmulatorKind.azahar,
      'Azahar 存档',
      'Azahar-sdmc',
      '{root}/Android/data/org.azahar_emu.azahar/files/sdmc',
      includeAll: true,
    ),
    // PCSX2（Android）：记忆卡与即时存档。
    _Candidate(
      EmulatorKind.pcsx2,
      'PCSX2 记忆卡',
      'PCSX2-memcards',
      '{root}/PCSX2/memcards',
      includeAll: true,
    ),
    _Candidate(
      EmulatorKind.pcsx2,
      'PCSX2 即时存档',
      'PCSX2-states',
      '{root}/PCSX2/sstates',
      includeAll: true,
    ),
    _Candidate(
      EmulatorKind.pcsx2,
      'PCSX2 记忆卡',
      'PCSX2-memcards',
      '{root}/Android/data/org.pcsx2/files/memcards',
      includeAll: true,
    ),
    _Candidate(
      EmulatorKind.pcsx2,
      'PCSX2 即时存档',
      'PCSX2-states',
      '{root}/Android/data/org.pcsx2/files/sstates',
      includeAll: true,
    ),
    // AetherSX2：记忆卡与即时存档。
    _Candidate(
      EmulatorKind.aetherSx2,
      'AetherSX2 记忆卡',
      'AetherSX2-memcards',
      '{root}/Android/data/xyz.aethersx2.android/files/memcards',
      includeAll: true,
    ),
    _Candidate(
      EmulatorKind.aetherSx2,
      'AetherSX2 即时存档',
      'AetherSX2-states',
      '{root}/Android/data/xyz.aethersx2.android/files/sstates',
      includeAll: true,
    ),
    _Candidate(
      EmulatorKind.aetherSx2,
      'AetherSX2 记忆卡',
      'AetherSX2-memcards',
      '{root}/AetherSX2/memcards',
      includeAll: true,
    ),
  ];

  /// 手动目录的默认白名单后缀。
  static const List<String> commonExtensions = <String>[
    'sav', 'srm', 'state', 'saveram', 'dsv', 'mcr', 'mcd', 'ps2', 'p2s',
    'bin', 'dat', 'sfo', 'eep', 'fla', 'mpk', 'rtc', 'sra', 'bak', 'ss0',
    'ss1', 'ss2', 'ss3', 'ss4', 'ss5', 'ss6', 'ss7', 'ss8', 'ss9',
  ];

  /// 扫描全部候选路径，返回检测到的存档目录（已去重、去掉嵌套目录）。
  static List<CloudSaveFolder> detect() {
    final found = <CloudSaveFolder>[];
    for (final candidate in _candidates) {
      for (final root in _roots) {
        final path = candidate.pathTemplate.replaceAll('{root}', root);
        if (!_isReadableDirectory(path)) continue;
        // 嵌套的父/子目录只保留先命中的一个，避免重复同步。
        final nested = found.any((folder) =>
            _isNested(folder.localPath, path) ||
            _isNested(path, folder.localPath));
        if (nested) continue;

        found.add(CloudSaveFolder(
          id: folderIdFor(candidate.emulator, path),
          emulatorId: candidate.emulator.id,
          label: candidate.label,
          localPath: path,
          remoteName: candidate.remoteName,
          includeAll: candidate.includeAll,
          extensions: candidate.includeAll
              ? const <String>[]
              : commonExtensions,
        ));
      }
    }
    return found;
  }

  /// 手动添加目录。
  static CloudSaveFolder? fromManualPath(String path) {
    final normalized = p.normalize(path.trim());
    if (!_isReadableDirectory(normalized)) return null;
    final base = p.basename(normalized);
    return CloudSaveFolder(
      id: folderIdFor(EmulatorKind.custom, normalized),
      emulatorId: EmulatorKind.custom.id,
      label: base.isEmpty ? '手动存档目录' : base,
      localPath: normalized,
      remoteName: sanitizeRemoteName(base.isEmpty ? 'Custom-saves' : base),
      includeAll: true,
      extensions: commonExtensions,
    );
  }

  /// 根据路径生成稳定 ID。
  static String folderIdFor(EmulatorKind kind, String path) {
    var hash = 0x811c9dc5;
    for (final code in '${kind.id}:$path'.codeUnits) {
      hash ^= code;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return '${kind.id}-${hash.toRadixString(16).padLeft(8, '0')}';
  }

  /// 云端目录名只保留 ASCII 安全字符，避免 WebDAV 编码差异。
  static String sanitizeRemoteName(String value) {
    var name = value
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '-')
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'-{2,}'), '-')
        .replaceAll(RegExp(r'^[-.]+|[-.]+$'), '');
    final ascii = name
        .codeUnits
        .where((c) => c >= 0x20 && c < 0x7F)
        .map(String.fromCharCode)
        .join();
    name = ascii.isEmpty ? 'Saves' : ascii;
    if (name.length > 48) name = name.substring(0, 48);
    return name;
  }

  /// 判断文件是否属于需要同步的存档。
  static bool matchFile(CloudSaveFolder folder, String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.startsWith('.')) {
      // .nomedia 等标记文件不同步，但允许 .srm 这类隐藏存档。
      if (!_hasSyncedExtension(folder, lower)) return false;
    }
    if (lower.endsWith('.tmp') ||
        lower.endsWith('.part') ||
        lower.endsWith('.crdownload') ||
        lower.endsWith('.log') ||
        lower == 'thumbs.db' ||
        lower == 'desktop.ini') {
      return false;
    }
    if (folder.includeAll) return true;
    final dot = lower.lastIndexOf('.');
    if (dot < 0 || dot == lower.length - 1) return false;
    final ext = lower.substring(dot + 1);
    return folder.extensions
        .map((e) => e.toLowerCase().replaceFirst('.', ''))
        .contains(ext);
  }

  static bool _hasSyncedExtension(CloudSaveFolder folder, String lowerName) {
    final dot = lowerName.lastIndexOf('.');
    if (dot < 0) return false;
    final ext = lowerName.substring(dot + 1);
    return folder.extensions
        .map((e) => e.toLowerCase().replaceFirst('.', ''))
        .contains(ext);
  }

  /// 递归统计目录内待同步文件数量，供 UI 展示；超过 [limit] 时提前结束。
  static Future<int> countFiles(CloudSaveFolder folder,
      {int limit = 2000}) async {
    final dir = Directory(folder.localPath);
    if (!await dir.exists()) return 0;
    var count = 0;
    try {
      await for (final entity in dir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        if (!matchFile(folder, p.basename(entity.path))) continue;
        count++;
        if (count >= limit) break;
      }
    } catch (_) {
      // 权限不足时按 0 处理。
    }
    return count;
  }

  /// 递归统计目录总大小。
  static Future<int> folderSize(CloudSaveFolder folder, {int limit = 2000}) async {
    final dir = Directory(folder.localPath);
    if (!await dir.exists()) return 0;
    var size = 0;
    var count = 0;
    try {
      await for (final entity in dir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        if (!matchFile(folder, p.basename(entity.path))) continue;
        try {
          size += await entity.length();
        } catch (_) {}
        count++;
        if (count >= limit) break;
      }
    } catch (_) {}
    return size;
  }

  static bool _isReadableDirectory(String path) {
    try {
      final dir = Directory(path);
      if (!dir.existsSync()) return false;
      dir.listSync(recursive: false).take(1).toList();
      return true;
    } catch (_) {
      return false;
    }
  }

  static bool _isNested(String parent, String child) {
    final normalizedParent = p.normalize(parent);
    final normalizedChild = p.normalize(child);
    return normalizedChild.startsWith('$normalizedParent/');
  }

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }
}

class _Candidate {
  final EmulatorKind emulator;
  final String label;
  final String remoteName;
  final String pathTemplate;
  final bool includeAll;

  const _Candidate(
    this.emulator,
    this.label,
    this.remoteName,
    this.pathTemplate, {
    this.includeAll = false,
  });
}