import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/cloud_save.dart';
import 'emulator_save_service.dart';
import 'preferences_service.dart';
import 'webdav_service.dart';

/// 云存档同步引擎（参考 retro-save-sync 的双向时间戳同步逻辑）。
///
/// - 以本地/云端修改时间与上次同步快照判断哪一端发生了变化；
/// - 两端都变化时按冲突策略处理（保留本地/云端/两者都保留）；
/// - 下载覆盖本地前自动备份到应用文档目录，并按份数清理；
/// - 支持双向、仅上传、仅下载，支持启动时自动同步与单目录手动同步。
class CloudSaveService extends ChangeNotifier {
  CloudSaveService._();

  static final CloudSaveService instance = CloudSaveService._();

  static const int _timeToleranceMs = 3000;
  static const int _maxFilesPerFolder = 2000;
  static const int _maxLogEntries = 400;

  final List<CloudSyncLog> _logs = <CloudSyncLog>[];

  bool _running = false;
  int _total = 0;
  int _completed = 0;
  int _uploaded = 0;
  int _downloaded = 0;
  int _conflicts = 0;
  int _failed = 0;
  String _message = '';
  String _currentFile = '';

  /// 当前同步过程的备份批次。
  _BackupBatch _batch = _BackupBatch();

  Map<String, Map<String, CloudFileSnapshot>> _snapshots =
      <String, Map<String, CloudFileSnapshot>>{};

  bool get running => _running;

  List<CloudSyncLog> get logs => List<CloudSyncLog>.unmodifiable(_logs);

  CloudSyncStatus get status => CloudSyncStatus(
        running: _running,
        total: _total,
        completed: _completed,
        uploaded: _uploaded,
        downloaded: _downloaded,
        conflicts: _conflicts,
        failed: _failed,
        message: _message,
        currentFile: _currentFile,
        logs: logs,
      );

  /// 校验 WebDAV 配置是否完整。
  static Future<String?> validateConfig() async {
    final url = (await PreferencesService.webdavUrl).trim();
    final user = (await PreferencesService.webdavUsername).trim();
    final password = await PreferencesService.webdavPassword;
    if (url.isEmpty) return '请先填写 WebDAV 服务器地址';
    if (user.isEmpty) return '请先填写 WebDAV 账号';
    if (password.isEmpty) return '请先填写 WebDAV 密码';
    return null;
  }

  static Future<WebDavService> createClient() async {
    return WebDavService(
      baseUrl: await PreferencesService.webdavUrl,
      username: (await PreferencesService.webdavUsername).trim(),
      password: await PreferencesService.webdavPassword,
      remoteRoot: await PreferencesService.webdavRoot,
    );
  }

  Future<bool> testConnection({
    required String url,
    required String username,
    required String password,
    required String root,
  }) async {
    final client = WebDavService(
      baseUrl: url,
      username: username,
      password: password,
      remoteRoot: root,
    );
    try {
      return await client.testConnection();
    } finally {
      client.close();
    }
  }

  /// 启动时按设置自动同步；未启用或未配置时返回 null。
  Future<CloudSyncStatus?> autoSyncOnStart() async {
    if (!await PreferencesService.cloudSaveAutoSync) return null;
    if (await validateConfig() != null) return null;
    final folders = await PreferencesService.cloudSaveFolders;
    if (!folders.any((f) => f.enabled)) return null;
    return syncAll(mode: SyncMode.bidirectional);
  }

  /// 同步全部启用的目录。
  Future<CloudSyncStatus> syncAll({
    SyncMode mode = SyncMode.bidirectional,
  }) async {
    if (_running) return status;

    final configError = await validateConfig();
    if (configError != null) {
      return _failFast(configError);
    }
    final folders = await PreferencesService.cloudSaveFolders;
    final enabled = folders.where((f) => f.enabled).toList();
    if (enabled.isEmpty) {
      return _failFast('还没有配置任何存档目录');
    }

    _running = true;
    _total = 0;
    _completed = 0;
    _uploaded = 0;
    _downloaded = 0;
    _conflicts = 0;
    _failed = 0;
    _logs.clear();
    _message = '准备同步 ${enabled.length} 个目录';
    _currentFile = '';
    notifyListeners();

    await _loadSnapshots();
    final policy = await _loadConflictPolicy();

    WebDavService? client;
    try {
      client = await createClient();
      for (final folder in enabled) {
        _message = '正在同步「${folder.label}」';
        _currentFile = '';
        notifyListeners();
        await _syncOne(client, folder, mode, policy);
      }
      _message = _summary('同步完成');
    } catch (e) {
      _message = '同步失败：${_friendlyError(e)}';
      _log(_message, failed: true);
    } finally {
      client?.close();
      _running = false;
      _currentFile = '';
      notifyListeners();
    }
    return status;
  }

