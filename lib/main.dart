import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;

import 'data/screenscraper_systems.dart';
import 'screens/library_screen.dart';
import 'services/background_scrape_service.dart';
import 'services/cloud_save_service.dart';
import 'services/library_service.dart';
import 'services/preferences_service.dart';
import 'theme.dart';

class _MoveFocusIntent extends Intent {
  const _MoveFocusIntent(this.direction);
  final TraversalDirection direction;
}

class _MoveFocusAction extends Action<_MoveFocusIntent> {
  @override
  Object? invoke(_MoveFocusIntent intent) {
    FocusManager.instance.primaryFocus?.focusInDirection(intent.direction);
    return null;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 预加载 ScreenScraper 平台 systemeid 表（assets 生成文件）。
  await ScreenscraperSystems.load();
  runApp(const SaveDeckToolkitApp());
}

class SaveDeckToolkitApp extends StatefulWidget {
  const SaveDeckToolkitApp({super.key});

  @override
  State<SaveDeckToolkitApp> createState() => _SaveDeckToolkitAppState();
}

class _SaveDeckToolkitAppState extends State<SaveDeckToolkitApp>
    with WidgetsBindingObserver {
  int _revision = 0;
  String? _libraryPath;
  bool _checkingPermission = true;
  String? _permissionMessage;

  /// 后台搜刮完成后，顶部提示条在 1 秒后自动隐藏。
  Timer? _bannerTimer;
  bool _hideCompletedBanner = false;
  bool _wasScrapeRunning = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    BackgroundScrapeService.instance.addListener(_onBackgroundChanged);
    _initialize();
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    BackgroundScrapeService.instance.removeListener(_onBackgroundChanged);
    super.dispose();
  }

