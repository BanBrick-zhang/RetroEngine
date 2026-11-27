import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../data/emulator_catalog.dart';
import '../models/emulator.dart';
import '../models/library.dart';
import '../services/emulator_service.dart';
import '../services/library_service.dart';
import '../services/preferences_service.dart';
import '../services/toml_service.dart';
import '../theme.dart';
import '../widgets/app_toast.dart';
import '../widgets/emulator_picker.dart';
import '../widgets/permission_dialog.dart';
import 'file_browser_screen.dart';

/// 可导入的 ROM 扩展名（与主页面添加 ROM 保持一致）。
const List<String> _romExtensions = <String>[
  'nes', 'fc', 'sfc', 'snes', 'gb', 'gbc', 'gba', 'n64', 'nds', '3ds',
  'zip', '7z', 'iso', 'bin', 'cue', 'chd', 'pbp', 'cso', 'md', 'gen',
  'sms', 'gg', 'pce', 'gcm', 'rvz', 'a26', 'vpk', 'wbfs', 'gdi', 'fds',
];

/// 游戏库管理：对已扫描平台进行重命名、排序、新增平台与导入 ROM。
class LibraryEditScreen extends StatefulWidget {
  final ValueChanged<String>? onChanged;

  const LibraryEditScreen({super.key, this.onChanged});

  @override
  State<LibraryEditScreen> createState() => _LibraryEditScreenState();
}