  /// 同步指定目录（手动触发）。
  Future<CloudSyncStatus> syncFolder(
    CloudSaveFolder folder, {
    SyncMode mode = SyncMode.bidirectional,
  }) async {
    if (_running) return status;

    final configError = await validateConfig();
    if (configError != null) return _failFast(configError);

    _running = true;
    _total = 0;
    _completed = 0;
    _uploaded = 0;
    _downloaded = 0;
    _conflicts = 0;
    _failed = 0;
    _logs.clear();
    _message = '正在同步「${folder.label}」';
    _currentFile = '';
    notifyListeners();

    await _loadSnapshots();
    final policy = await _loadConflictPolicy();

    WebDavService? client;
    try {
      client = await createClient();
      await _syncOne(client, folder, mode, policy);
      _message = _summary('「${folder.label}」同步完成');
    } catch (e) {
      _message = '同步失败：${_friendlyError(e)}';
      _log(_message, failed: true);
    } finally {
      client?.close();
      _running = false;
      _currentFile = '';
      notifyListeners();
    }
    return status;
  }

  // ---------------------------------------------------------------------------
  // 单目录同步
  // ---------------------------------------------------------------------------

  Future<void> _syncOne(
    WebDavService client,
    CloudSaveFolder folder,
    SyncMode mode,
    ConflictPolicy policy,
  ) async {
    final root = folder.localPath;
    final localDir = Directory(root);
    if (!localDir.existsSync()) {
      _failed++;
      _log('目录不存在：$root', failed: true);
      await _persistFolderResult(folder, '目录不存在');
      return;
    }

    final remoteBase = client.folderPath(folder.remoteName);
    try {
      await client.ensureDirectory(remoteBase);
    } on WebDavException catch (e) {
      _failed++;
      _log('创建云端目录失败：${e.message}', failed: true);
      return;
    }

    final localFiles = await _scanLocal(folder);
    Map<String, WebDavEntry> remoteFiles;
    try {
      remoteFiles = <String, WebDavEntry>{};
      await _scanRemote(client, remoteBase, '', remoteFiles, 0);
    } on WebDavException catch (e) {
      // 目录刚创建时部分服务端 PROPFIND 会短暂 404，按空目录处理。
      if (e.message.contains('404')) {
        remoteFiles = <String, WebDavEntry>{};
      } else {
        _failed++;
        _log('读取云端目录失败：${e.message}', failed: true);
        return;
      }
    }

    final relativePaths = <String>{
      ...localFiles.keys,
      ...remoteFiles.keys,
    }.toList()
      ..sort();

    _total = relativePaths.length;
    _completed = 0;
    notifyListeners();
    _log('「${folder.label}」发现 ${localFiles.length} 个本地文件、'
        '${remoteFiles.length} 个云端文件');

    final createdRemoteDirs = <String>{};
    _batch = _BackupBatch();

    for (final relative in relativePaths) {
      if (_completed >= _maxFilesPerFolder) {
        _log('文件数量超过 $_maxFilesPerFolder，剩余文件已跳过', failed: true);
        break;
      }
      final local = localFiles[relative];
      final remote = remoteFiles[relative];
      final snapshot = _snapshots[folder.id]?[relative];

      _currentFile = relative;
      notifyListeners();

      try {
        await _syncFile(
          client: client,
          folder: folder,
          relative: relative,
          remoteBase: remoteBase,
          local: local,
          remote: remote,
          snapshot: snapshot,
          mode: mode,
          policy: policy,
          createdRemoteDirs: createdRemoteDirs,
        );
      } catch (e) {
        _failed++;
        _log('$relative：${_friendlyError(e)}', failed: true);
      }

      _completed++;
      notifyListeners();
    }

    if (_batch.dirPath != null) {
      await _trimBackups(folder.id);
    }
    await _reconcileSnapshots(client, folder, remoteBase);
    await _saveSnapshots();
    await _persistFolderResult(
      folder,
      '上传 $_uploaded · 下载 $_downloaded · 冲突 $_conflicts · 失败 $_failed',
    );

    _currentFile = '';
    notifyListeners();
  }

