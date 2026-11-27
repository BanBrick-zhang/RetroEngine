import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../models/cloud_save.dart';
import '../services/cloud_save_service.dart';
import '../services/emulator_save_service.dart';
import '../services/library_service.dart';
import '../services/preferences_service.dart';
import '../theme.dart';
import '../widgets/app_toast.dart';
import '../widgets/info_dialog.dart';
import 'file_browser_screen.dart';

/// 云存档：WebDAV 配置、模拟器存档目录管理、双向同步与备份恢复。
class CloudSaveScreen extends StatefulWidget {
  const CloudSaveScreen({super.key});

  @override
  State<CloudSaveScreen> createState() => _CloudSaveScreenState();
}

class _CloudSaveScreenState extends State<CloudSaveScreen> {
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _userController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _rootController = TextEditingController();

  final CloudSaveService _service = CloudSaveService.instance;

  List<CloudSaveFolder> _folders = <CloudSaveFolder>[];
  final Map<String, int> _fileCounts = <String, int>{};
  final Map<String, int> _sizes = <String, int>{};

  bool _obscure = true;
  bool _testing = false;
  bool _savingConfig = false;
  bool _detecting = false;
  bool _autoSync = false;
  ConflictPolicy _policy = ConflictPolicy.keepBoth;
  int _maxBackups = 5;
  int _statsToken = 0;
  Timer? _notifyTimer;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onServiceChanged);
    _loadConfig();
    _reloadFolders(refreshStats: true);
  }

  @override
  void dispose() {
    _notifyTimer?.cancel();
    _service.removeListener(_onServiceChanged);
    _urlController.dispose();
    _userController.dispose();
    _passwordController.dispose();
    _rootController.dispose();
    super.dispose();
  }

  void _onServiceChanged() {
    if (!mounted) return;
    if (_notifyTimer?.isActive ?? false) return;
    // 同步时每个文件都会通知一次，限制 UI 刷新频率。
    _notifyTimer = Timer(const Duration(milliseconds: 200), () {
      if (mounted) setState(() {});
    });
  }

  Future<void> _loadConfig() async {
    final url = await PreferencesService.webdavUrl;
    final user = await PreferencesService.webdavUsername;
    final password = await PreferencesService.webdavPassword;
    final root = await PreferencesService.webdavRoot;
    final auto = await PreferencesService.cloudSaveAutoSync;
    final policyName = await PreferencesService.cloudSaveConflictPolicy;
    final maxBackups = await PreferencesService.cloudSaveMaxBackups;
    if (!mounted) return;
    setState(() {
      _urlController.text = url;
      _userController.text = user;
      _passwordController.text = password;
      _rootController.text = root;
      _autoSync = auto;
      _policy = ConflictPolicy.values.firstWhere(
        (value) => value.name == policyName,
        orElse: () => ConflictPolicy.keepBoth,
      );
      _maxBackups = maxBackups;
    });
  }

  Future<void> _reloadFolders({bool refreshStats = false}) async {
    final folders = await PreferencesService.cloudSaveFolders;
    if (!mounted) return;
    setState(() => _folders = folders);
    if (refreshStats) _refreshStats();
  }

  Future<void> _refreshStats() async {
    final token = ++_statsToken;
    final folders = List<CloudSaveFolder>.from(_folders);
    for (final folder in folders) {
      final count = await EmulatorSaveService.countFiles(folder);
      final size = await EmulatorSaveService.folderSize(folder);
      if (!mounted || token != _statsToken) return;
      setState(() {
        _fileCounts[folder.id] = count;
        _sizes[folder.id] = size;
      });
    }
  }

  Future<void> _saveConfig() async {
    setState(() => _savingConfig = true);
    final url = _urlController.text.trim();
    final user = _userController.text.trim();
    final root = _rootController.text.trim();
    await PreferencesService.setWebdavUrl(url);
    await PreferencesService.setWebdavUsername(user);
    await PreferencesService.setWebdavPassword(_passwordController.text);
    await PreferencesService.setWebdavRoot(root.isEmpty ? 'RetroEngine' : root);
    if (!mounted) return;
    setState(() => _savingConfig = false);
    AppToast.show(context, 'WebDAV 配置已保存');
  }

  Future<void> _testConnection() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      AppToast.show(context, '请先填写 WebDAV 服务器地址');
      return;
    }
    setState(() => _testing = true);
    try {
      final ok = await _service.testConnection(
        url: url,
        username: _userController.text.trim(),
        password: _passwordController.text,
        root: _rootController.text.trim().isEmpty
            ? 'RetroEngine'
            : _rootController.text.trim(),
      );
      if (!mounted) return;
      AppToast.show(context, ok ? '连接成功，可以开始同步' : '连接失败，请检查配置');
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, e is Exception ? e.toString() : '连接失败：$e');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _toggleAutoSync(bool value) async {
    setState(() => _autoSync = value);
    await PreferencesService.setCloudSaveAutoSync(value);
  }

  Future<void> _setPolicy(ConflictPolicy policy) async {
    setState(() => _policy = policy);
    await PreferencesService.setCloudSaveConflictPolicy(policy.name);
  }

  Future<void> _setMaxBackups(int value) async {
    final clamped = value.clamp(0, 20).toInt();
    setState(() => _maxBackups = clamped);
    await PreferencesService.setCloudSaveMaxBackups(clamped);
  }

  Future<void> _detectEmulators() async {
    var granted = await LibraryService.hasStorageAccess();
    if (!granted) {
      await LibraryService.ensureStoragePermission();
      granted = await LibraryService.hasStorageAccess();
    }
    if (!granted) {
      if (mounted) AppToast.show(context, '未获得存储权限，无法扫描模拟器目录');
      return;
    }
    setState(() => _detecting = true);
    try {
      final detected = EmulatorSaveService.detect();
      final existingPaths = _folders.map((f) => f.localPath).toSet();
      final added = detected
          .where((folder) => !existingPaths.contains(folder.localPath))
          .toList();
      if (added.isNotEmpty) {
        final merged = <CloudSaveFolder>[..._folders, ...added];
        await PreferencesService.setCloudSaveFolders(merged);
        if (!mounted) return;
        setState(() => _folders = merged);
        _refreshStats();
      }
      if (!mounted) return;
      AppToast.show(
        context,
        added.isEmpty ? '没有发现新的模拟器存档目录' : '已添加 ${added.length} 个存档目录',
      );
    } finally {
      if (mounted) setState(() => _detecting = false);
    }
  }

  Future<void> _addManualFolder() async {
    final root = await LibraryService.defaultRoot();
    if (!mounted) return;
    final path = await Navigator.of(context).push<String>(
      AppPageRoute<String>(
        builder: (_) => FileBrowserScreen(
          initialPath: root,
          title: '选择存档目录',
        ),
      ),
    );
    if (path == null || !mounted) return;
    final folder = EmulatorSaveService.fromManualPath(path);
    if (folder == null) {
      AppToast.show(context, '目录不可访问');
      return;
    }
    if (_folders.any((f) => f.localPath == folder.localPath)) {
      AppToast.show(context, '该目录已在同步列表中');
      return;
    }
    final remote = _uniqueRemoteName(folder.remoteName, null);
    final merged = <CloudSaveFolder>[
      ..._folders,
      folder.copyWith(label: p.basename(path), remoteName: remote),
    ];
    await PreferencesService.setCloudSaveFolders(merged);
    if (!mounted) return;
    setState(() => _folders = merged);
    _refreshStats();
    AppToast.show(context, '已添加目录：${p.basename(path)}');
  }

  String _uniqueRemoteName(String desired, String? exceptId) {
    final used = _folders
        .where((f) => f.id != exceptId)
        .map((f) => f.remoteName.toLowerCase())
        .toSet();
    var name = desired;
    var index = 2;
    while (used.contains(name.toLowerCase())) {
      name = '$desired-$index';
      index++;
    }
    return name;
  }

  Future<void> _persistFolders(List<CloudSaveFolder> folders) async {
    setState(() => _folders = folders);
    await PreferencesService.setCloudSaveFolders(folders);
  }

  Future<void> _toggleFolder(CloudSaveFolder folder, bool enabled) async {
    final folders = _folders
        .map((f) => f.id == folder.id ? f.copyWith(enabled: enabled) : f)
        .toList();
    await _persistFolders(folders);
  }

  Future<void> _editFolder(CloudSaveFolder folder) async {
    final labelController = TextEditingController(text: folder.label);
    final remoteController = TextEditingController(text: folder.remoteName);
    final extensionsController = TextEditingController(
      text: folder.extensions.join(', '),
    );
    var includeAll = folder.includeAll;
    var enabled = folder.enabled;
    String? error;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: AppTheme.surface,
          title: Text('编辑「${folder.label}」',
              style: const TextStyle(
                  color: AppTheme.textPrimary, fontSize: 17)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: labelController,
                  style: const TextStyle(
                      color: AppTheme.textPrimary, fontSize: 14),
                  decoration: const InputDecoration(labelText: '显示名称'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: remoteController,
                  style: const TextStyle(
                      color: AppTheme.textPrimary, fontSize: 14),
                  decoration: const InputDecoration(
                    labelText: '云端目录名',
                    helperText: '仅使用英文、数字与短横线更稳定',
                  ),
                ),
                const SizedBox(height: 6),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('同步全部文件',
                      style: TextStyle(
                          color: AppTheme.textPrimary, fontSize: 14)),
                  subtitle: const Text('关闭后仅同步下方后缀的文件',
                      style: TextStyle(
                          color: AppTheme.textSecondary, fontSize: 11)),
                  value: includeAll,
                  activeColor: AppTheme.accent,
                  onChanged: (value) =>
                      setDialogState(() => includeAll = value),
                ),
                if (!includeAll)
                  TextField(
                    controller: extensionsController,
                    style: const TextStyle(
                        color: AppTheme.textPrimary, fontSize: 14),
                    decoration: const InputDecoration(
                      labelText: '同步后缀',
                      helperText: '逗号分隔，例如 sav, srm, state',
                    ),
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('参与同步',
                      style: TextStyle(
                          color: AppTheme.textPrimary, fontSize: 14)),
                  value: enabled,
                  activeColor: AppTheme.accent,
                  onChanged: (value) =>
                      setDialogState(() => enabled = value),
                ),
                if (error != null)
                  Text(error!,
                      style: const TextStyle(
                          color: AppTheme.danger, fontSize: 12)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                final remote = EmulatorSaveService.sanitizeRemoteName(
                    remoteController.text);
                if (labelController.text.trim().isEmpty ||
                    remote.isEmpty) {
                  setDialogState(() => error = '显示名称与云端目录名不能为空');
                  return;
                }
                if (_folders.any((f) =>
                    f.id != folder.id &&
                    f.remoteName.toLowerCase() == remote.toLowerCase())) {
                  setDialogState(() => error = '云端目录名已被其他目录使用');
                  return;
                }
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );

    final newLabel = labelController.text.trim();
    final newRemote =
        EmulatorSaveService.sanitizeRemoteName(remoteController.text);
    final newExtensions = extensionsController.text
        .split(RegExp(r'[,，\s]+'))
        .map((e) => e.trim().toLowerCase().replaceFirst('.', ''))
        .where((e) => e.isNotEmpty)
        .toList();
    labelController.dispose();
    remoteController.dispose();
    extensionsController.dispose();

    if (saved != true || !mounted) return;
    final folders = _folders
        .map((f) => f.id == folder.id
            ? f.copyWith(
                label: newLabel,
                remoteName: newRemote,
                includeAll: includeAll,
                enabled: enabled,
                extensions: newExtensions.isEmpty
                    ? EmulatorSaveService.commonExtensions
                    : newExtensions,
              )
            : f)
        .toList();
    await _persistFolders(folders);
    _refreshStats();
  }

  Future<void> _deleteFolder(CloudSaveFolder folder) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('移除同步目录',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 17)),
        content: Text(
          '将从同步列表移除「${folder.label}」。\n'
          '本地与云端已有的存档文件不会被删除。',
          style: const TextStyle(
              color: AppTheme.textSecondary, fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('移除',
                style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final folders =
        _folders.where((f) => f.id != folder.id).toList(growable: false);
    await _persistFolders(folders);
    await _service.forgetFolder(folder.id);
    if (!mounted) return;
    AppToast.show(context, '已移除「${folder.label}」');
  }

  Future<void> _syncFolder(CloudSaveFolder folder) async {
    final result = await _service.syncFolder(folder);
    if (!mounted) return;
    AppToast.show(context, result.message);
    await _reloadFolders();
  }

  Future<void> _syncAll() async {
    final result = await _service.syncAll();
    if (!mounted) return;
    AppToast.show(context, result.message);
    await _reloadFolders();
  }

  Future<void> _showBackups(CloudSaveFolder folder) async {
    final backups = await _service.listBackups(folder);
    if (!mounted) return;
    if (backups.isEmpty) {
      AppToast.show(context, '暂无本地备份');
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Row(
                children: [
                  const Icon(Icons.restore, size: 18, color: AppTheme.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('「${folder.label}」本地备份',
                        style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                itemCount: backups.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  final backup = backups[index];
                  final raw = p.basename(backup.path);
                  final parts = raw.split('T');
                  final timePart = parts.length > 1 ? parts[1] : '';
                  final label = timePart.isEmpty
                      ? raw
                      : '${parts.first} '
                          '${timePart.split('-').take(3).join(':')}';
                  return GlassCard(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    radius: 12,
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _restoreBackup(folder, backup);
                    },
                    child: Row(
                      children: [
                        const Icon(Icons.history, size: 18,
                            color: AppTheme.textSecondary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            index == 0 ? '$label（最新）' : label,
                            style: const TextStyle(
                                color: AppTheme.textPrimary, fontSize: 13),
                          ),
                        ),
                        const Text('恢复',
                            style: TextStyle(
                                color: AppTheme.accent, fontSize: 12)),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _restoreBackup(CloudSaveFolder folder, Directory backup) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('恢复备份',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 17)),
        content: Text(
          '将用备份中的文件覆盖「${folder.label}」当前存档，覆盖前会自动再备份一次。',
          style: const TextStyle(
              color: AppTheme.textSecondary, fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('恢复'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final count = await _service.restoreBackup(folder, backup);
    if (!mounted) return;
    AppToast.show(context, '已恢复 $count 个文件');
  }

  @override
  Widget build(BuildContext context) {
    final status = _service.status;
    final running = status.running;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('云存档'),
        actions: [
          IconButton(
            tooltip: '立即同步全部目录',
            icon: running
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppTheme.accent),
                  )
                : const Icon(Icons.sync),
            onPressed: running || _folders.isEmpty ? null : _syncAll,
          ),
          IconButton(
            tooltip: '同步说明',
            icon: const Icon(Icons.info_outline),
            onPressed: () => showInfoDialog(
              context,
              icon: Icons.cloud_sync_outlined,
              title: 'WebDAV 云存档',
              message: '按修改时间在本地与云端之间双向同步模拟器存档：'
                  '较新的一方覆盖较旧的一方，两端都修改时按冲突策略处理。\n\n'
                  '下载覆盖本地前会自动备份到应用文档目录，可在目录菜单中恢复。'
                  '推荐使用坚果云、Nextcloud 等支持 WebDAV 的服务。',
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 32),
        children: [
          if (running || status.total > 0) ...[
            _statusCard(status),
            const SizedBox(height: 12),
          ],
          _webDavCard(),
          const SizedBox(height: 12),
          _optionsCard(),
          const SizedBox(height: 12),
          _foldersCard(),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 卡片
  // ---------------------------------------------------------------------------

  Widget _section({required String title, required IconData icon, required List<Widget> children}) {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppTheme.accent),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _webDavCard() {
    return _section(
      title: 'WebDAV 服务器',
      icon: Icons.dns_outlined,
      children: [
        TextField(
          controller: _urlController,
          keyboardType: TextInputType.url,
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
          decoration: const InputDecoration(
            labelText: '服务器地址',
            hintText: 'https://dav.jianguoyun.com/dav/',
            prefixIcon:
                Icon(Icons.link, size: 18, color: AppTheme.textSecondary),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _userController,
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
          decoration: const InputDecoration(
            labelText: '账号 / 邮箱',
            prefixIcon: Icon(Icons.person_outline,
                size: 18, color: AppTheme.textSecondary),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _passwordController,
          obscureText: _obscure,
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            labelText: '密码 / 应用密码',
            prefixIcon: const Icon(Icons.lock_outline,
                size: 18, color: AppTheme.textSecondary),
            suffixIcon: IconButton(
              icon: Icon(_obscure
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _rootController,
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
          decoration: const InputDecoration(
            labelText: '云端根目录',
            hintText: 'RetroEngine',
            prefixIcon:
                Icon(Icons.folder_outlined, size: 18, color: AppTheme.textSecondary),
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          '密码保存在本机应用偏好中，仅用于 WebDAV Basic 认证。'
          '坚果云需先在网页端「安全设置」中创建应用密码。',
          style: TextStyle(
              color: AppTheme.textSecondary, fontSize: 11, height: 1.5),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            FilledButton.icon(
              onPressed: _savingConfig ? null : _saveConfig,
              icon: _savingConfig
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.save_outlined, size: 16),
              label: const Text('保存配置'),
            ),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: _testing ? null : _testConnection,
              icon: _testing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppTheme.accent),
                    )
                  : const Icon(Icons.wifi_tethering, size: 16),
              label: const Text('测试连接'),
              style: OutlinedButton.styleFrom(
                primary: AppTheme.textPrimary,
                side: const BorderSide(color: AppTheme.border),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _optionsCard() {
    return _section(
      title: '同步设置',
      icon: Icons.tune,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('启动时自动同步',
                      style: TextStyle(
                          color: AppTheme.textPrimary, fontSize: 14)),
                  SizedBox(height: 2),
                  Text('每次打开应用后在后台同步全部已启用目录',
                      style: TextStyle(
                          color: AppTheme.textSecondary, fontSize: 11)),
                ],
              ),
            ),
            Switch(
              value: _autoSync,
              activeColor: AppTheme.accent,
              onChanged: _toggleAutoSync,
            ),
          ],
        ),
        const Divider(height: 20, color: AppTheme.border),
        const Text('冲突处理（两端都修改时）',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 11.5)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: ConflictPolicy.values.map((policy) {
            final selected = _policy == policy;
            return ChoiceChip(
              label: Text(policy.label,
                  style: TextStyle(
                      fontSize: 12,
                      color: selected
                          ? Colors.white
                          : AppTheme.textPrimary)),
              selected: selected,
              selectedColor: AppTheme.accent,
              backgroundColor: AppTheme.subtleFill,
              side: BorderSide(
                  color: selected ? AppTheme.accent : AppTheme.border),
              onSelected: (_) => _setPolicy(policy),
            );
          }).toList(),
        ),
        const Divider(height: 20, color: AppTheme.border),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('本地备份份数',
                      style: TextStyle(
                          color: AppTheme.textPrimary, fontSize: 14)),
                  SizedBox(height: 2),
                  Text('下载覆盖前自动备份，按目录保留',
                      style: TextStyle(
                          color: AppTheme.textSecondary, fontSize: 11)),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.remove_circle_outline, size: 20),
              color: AppTheme.textSecondary,
              onPressed:
                  _maxBackups > 0 ? () => _setMaxBackups(_maxBackups - 1) : null,
            ),
            Text('$_maxBackups',
                style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
            IconButton(
              icon: const Icon(Icons.add_circle_outline, size: 20),
              color: AppTheme.textSecondary,
              onPressed:
                  _maxBackups < 20 ? () => _setMaxBackups(_maxBackups + 1) : null,
            ),
          ],
        ),
      ],
    );
  }

  Widget _foldersCard() {
    final running = _service.running;
    return _section(
      title: '存档目录（${_folders.length}）',
      icon: Icons.save_outlined,
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _detecting || running ? null : _detectEmulators,
                icon: _detecting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppTheme.accent),
                      )
                    : const Icon(Icons.auto_awesome, size: 16),
                label: const Text('自动检测模拟器'),
                style: OutlinedButton.styleFrom(
                  primary: AppTheme.textPrimary,
                  side: const BorderSide(color: AppTheme.border),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: running ? null : _addManualFolder,
                icon: const Icon(Icons.create_new_folder_outlined, size: 16),
                label: const Text('手动选择目录'),
                style: OutlinedButton.styleFrom(
                  primary: AppTheme.textPrimary,
                  side: const BorderSide(color: AppTheme.border),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          '自动检测支持 RetroArch、PPSSPP、Citra、Azahar、PCSX2、AetherSX2。'
          'Android 11 及以上需要「所有文件访问权限」才能读取模拟器目录。',
          style: TextStyle(
              color: AppTheme.textSecondary, fontSize: 11, height: 1.5),
        ),
        if (_folders.isEmpty) ...[
          const SizedBox(height: 16),
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('还没有同步目录，先自动检测或手动选择',
                  style: TextStyle(
                      color: AppTheme.textSecondary, fontSize: 12)),
            ),
          ),
        ] else ...[
          const SizedBox(height: 6),
          ..._folders.map(_folderTile),
          const SizedBox(height: 6),
          FilledButton.icon(
            onPressed: running ? null : _syncAll,
            icon: running
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.cloud_sync_outlined, size: 18),
            label: Text(running ? '正在同步…' : '同步全部目录'),
          ),
        ],
      ],
    );
  }

  Widget _folderTile(CloudSaveFolder folder) {
    final kind = folder.emulator;
    final count = _fileCounts[folder.id];
    final size = _sizes[folder.id];
    final last = folder.lastSyncMs;
    final lastLabel = last == null ? '尚未同步' : '上次 ${_formatDate(last)}';
    final running = _service.running;

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        decoration: BoxDecoration(
          color: AppTheme.subtleFill.withOpacity(0.55),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    kind.label,
                    style: const TextStyle(
                        color: AppTheme.accent, fontSize: 10.5),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    folder.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                Switch(
                  value: folder.enabled,
                  activeColor: AppTheme.accent,
                  onChanged:
                      running ? null : (value) => _toggleFolder(folder, value),
                ),
                PopupMenuButton<String>(
                  tooltip: '更多操作',
                  icon: const Icon(Icons.more_vert,
                      size: 18, color: AppTheme.textSecondary),
                  onSelected: (value) {
                    switch (value) {
                      case 'sync':
                        _syncFolder(folder);
                        break;
                      case 'edit':
                        _editFolder(folder);
                        break;
                      case 'backups':
                        _showBackups(folder);
                        break;
                      case 'delete':
                        _deleteFolder(folder);
                        break;
                    }
                  },
                  itemBuilder: (context) => <PopupMenuEntry<String>>[
                    PopupMenuItem<String>(
                      value: 'sync',
                      child: Row(children: const [
                        Icon(Icons.sync, size: 18, color: AppTheme.accent),
                        SizedBox(width: 10),
                        Text('立即同步'),
                      ]),
                    ),
                    PopupMenuItem<String>(
                      value: 'edit',
                      child: Row(children: const [
                        Icon(Icons.edit_outlined,
                            size: 18, color: AppTheme.textSecondary),
                        SizedBox(width: 10),
                        Text('编辑目录'),
                      ]),
                    ),
                    PopupMenuItem<String>(
                      value: 'backups',
                      child: Row(children: const [
                        Icon(Icons.restore,
                            size: 18, color: AppTheme.textSecondary),
                        SizedBox(width: 10),
                        Text('本地备份'),
                      ]),
                    ),
                    PopupMenuItem<String>(
                      value: 'delete',
                      child: Row(children: const [
                        Icon(Icons.delete_outline,
                            size: 18, color: AppTheme.danger),
                        SizedBox(width: 10),
                        Text('移除目录',
                            style: TextStyle(color: AppTheme.danger)),
                      ]),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              folder.localPath,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(color: AppTheme.textSecondary, fontSize: 10.5),
            ),
            const SizedBox(height: 2),
            Text(
              '→ /${folder.remoteName}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(color: AppTheme.textSecondary, fontSize: 10.5),
            ),
            const SizedBox(height: 4),
            Text(
              [
                if (count == null) '统计中…' else '$count 个文件',
                if (size != null) EmulatorSaveService.formatBytes(size),
                lastLabel,
                if (folder.lastResult != null) folder.lastResult!,
              ].join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(color: AppTheme.textSecondary, fontSize: 10.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusCard(CloudSyncStatus status) {
    final running = status.running;
    final logs = status.logs;

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                running ? Icons.cloud_sync_outlined : Icons.cloud_done_outlined,
                size: 18,
                color: running ? AppTheme.accent : AppTheme.success,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  status.message.isEmpty
                      ? (running ? '正在同步…' : '同步完成')
                      : status.message,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600),
                ),
              ),
              if (status.total > 0)
                Text('${status.completed}/${status.total}',
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 11)),
            ],
          ),
          if (running) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: status.progress,
                minHeight: 5,
                backgroundColor: AppTheme.subtleFill,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(AppTheme.accent),
              ),
            ),
            if (status.currentFile.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                status.currentFile,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 10.5),
              ),
            ],
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              _statItem(Icons.arrow_upward, '上传', status.uploaded,
                  AppTheme.accent),
              _statItem(Icons.arrow_downward, '下载', status.downloaded,
                  AppTheme.success),
              _statItem(Icons.merge_type, '冲突', status.conflicts,
                  AppTheme.warning),
              _statItem(Icons.error_outline, '失败', status.failed,
                  AppTheme.danger),
            ],
          ),
          if (logs.isNotEmpty) ...[
            const Divider(height: 18, color: AppTheme.border),
            ...logs.reversed.take(5).map(
                  (log) => Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      '${log.timeLabel}  ${log.message}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: log.failed
                            ? AppTheme.danger
                            : AppTheme.textSecondary,
                        fontSize: 10.5,
                      ),
                    ),
                  ),
                ),
          ],
        ],
      ),
    );
  }

  Widget _statItem(IconData icon, String label, int value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text('$label $value',
            style: const TextStyle(
                color: AppTheme.textSecondary, fontSize: 11)),
      ],
    );
  }

  String _formatDate(int millis) {
    final time = DateTime.fromMillisecondsSinceEpoch(millis);
    final now = DateTime.now();
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');
    final sameDay = time.year == now.year &&
        time.month == now.month &&
        time.day == now.day;
    if (sameDay) return '今天 $hh:$mm';
    final mo = time.month.toString().padLeft(2, '0');
    final dd = time.day.toString().padLeft(2, '0');
    return '$mo-$dd $hh:$mm';
  }
}