  void _onBackgroundChanged() {
    if (!mounted) return;
    final running = BackgroundScrapeService.instance.status.running;
    if (running) {
      // 新一轮搜刮开始：取消隐藏计时并重新显示提示条。
      _bannerTimer?.cancel();
      _bannerTimer = null;
      _hideCompletedBanner = false;
    } else if (_wasScrapeRunning) {
      // 队列刚结束：完成提示只保留 1 秒。
      _bannerTimer?.cancel();
      _bannerTimer = Timer(const Duration(seconds: 1), () {
        if (!mounted) return;
        setState(() => _hideCompletedBanner = true);
      });
    }
    _wasScrapeRunning = running;
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 从系统「所有文件访问权限」设置页返回时，系统权限状态可能有短暂延迟，
      // 稍等再重新检测，避免刚返回时仍读到未授权而提示失败。
      Future<void>.delayed(const Duration(milliseconds: 300), _recheckPermission);
    }
  }

  Future<void> _recheckPermission() async {
    final path = await PreferencesService.libraryPath;

    // 尚未绑定游戏库时不提示权限，避免首次启动就显示警告；绑定目录时再引导。
    if (path == null || path.isEmpty) {
      if (mounted) setState(() => _permissionMessage = null);
      return;
    }

    final hasPermission = await LibraryService.hasStorageAccess();
    final access = await LibraryService.verifyDirectoryAccess(path);
    final granted = hasPermission && access.ok;

    String? message;
    if (!granted) {
      if (!hasPermission) {
        message = '无法访问游戏库目录，请开启“所有文件访问权限”（特殊应用权限中）。';
      } else if (!access.exists) {
        message = '游戏库目录不存在，请在「设置」中重新选择游戏库目录。';
      } else {
        message = '无法读取游戏库目录，请确认“所有文件访问权限”已开启。';
      }
    }

    if (!mounted) return;
    // 只更新提示条，不重建子页面：子页面会在 resumed 时自行刷新，
    // 避免打断用户正在进行的目录选择流程。
    setState(() => _permissionMessage = granted ? null : message);
  }

  Future<void> _initialize() async {
    final path = await PreferencesService.libraryPath;
    if (mounted) setState(() => _libraryPath = path);

    await LibraryService.ensureStoragePermission();
    await _recheckPermission();
    if (mounted) setState(() => _checkingPermission = false);

    // 启动后按设置自动进行云存档同步，后台执行不阻塞首屏。
    unawaited(CloudSaveService.instance.autoSyncOnStart());
  }

  void _onLibraryChanged(String path) {
    setState(() {
      _libraryPath = path;
      _revision++;
    });
    // 目录刚变更，立即重检一次，保证未授权时能及时显示提示条。
    _recheckPermission();
  }

  void _bump() => setState(() => _revision++);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'RetroEngine',
      theme: AppTheme.theme,
      home: Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.arrowUp):
              _MoveFocusIntent(TraversalDirection.up),
          SingleActivator(LogicalKeyboardKey.arrowDown):
              _MoveFocusIntent(TraversalDirection.down),
          SingleActivator(LogicalKeyboardKey.arrowLeft):
              _MoveFocusIntent(TraversalDirection.left),
          SingleActivator(LogicalKeyboardKey.arrowRight):
              _MoveFocusIntent(TraversalDirection.right),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            _MoveFocusIntent: _MoveFocusAction(),
          },
          child: FocusTraversalGroup(
            child: Scaffold(
              extendBody: true,
        backgroundColor: AppTheme.background,
        body: AppTheme.backdrop(
          child: _checkingPermission
              ? const Center(child: GlassLoader(message: '正在检查权限…'))
              : Column(
                  children: [
                    if (_permissionMessage != null)
                      Container(
                        margin: const EdgeInsets.fromLTRB(16, 44, 16, 0),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.warning.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.warning.withOpacity(0.4)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded,
                                color: AppTheme.warning, size: 20),
                            const SizedBox(width: 10),
                            Expanded(child: Text(_permissionMessage!,
                                style: const TextStyle(
                                    color: AppTheme.textPrimary, fontSize: 12))),
                            TextButton(
                              onPressed: () async {
                                await LibraryService.requestManageStorageSettings();
                                _recheckPermission();
                              },
                              child: const Text('去授权'),
                            ),
                          ],
                        ),
                      ),
                    _buildBackgroundProgress(),
                    Expanded(
                      child: LibraryScreen(
                        key: ValueKey('library-$_revision'),
                        libraryPath: _libraryPath,
                        onReload: _bump,
                        onLibraryChanged: _onLibraryChanged,
                      ),
                    ),
                  ],
                ),
        ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackgroundProgress() {
    final status = BackgroundScrapeService.instance.status;
    if (status.total == 0) return const SizedBox.shrink();
    if (!status.running && _hideCompletedBanner) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        radius: 12,
        onTap: _showScrapeProgressDialog,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  status.running ? Icons.download : Icons.check_circle_outline,
                  size: 16,
                  color: AppTheme.accent,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    status.running
                        ? '后台搜刮 ${status.completed}/${status.total} · ${status.currentName}'
                        : '上次后台搜刮：成功 ${status.success}，失败 ${status.failed}',
                    style: const TextStyle(
                        color: AppTheme.textPrimary, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.chevron_right,
                    size: 16, color: AppTheme.textSecondary),
              ],
            ),
            if (status.running) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: status.progress,
                minHeight: 3,
                backgroundColor: AppTheme.border,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(AppTheme.accent),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showScrapeProgressDialog() {
    final service = BackgroundScrapeService.instance;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (dialogContext) => AnimatedBuilder(
        animation: service,
        builder: (context, _) {
          final status = service.status;
          final entries = status.statuses.entries.toList();
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text('后台搜刮进度',
                            style: TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.w600)),
                      ),
                      if (!status.running)
                        TextButton(
                          onPressed: () {
                            service.clear();
                            Navigator.pop(dialogContext);
                          },
                          child: const Text('清除记录'),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: LinearProgressIndicator(
                    value: status.progress,
                    minHeight: 4,
                    backgroundColor: AppTheme.border,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(AppTheme.accent),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text(
                    status.message.isEmpty
                        ? '等待任务…'
                        : '${status.message}（${status.completed}/${status.total}）',
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 12),
                  ),
                ),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    itemCount: entries.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      final failed = entry.value.startsWith('失败');
                      final itemProgress = status.progresses[entry.key] ?? 0;
                      return ListTile(
                        dense: true,
                        title: Text(
                          entry.key.split('/').last,
                          style: const TextStyle(
                              color: AppTheme.textPrimary, fontSize: 13),
                        ),
                        subtitle: itemProgress > 0 && itemProgress < 1
                            ? LinearProgressIndicator(
                                value: itemProgress,
                                minHeight: 2,
                                backgroundColor: AppTheme.border,
                                valueColor:
                                    const AlwaysStoppedAnimation<Color>(
                                        AppTheme.accent),
                              )
                            : null,
                        trailing: Text(
                          itemProgress > 0 && itemProgress < 1
                              ? '${(itemProgress * 100).toInt()}%'
                              : entry.value,
                          style: TextStyle(
                              color: failed ? AppTheme.danger : AppTheme.success,
                              fontSize: 11),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

}