  Future<void> _syncFile({
    required WebDavService client,
    required CloudSaveFolder folder,
    required String relative,
    required String remoteBase,
    required _LocalFile? local,
    required WebDavEntry? remote,
    required CloudFileSnapshot? snapshot,
    required SyncMode mode,
    required ConflictPolicy policy,
    required Set<String> createdRemoteDirs,
  }) async {
    if (local == null && remote != null) {
      if (mode == SyncMode.upload) return;
      await _download(
          client: client, folder: folder, relative: relative, remote: remote);
      return;
    }

    if (local != null && remote == null) {
      if (mode == SyncMode.download) return;
      await _upload(
        client: client,
        folder: folder,
        relative: relative,
        remoteBase: remoteBase,
        local: local,
        createdRemoteDirs: createdRemoteDirs,
      );
      return;
    }

    if (local == null || remote == null) return;

    final localChanged = _changed(
      snapshot?.localMs,
      local.modifiedMs,
      snapshot?.size,
      local.size,
    );
    final remoteChanged = _changed(
      snapshot?.remoteMs,
      remote.modifiedMs,
      snapshot?.size,
      remote.size,
    );

    if (snapshot == null) {
      // 没有快照时按文件大小与修改时间判断，大小相同且时间接近视为一致。
      if (local.size == remote.size &&
          _timeClose(local.modifiedMs, remote.modifiedMs)) {
        return;
      }
      final useLocal = local.modifiedMs >= (remote.modifiedMs ?? 0);
      if (useLocal) {
        if (mode == SyncMode.download) return;
        await _upload(
          client: client,
          folder: folder,
          relative: relative,
          remoteBase: remoteBase,
          local: local,
          createdRemoteDirs: createdRemoteDirs,
        );
      } else {
        if (mode == SyncMode.upload) return;
        await _download(
            client: client, folder: folder, relative: relative, remote: remote);
      }
      return;
    }

    if (localChanged && remoteChanged) {
      _conflicts++;
      _log('$relative：本地与云端均已修改', failed: true);
      switch (policy) {
        case ConflictPolicy.preferLocal:
          if (mode == SyncMode.download) return;
          await _upload(
            client: client,
            folder: folder,
            relative: relative,
            remoteBase: remoteBase,
            local: local,
            createdRemoteDirs: createdRemoteDirs,
          );
          break;
        case ConflictPolicy.preferRemote:
          if (mode == SyncMode.upload) return;
          await _download(
              client: client,
              folder: folder,
              relative: relative,
              remote: remote);
          break;
        case ConflictPolicy.keepBoth:
          if (mode == SyncMode.download) {
            await _download(
                client: client,
                folder: folder,
                relative: relative,
                remote: remote);
            break;
          }
          final stamp = _timestamp();
          final conflictPath = _joinRemote(remoteBase, relative);
          final backupRemote = '$conflictPath.conflict-$stamp';
          try {
            await client.move(conflictPath, backupRemote);
            _log('$relative：云端旧版本已保留为 .conflict-$stamp');
          } catch (_) {
            // 部分服务不支持 MOVE 时退化为直接覆盖。
          }
          await _upload(
            client: client,
            folder: folder,
            relative: relative,
            remoteBase: remoteBase,
            local: local,
            createdRemoteDirs: createdRemoteDirs,
          );
          break;
      }
      return;
    }

    if (localChanged) {
      if (mode == SyncMode.download) return;
      await _upload(
        client: client,
        folder: folder,
        relative: relative,
        remoteBase: remoteBase,
        local: local,
        createdRemoteDirs: createdRemoteDirs,
      );
      return;
    }

    if (remoteChanged) {
      if (mode == SyncMode.upload) return;
      await _download(
          client: client, folder: folder, relative: relative, remote: remote);
      return;
    }
  }

