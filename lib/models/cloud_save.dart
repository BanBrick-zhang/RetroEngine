import 'dart:convert';

/// 支持自动识别存档目录的复古模拟器。
enum EmulatorKind {
  retroArch('retroarch', 'RetroArch'),
  ppsspp('ppsspp', 'PPSSPP'),
  citra('citra', 'Citra'),
  azahar('azahar', 'Azahar'),
  pcsx2('pcsx2', 'PCSX2'),
  aetherSx2('aethersx2', 'AetherSX2'),
  custom('custom', '自定义目录');

  final String id;
  final String label;

  const EmulatorKind(this.id, this.label);

  static EmulatorKind fromId(String? id) => values.firstWhere(
        (kind) => kind.id == id,
        orElse: () => EmulatorKind.custom,
      );
}

/// 同步方向。
enum SyncMode {
  bidirectional('双向同步'),
  upload('仅上传'),
  download('仅下载');

  final String label;
  const SyncMode(this.label);
}

/// 双边都修改时的冲突处理策略。
enum ConflictPolicy {
  preferLocal('保留本地'),
  preferRemote('保留云端'),
  keepBoth('两者都保留');

  final String label;
  const ConflictPolicy(this.label);
}

/// 一个参与云同步的本地存档目录。
class CloudSaveFolder {
  final String id;

  /// [EmulatorKind.id]，自定义目录为 `custom`。
  final String emulatorId;

  /// 展示名称。
  final String label;

  /// 本地绝对路径。
  final String localPath;

  /// 云端根目录下的子目录名。
  final String remoteName;

  /// 是否同步目录下的全部文件（适用于 PPSSPP、Citra 等无扩展名的存档）。
  final bool includeAll;

  /// 后缀白名单（不含点，小写）。[includeAll] 为 true 时忽略。
  final List<String> extensions;

  final bool enabled;

  /// 最近一次同步完成时间（毫秒时间戳）。
  final int? lastSyncMs;

  /// 最近一次同步结果摘要。
  final String? lastResult;

  const CloudSaveFolder({
    required this.id,
    required this.emulatorId,
    required this.label,
    required this.localPath,
    required this.remoteName,
    this.includeAll = false,
    this.extensions = const <String>['sav', 'srm', 'state', 'saveram', 'dsv'],
    this.enabled = true,
    this.lastSyncMs,
    this.lastResult,
  });

  EmulatorKind get emulator => EmulatorKind.fromId(emulatorId);

  CloudSaveFolder copyWith({
    String? emulatorId,
    String? label,
    String? localPath,
    String? remoteName,
    bool? includeAll,
    List<String>? extensions,
    bool? enabled,
    int? lastSyncMs,
    String? lastResult,
  }) {
    return CloudSaveFolder(
      id: id,
      emulatorId: emulatorId ?? this.emulatorId,
      label: label ?? this.label,
      localPath: localPath ?? this.localPath,
      remoteName: remoteName ?? this.remoteName,
      includeAll: includeAll ?? this.includeAll,
      extensions: extensions ?? this.extensions,
      enabled: enabled ?? this.enabled,
      lastSyncMs: lastSyncMs ?? this.lastSyncMs,
      lastResult: lastResult ?? this.lastResult,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'emulator': emulatorId,
        'label': label,
        'localPath': localPath,
        'remoteName': remoteName,
        'includeAll': includeAll,
        'extensions': extensions,
        'enabled': enabled,
        'lastSyncMs': lastSyncMs,
        'lastResult': lastResult,
      };

  static CloudSaveFolder? fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString();
    final localPath = json['localPath']?.toString();
    if (id == null || id.isEmpty || localPath == null || localPath.isEmpty) {
      return null;
    }
    final extensions = (json['extensions'] as List<dynamic>?)
            ?.map((e) => e.toString().toLowerCase().replaceFirst('.', ''))
            .where((e) => e.isNotEmpty)
            .toList() ??
        const <String>[];
    return CloudSaveFolder(
      id: id,
      emulatorId: json['emulator']?.toString() ?? EmulatorKind.custom.id,
      label: json['label']?.toString() ?? '',
      localPath: localPath,
      remoteName: json['remoteName']?.toString() ?? '',
      includeAll: json['includeAll'] as bool? ?? false,
      extensions: extensions,
      enabled: json['enabled'] as bool? ?? true,
      lastSyncMs: int.tryParse(json['lastSyncMs']?.toString() ?? ''),
      lastResult: json['lastResult']?.toString(),
    );
  }
}

/// 某次同步中单个文件在两端的时间戳快照。
class CloudFileSnapshot {
  final int localMs;
  final int remoteMs;
  final int size;

  const CloudFileSnapshot({
    required this.localMs,
    required this.remoteMs,
    this.size = 0,
  });

  Map<String, dynamic> toJson() =>
      <String, dynamic>{'l': localMs, 'r': remoteMs, 's': size};

  static CloudFileSnapshot fromJson(Map<String, dynamic> json) {
    return CloudFileSnapshot(
      localMs: int.tryParse(json['l']?.toString() ?? '') ?? 0,
      remoteMs: int.tryParse(json['r']?.toString() ?? '') ?? 0,
      size: int.tryParse(json['s']?.toString() ?? '') ?? 0,
    );
  }
}

/// 一条同步日志。
class CloudSyncLog {
  final DateTime time;
  final String message;
  final bool failed;

  CloudSyncLog(this.message, {this.failed = false, DateTime? time})
      : time = time ?? DateTime.now();

  String get timeLabel {
    final t = time;
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    final ss = t.second.toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }
}

/// 同步进度快照。
class CloudSyncStatus {
  final bool running;
  final int total;
  final int completed;
  final int uploaded;
  final int downloaded;
  final int conflicts;
  final int failed;
  final String message;
  final String currentFile;
  final List<CloudSyncLog> logs;

  const CloudSyncStatus({
    this.running = false,
    this.total = 0,
    this.completed = 0,
    this.uploaded = 0,
    this.downloaded = 0,
    this.conflicts = 0,
    this.failed = 0,
    this.message = '',
    this.currentFile = '',
    this.logs = const <CloudSyncLog>[],
  });

  double get progress => total == 0 ? 0 : completed / total;

  bool get hasResult => total > 0;
}

/// 把目录列表编码为偏好存储中的 JSON 字符串。
String encodeFolders(List<CloudSaveFolder> folders) =>
    jsonEncode(folders.map((f) => f.toJson()).toList());

/// 从偏好存储读取目录列表，损坏数据自动跳过。
List<CloudSaveFolder> decodeFolders(String? raw) {
  if (raw == null || raw.isEmpty) return <CloudSaveFolder>[];
  try {
    final list = jsonDecode(raw);
    if (list is! List) return <CloudSaveFolder>[];
    return list
        .whereType<Map<String, dynamic>>()
        .map(CloudSaveFolder.fromJson)
        .whereType<CloudSaveFolder>()
        .toList();
  } catch (_) {
    return <CloudSaveFolder>[];
  }
}