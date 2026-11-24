import 'package:flutter/material.dart';

import '../services/library_service.dart';
import '../theme.dart';

/// 权限引导结果。
enum DirectoryAccessOutcome {
  granted, // 已可正常读写
  awaitingSettings, // 已跳转系统设置，返回后由生命周期监听自动重检
  cancelled, // 用户取消
}

/// 打开文件/目录浏览器前的存储权限检查结果。
enum StorageAccessPrompt {
  granted, // 已具备权限
  openedSettings, // 已跳转系统设置，调用方应在返回后自动继续
  cancelled, // 用户取消
}

/// 浏览共享存储前确保具备“所有文件访问权限”。
///
/// Android 11+ 缺少该权限时，应用内文件浏览器通常无法列出共享存储，
/// 因此在打开浏览器之前先引导授权。用户从系统设置返回后由调用方自动继续。
///
/// [isMounted] 由调用方 State 提供，兼容 Flutter 3.0（无 context.mounted）。
Future<StorageAccessPrompt> ensureStorageAccessPrompt(
  BuildContext context, {
  required bool Function() isMounted,
}) async {
  if (await LibraryService.hasStorageAccess()) {
    return StorageAccessPrompt.granted;
  }
  if (!isMounted()) return StorageAccessPrompt.cancelled;

  final open = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: AppTheme.surface,
      title: Row(
        children: const [
          Icon(Icons.folder_off_outlined, color: AppTheme.warning),
          SizedBox(width: 10),
          Text('需要文件访问权限',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 17)),
        ],
      ),
      content: const Text(
        '浏览和读取游戏库需要“所有文件访问权限”。\n'
        '开启后返回应用会自动继续，无需重新点击。',
        style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.6),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('打开权限设置'),
        ),
      ],
    ),
  );

  if (!isMounted()) return StorageAccessPrompt.cancelled;
  if (open == true) {
    await LibraryService.requestManageStorageSettings();
    return StorageAccessPrompt.openedSettings;
  }
  return StorageAccessPrompt.cancelled;
}

/// 绑定目录后的权限验证与授权引导。
///
/// [isMounted] 由调用方 State 提供，兼容 Flutter 3.0（无 context.mounted）。
/// 注意：调用方应在调用本函数**之前**就把目录路径持久化，这样用户从系统
/// 设置返回后无需重新选择，应用会自动重检权限并读取游戏库。
Future<DirectoryAccessOutcome> ensureDirectoryAccess(
  BuildContext context,
  String path, {
  required bool Function() isMounted,
}) async {
  var result = await LibraryService.verifyDirectoryAccess(path);
  if (result.ok) return DirectoryAccessOutcome.granted;
  if (!isMounted()) return DirectoryAccessOutcome.cancelled;

  final action = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: AppTheme.surface,
      title: Row(
        children: const [
          Icon(Icons.lock_outline, color: AppTheme.warning),
          SizedBox(width: 10),
          Text('需要目录访问权限',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 17)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '应用无法读取所选目录，因此看不到 ROM 和 savedeck.toml。请授予“所有文件访问权限”：',
              style: TextStyle(
                  color: AppTheme.textSecondary, fontSize: 13, height: 1.6)),
            const SizedBox(height: 12),
            _statusRow('目录可访问', result.exists),
            _statusRow('可读取', result.canRead),
            _statusRow('可写入', result.canWrite),
            _statusRow('所有文件访问权限', result.manageGranted ?? false),
            const SizedBox(height: 12),
            const Text(
              '点「打开权限设置」会直达该权限页面（Android 11 及以上位于'
              '「特殊应用权限 → 所有文件访问权限」）。开启开关后直接返回本应用即可，'
              '目录已自动保存，无需再次选择，应用会自动读取游戏库。',
              style: TextStyle(
                  color: AppTheme.textSecondary, fontSize: 12, height: 1.6)),
            const SizedBox(height: 8),
            Text(path,
                style: const TextStyle(
                    color: AppTheme.textPrimary, fontSize: 11)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, 'cancel'),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, 'settings'),
          child: const Text('打开权限设置'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, 'retry'),
          child: const Text('已授权，重新检测'),
        ),
      ],
    ),
  );

  if (action == 'settings') {
    await LibraryService.requestManageStorageSettings();
    return DirectoryAccessOutcome.awaitingSettings;
  }
  if (action == 'retry') {
    final recheck = await LibraryService.verifyDirectoryAccess(path);
    return recheck.ok
        ? DirectoryAccessOutcome.granted
        : DirectoryAccessOutcome.awaitingSettings;
  }
  return DirectoryAccessOutcome.cancelled;
}

Widget _statusRow(String label, bool ok) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Icon(
          ok ? Icons.check_circle : Icons.cancel_outlined,
          size: 16,
          color: ok ? AppTheme.success : AppTheme.danger,
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
        ),
      ],
    ),
  );
}