  Future<void> _upload({
    required WebDavService client,
    required CloudSaveFolder folder,
    required String relative,
    required String remoteBase,
    required _LocalFile local,
    required Set<String> createdRemoteDirs,
  }) async {
    final dir = p.url.dirname(relative);
    if (dir != '.' && dir.isNotEmpty) {
      final key = '$remoteBase/$dir';
      if (!createdRemoteDirs.contains(key)) {
        await client.ensureDirectory(key);
        createdRemoteDirs.add(key);
      }
    }
    await client.upload(_joinRemote(remoteBase, relative), local.file);
    _uploaded++;
    _log('↑ $relative');
  }

  Future<void> _download({
    required WebDavService client,
    required CloudSaveFolder folder,
    required String relative,
    required WebDavEntry remote,
  }) async {
    final localPath = p.joinAll(<String>[folder.localPath, ...relative.split('/')]);
    final file = File(localPath);
    if (await file.exists()) {
      await _backupLocal(folder, relative, file, _batch);
    }
    await file.parent.create(recursive: true);
    final bytes = await client.download(
        _joinRemote(client.folderPath(folder.remoteName), relative));
    await file.writeAsBytes(bytes, flush: true);
    if (remote.modified != null) {
      try {
        await file.setLastModified(remote.modified!);
      } catch (_) {
        // 部分文件系统不支持修改时间，忽略即可。
      }
    }
    _downloaded++;
    _log('↓ $relative');
  }

  // ---------------------------------------------------------------------------
  // 快照 / 扫描
  // ---------------------------------------------------------------------------

  Future<Map<String, _LocalFile>> _scanLocal(CloudSaveFolder folder) async {
    final result = <String, _LocalFile>{};
    final dir = Directory(folder.localPath);
    try {
      await for (final entity in dir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (!EmulatorSaveService.matchFile(folder, name)) continue;
        final relative =
            p.relative(entity.path, from: folder.localPath).replaceAll('\\', '/');
        try {
          final stat = await entity.stat();
          result[relative] = _LocalFile(
            file: entity,
            modifiedMs: stat.modified.millisecondsSinceEpoch,
            size: stat.size,
          );
        } catch (_) {}
        if (result.length >= _maxFilesPerFolder) break;
      }
    } catch (e) {
      _log('读取本地目录失败：${_friendlyError(e)}', failed: true);
    }
    return result;
  }

  Future<void> _scanRemote(
    WebDavService client,
    String remoteBase,
    String prefix,
    Map<String, WebDavEntry> out,
    int depth,
  ) async {
    if (depth > 12) return;
    final path = prefix.isEmpty ? remoteBase : '$remoteBase/$prefix';
    final entries = await client.list(path);
    for (final entry in entries) {
      final relative = prefix.isEmpty ? entry.name : '$prefix/${entry.name}';
      if (entry.isDirectory) {
        await _scanRemote(client, remoteBase, relative, out, depth + 1);
      } else {
        out[relative] = entry;
      }
      if (out.length >= _maxFilesPerFolder) return;
    }
  }

  Future<void> _reconcileSnapshots(
    WebDavService client,
    CloudSaveFolder folder,
    String remoteBase,
  ) async {
    // 重新读取两端，记录服务端实际写入的 Last-Modified，避免下次误判。
    final localFiles = await _scanLocal(folder);
    Map<String, WebDavEntry> remoteFiles;
    try {
      remoteFiles = <String, WebDavEntry>{};
      await _scanRemote(client, remoteBase, '', remoteFiles, 0);
    } catch (_) {
      return;
    }

    final snaps = <String, CloudFileSnapshot>{};
    for (final entry in localFiles.entries) {
      final remote = remoteFiles[entry.key];
      if (remote == null) continue;
      // 仅在两端的文件大小一致时才记录，避免把失败的上传/下载误标为已同步。
      if (remote.size != 0 && remote.size != entry.value.size) continue;
      snaps[entry.key] = CloudFileSnapshot(
        localMs: entry.value.modifiedMs,
        remoteMs: remote.modifiedMs ?? entry.value.modifiedMs,
        size: entry.value.size,
      );
    }
    _snapshots[folder.id] = snaps;
  }