class _LibraryEditScreenState extends State<LibraryEditScreen> {
  List<PlatformLibrary> _platforms = <PlatformLibrary>[];
  Map<String, EmulatorConfig> _emulators = <String, EmulatorConfig>{};
  String? _path;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final path = await PreferencesService.libraryPath;
    if (!mounted) return;
    if (path == null || path.isEmpty) {
      setState(() {
        _path = null;
        _platforms = <PlatformLibrary>[];
        _loading = false;
      });
      return;
    }
    try {
      final platforms = await LibraryService.loadLibrary(path);
      final emulators = await EmulatorService.instance.loadConfigs();
      if (!mounted) return;
      setState(() {
        _path = path;
        _platforms = platforms;
        _emulators = emulators;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// 平台当前的默认模拟器配置。
  EmulatorConfig? _emulatorFor(PlatformLibrary platform) =>
      _emulators[emulatorPlatformKey(platform.platform)];

  /// 选择 / 清除平台的默认模拟器。
  Future<void> _pickEmulator(PlatformLibrary platform) async {
    final current = _emulatorFor(platform);
    final result = await showEmulatorPicker(
      context,
      platformName: platform.platform,
      initial: current,
    );
    if (result == null) return;
    try {
      await EmulatorService.instance.saveConfig(
        platform.platform,
        result.removed ? null : result.config,
      );
      final configs = await EmulatorService.instance.loadConfigs();
      if (!mounted) return;
      setState(() => _emulators = configs);
      _showMessage(result.removed
          ? '已清除 ${platform.platform} 的默认模拟器'
          : '默认模拟器：${result.config?.label ?? ''}');
    } catch (e) {
      if (mounted) _showMessage('保存失败：$e');
    }
  }

  void _notifyChanged() {
    final path = _path;
    if (path != null && path.isNotEmpty) widget.onChanged?.call(path);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('游戏库管理'),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : () => _load(),
          ),
          IconButton(
            tooltip: '添加平台',
            icon: const Icon(Icons.create_new_folder_outlined),
            onPressed: _path == null || _busy ? null : _addPlatform,
          ),
        ],
      ),
      body: SafeArea(
        child: AppTheme.backdrop(
          child: _loading
              ? const Center(child: GlassLoader(message: '正在读取平台列表…'))
              : _error != null
                  ? _errorView()
                  : _path == null
                      ? _unboundView()
                      : _contentView(),
        ),
      ),
    );
  }

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: GlassCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline,
                    color: AppTheme.danger, size: 40),
                const SizedBox(height: 12),
                Text(_error!,
                    style: const TextStyle(
                        color: AppTheme.textPrimary, fontSize: 13)),
                const SizedBox(height: 12),
                FilledButton(onPressed: _load, child: const Text('重试')),
              ],
            ),
          ),
        ),
      );

  Widget _unboundView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: GlassCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.folder_off_outlined,
                    size: 44, color: AppTheme.textSecondary),
                SizedBox(height: 14),
                Text(
                  '尚未绑定游戏库总目录',
                  style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 8),
                Text(
                  '请返回设置，在「游戏库」中选择目录后再进行平台管理。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: AppTheme.textSecondary, fontSize: 12, height: 1.6),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _contentView() {
    final gameCount =
        _platforms.fold<int>(0, (sum, platform) => sum + platform.games.length);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        GlassCard(
          padding: const EdgeInsets.all(14),
          radius: 14,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.folder_shared_outlined,
                      size: 16, color: AppTheme.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _path!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppTheme.textPrimary, fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '共 ${_platforms.length} 个平台 · $gameCount 款游戏',
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 11),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          '重命名仅修改 savedeck.toml 中的平台显示名，不会改动目录名；'
          '排序会写入各平台的 sort 字段，决定游戏库中的展示顺序。',
          style: TextStyle(
              color: AppTheme.textSecondary, fontSize: 11, height: 1.6),
        ),
        const SizedBox(height: 12),
        if (_platforms.isEmpty)
          GlassCard(
            child: Column(
              children: [
                const Icon(Icons.create_new_folder_outlined,
                    size: 40, color: AppTheme.textSecondary),
                const SizedBox(height: 12),
                const Text(
                  '还没有可管理的平台',
                  style: TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _busy ? null : _addPlatform,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('添加平台'),
                ),
              ],
            ),
          )
        else
          for (var index = 0; index < _platforms.length; index++) ...[
            _platformCard(_platforms[index], index),
            const SizedBox(height: 10),
          ],
        if (_platforms.isNotEmpty) ...[
          const SizedBox(height: 4),
          FilledButton.icon(
            onPressed: _busy ? null : _addPlatform,
            icon: const Icon(Icons.create_new_folder_outlined, size: 18),
            label: const Text('添加游戏平台'),
          ),
        ],
        if (_busy) ...[
          const SizedBox(height: 18),
          const Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppTheme.accent),
            ),
          ),
        ],
      ],
    );
  }

  Widget _platformCard(PlatformLibrary platform, int index) {
    final sortLabel =
        platform.sort == null || platform.sort!.isEmpty ? '未设置排序' : '排序 ${platform.sort}';
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      radius: 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppTheme.accent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                      color: AppTheme.accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            platform.platform,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (!platform.hasToml)
                          const Padding(
                            padding: EdgeInsets.only(left: 6),
                            child: Icon(Icons.auto_awesome_outlined,
                                size: 13, color: AppTheme.warning),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${platform.games.length} 款游戏 · $sortLabel · '
                      '${p.basename(platform.directory)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 11),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(
                          Icons.play_circle_outline,
                          size: 12,
                          color: _emulatorFor(platform) == null
                              ? AppTheme.warning
                              : AppTheme.success,
                        ),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            _emulatorFor(platform) == null
                                ? '默认模拟器：未设置'
                                : '默认模拟器：${_emulatorFor(platform)!.label}'
                                    '${_emulatorFor(platform)!.core == null ? '' : ' · ${_emulatorFor(platform)!.core}'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: AppTheme.textSecondary, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: '排序',
                enabled: !_busy,
                icon: const Icon(Icons.swap_vert,
                    size: 20, color: AppTheme.textSecondary),
                onSelected: (value) {
                  if (value == 'up') {
                    _movePlatform(index, -1);
                  } else if (value == 'down') {
                    _movePlatform(index, 1);
                  }
                },
                itemBuilder: (context) => <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(
                    value: 'up',
                    enabled: index > 0,
                    child: const Text('上移'),
                  ),
                  PopupMenuItem<String>(
                    value: 'down',
                    enabled: index < _platforms.length - 1,
                    child: const Text('下移'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 4,
            runSpacing: 2,
            children: [
              TextButton.icon(
                onPressed: _busy ? null : () => _editPlatform(platform),
                icon: const Icon(Icons.drive_file_rename_outline,
                    size: 16, color: AppTheme.accent),
                label: const Text('重命名 / 排序'),
              ),
              TextButton.icon(
                onPressed: _busy ? null : () => _importRom(platform),
                icon: const Icon(Icons.videogame_asset_outlined,
                    size: 16, color: AppTheme.accent),
                label: const Text('导入 ROM'),
              ),
              TextButton.icon(
                onPressed: _busy ? null : () => _pickEmulator(platform),
                icon: const Icon(Icons.memory_outlined,
                    size: 16, color: AppTheme.accent),
                label: Text(_emulatorFor(platform) == null ? '设置模拟器' : '更换模拟器'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 重命名平台显示名并修改排序值。
  Future<void> _editPlatform(PlatformLibrary platform) async {
    final nameController = TextEditingController(text: platform.platform);
    final sortController = TextEditingController(text: platform.sort ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('编辑平台',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 17)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                labelText: '平台名称',
                hintText: '例如：GBA、PS2',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: sortController,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                labelText: '排序',
                hintText: '例如：001，留空则不设置',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (saved != true) return;

    final name = nameController.text.trim();
    if (name.isEmpty) {
      _showMessage('平台名称不能为空');
      return;
    }
    platform.platform = name;
    final sort = sortController.text.trim();
    platform.sort = sort.isEmpty ? null : sort;
    platform.hasToml = true;
    try {
      await TomlService.save(platform);
      _notifyChanged();
      await _load(silent: true);
      if (mounted) _showMessage('平台信息已保存');
    } catch (e) {
      if (mounted) _showMessage('保存失败：$e');
    }
  }

  /// 在游戏库根目录下创建新平台目录与 savedeck.toml。
  Future<void> _addPlatform() async {
    final root = _path;
    if (root == null) return;
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('添加平台',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 17)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: const InputDecoration(
            labelText: '平台目录名称',
            hintText: '例如：GBA、FC、PSX',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(context, controller.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    if (RegExp(r'[\\/:*?"<>|]').hasMatch(name)) {
      _showMessage('名称不能包含 \\ / : * ? " < > | 等字符');
      return;
    }
    setState(() => _busy = true);
    try {
      await LibraryService.createPlatform(root, name);
      _notifyChanged();
      await _load(silent: true);
      if (mounted) _showMessage('已创建平台 ${name.toUpperCase()}');
    } catch (e) {
      if (mounted) _showMessage('创建失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 选择 ROM 文件并复制到该平台目录，同时登记到 savedeck.toml。
  Future<void> _importRom(PlatformLibrary platform) async {
    final access = await ensureStorageAccessPrompt(
      context,
      isMounted: () => mounted,
    );
    if (!mounted || access != StorageAccessPrompt.granted) return;

    final romPath = await Navigator.of(context).push<String>(
      AppPageRoute(
        builder: (_) => FileBrowserScreen(
          initialPath: platform.directory,
          mode: FileBrowserMode.file,
          title: '选择要导入的 ROM',
          extensions: _romExtensions,
        ),
      ),
    );
    if (romPath == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final relative =
          await LibraryService.copyRomToPlatform(romPath, platform);
      if (platform.games.any((game) => game.file == relative)) {
        if (mounted) _showMessage('该 ROM 已在平台中，无需重复导入');
        return;
      }
      final generateId = await PreferencesService.autoId;
      platform.games.add(GameEntry(
        name: LibraryService.gameNameFromRom(romPath),
        file: relative,
        id: generateId ? LibraryService.newId() : null,
      ));
      await TomlService.save(platform);
      _notifyChanged();
      await _load(silent: true);
      if (mounted) {
        _showMessage('已导入 ${p.basename(romPath)}');
      }
    } catch (e) {
      if (mounted) _showMessage('导入失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 调整平台顺序：交换后按当前顺序写入 001、002… 的 sort 值。
  Future<void> _movePlatform(int index, int delta) async {
    final target = index + delta;
    if (target < 0 || target >= _platforms.length) return;
    setState(() {
      final moved = _platforms.removeAt(index);
      _platforms.insert(target, moved);
      _busy = true;
    });
    try {
      for (var i = 0; i < _platforms.length; i++) {
        final platform = _platforms[i];
        final sort = (i + 1).toString().padLeft(3, '0');
        if (platform.hasToml && platform.sort == sort) continue;
        platform.sort = sort;
        await TomlService.save(platform);
      }
      _notifyChanged();
      await _load(silent: true);
      if (mounted) _showMessage('平台顺序已保存');
    } catch (e) {
      if (mounted) _showMessage('保存顺序失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    AppToast.show(context, message);
  }
}