  Future<void> _loadSnapshots() async {
    final raw = await PreferencesService.cloudSaveSnapshots;
    final result = <String, Map<String, CloudFileSnapshot>>{};
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          decoded.forEach((folderId, value) {
            if (value is! Map) return;
            final files = <String, CloudFileSnapshot>{};
            value.forEach((relative, snapshot) {
              if (snapshot is Map) {
                files[relative.toString()] = CloudFileSnapshot.fromJson(
                  Map<String, dynamic>.from(snapshot),
                );
              }
            });
            result[folderId.toString()] = files;
          });
        }
      } catch (_) {
        // 损坏的快照直接丢弃，下次按修改时间重新判断。
      }
    }
    _snapshots = result;
  }

  Future<void> _saveSnapshots() async {
    final data = <String, Map<String, Map<String, dynamic>>>{};
    _snapshots.forEach((folderId, files) {
      data[folderId] = files.map((relative, snapshot) =>
          MapEntry(relative, snapshot.toJson()));
    });
    await PreferencesService.setCloudSaveSnapshots(jsonEncode(data));
  }

  /// 清空某个目录的同步快照（移除目录后不再保留其对比基线）。
  Future<void> forgetFolder(String folderId) async {
    await _loadSnapshots();
    if (_snapshots.remove(folderId) == null) return;
    await _saveSnapshots();
  }

  Future<ConflictPolicy> _loadConflictPolicy() async {
    final raw = await PreferencesService.cloudSaveConflictPolicy;
    return ConflictPolicy.values.firstWhere(
      (policy) => policy.name == raw,
      orElse: () => ConflictPolicy.keepBoth,
    );
  }

  Future<void> _persistFolderResult(
    CloudSaveFolder folder,
    String result,
  ) async {
    final folders = await PreferencesService.cloudSaveFolders;
    final index = folders.indexWhere((f) => f.id == folder.id);
    if (index < 0) return;
    folders[index] = folders[index].copyWith(
      lastSyncMs: DateTime.now().millisecondsSinceEpoch,
      lastResult: result,
    );
    await PreferencesService.setCloudSaveFolders(folders);
  }

  /// 覆盖本地文件前备份到应用文档目录；同一次同步共用一个时间戳批次目录，
  /// 批次清理在同步结束时统一进行。
  Future<void> _backupLocal(
    CloudSaveFolder folder,
    String relative,
    File file,
    _BackupBatch batch,
  ) async {
    try {
      if (batch.dirPath == null) {
        final documents = await getApplicationDocumentsDirectory();
        final stamp = DateTime.now()
            .toIso8601String()
            .replaceAll(':', '-')
            .replaceAll('.', '-');
        final base = Directory(p.join(
          documents.path,
          'cloud_save_backups',
          folder.id,
          stamp,
        ));
        await base.create(recursive: true);
        batch.dirPath = base.path;
      }
      final target = File(
          p.joinAll(<String>[batch.dirPath!, ...relative.split('/')]));
      await target.parent.create(recursive: true);
      await file.copy(target.path);
      _log('已备份本地 $relative');
    } catch (e) {
      _log('备份失败：${_friendlyError(e)}', failed: true);
    }
  }

  Future<void> _trimBackups(String folderId) async {
    try {
      final max = await PreferencesService.cloudSaveMaxBackups;
      if (max <= 0) return;
      final documents = await getApplicationDocumentsDirectory();
      final dir = Directory(
          p.join(documents.path, 'cloud_save_backups', folderId));
      if (!await dir.exists()) return;
      final batches = await dir
          .list(followLinks: false)
          .where((e) => e is Directory)
          .cast<Directory>()
          .toList();
      batches.sort((a, b) => b.path.compareTo(a.path));
      for (var i = max; i < batches.length; i++) {
        try {
          await batches[i].delete(recursive: true);
        } catch (_) {}
      }
    } catch (_) {}
  }

  /// 列出某个目录的本地备份（时间倒序，最新在前）。
  Future<List<Directory>> listBackups(CloudSaveFolder folder) async {
    try {
      final documents = await getApplicationDocumentsDirectory();
      final dir = Directory(
          p.join(documents.path, 'cloud_save_backups', folder.id));
      if (!await dir.exists()) return <Directory>[];
      final batches = await dir
          .list(followLinks: false)
          .where((e) => e is Directory)
          .cast<Directory>()
          .toList();
      batches.sort((a, b) => b.path.compareTo(a.path));
      return batches;
    } catch (_) {
      return <Directory>[];
    }
  }

  /// 把某次备份中的文件恢复到目录（覆盖前会再备份当前文件）。
  Future<int> restoreBackup(
    CloudSaveFolder folder,
    Directory backup,
  ) async {
    var count = 0;
    final batch = _BackupBatch();
    try {
      await for (final entity in backup.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        final relative = p.relative(entity.path, from: backup.path);
        final target =
            File(p.joinAll(<String>[folder.localPath, ...relative.split(p.separator)]));
        if (await target.exists()) {
          await _backupLocal(folder, relative, target, batch);
        }
        await target.parent.create(recursive: true);
        await entity.copy(target.path);
        count++;
      }
      if (batch.dirPath != null) await _trimBackups(folder.id);
      _log('已从备份恢复 $count 个文件到「${folder.label}」');
      notifyListeners();
    } catch (e) {
      _log('恢复备份失败：${_friendlyError(e)}', failed: true);
    }
    return count;
  }

  // ---------------------------------------------------------------------------
  // 工具
  // ---------------------------------------------------------------------------

  static bool _changed(
    int? snapshotMs,
    int? currentMs,
    int? snapshotSize,
    int currentSize,
  ) {
    if (snapshotMs == null || currentMs == null) return true;
    if ((currentMs - snapshotMs).abs() > _timeToleranceMs) return true;
    if (snapshotSize != null && snapshotSize != currentSize) return true;
    return false;
  }

  static bool _timeClose(int a, int? b) {
    if (b == null) return false;
    return (a - b).abs() <= _timeToleranceMs;
  }

  static String _joinRemote(String base, String relative) {
    final joined = '$base/${relative.replaceAll('\\', '/')}';
    return joined.replaceAll(RegExp(r'/+'), '/');
  }

  static String _timestamp() {
    final now = DateTime.now();
    final date = '${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}';
    final time = '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';
    return '$date-$time';
  }

  String _summary(String prefix) {
    return '$prefix：↑$_uploaded ↓$_downloaded 冲突$_conflicts 失败$_failed';
  }

  String _friendlyError(Object error) {
    if (error is WebDavException) return error.message;
    if (error is FileSystemException) {
      return '文件操作失败：${error.message}';
    }
    final text = error.toString();
    return text.startsWith('Exception: ') ? text.substring(11) : text;
  }

  void _log(String message, {bool failed = false}) {
    _logs.add(CloudSyncLog(message, failed: failed));
    if (_logs.length > _maxLogEntries) {
      _logs.removeRange(0, _logs.length - _maxLogEntries);
    }
    if (_running) notifyListeners();
  }

  CloudSyncStatus _failFast(String message) {
    _running = false;
    _total = 0;
    _completed = 0;
    _uploaded = 0;
    _downloaded = 0;
    _conflicts = 0;
    _failed = 1;
    _message = message;
    _currentFile = '';
    _logs.clear();
    _logs.add(CloudSyncLog(message, failed: true));
    notifyListeners();
    return status;
  }
}

class _LocalFile {
  final File file;
  final int modifiedMs;
  final int size;

  const _LocalFile({
    required this.file,
    required this.modifiedMs,
    required this.size,
  });
}

/// 一次同步的备份批次：同一次同步中被覆盖的本地文件共享一个时间戳目录。
class _BackupBatch {
  String? dirPath;
}