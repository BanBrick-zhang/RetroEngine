import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'data/screenscraper_systems.dart';
import 'screens/batch_scrape_screen.dart';
import 'screens/library_screen.dart';
import 'screens/settings_screen.dart';
import 'services/library_service.dart';
import 'services/preferences_service.dart';
import 'theme.dart';

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
  int _index = 0;
  int _revision = 0;
  String? _libraryPath;
  bool _checkingPermission = true;
  String? _permissionMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
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
  }

  void _onLibraryChanged(String path) {
    setState(() {
      _libraryPath = path;
      _revision++;
      _index = 0;
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
      home: Scaffold(
        extendBody: true,
        backgroundColor: AppTheme.background,
        body: AppTheme.backdrop(
          child: _checkingPermission
              ? const Center(
                  child: CircularProgressIndicator(color: AppTheme.accent),
                )
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
                    Expanded(
                      child: IndexedStack(
                        index: _index,
                        children: [
                          LibraryScreen(
                            key: ValueKey('library-$_revision'),
                            libraryPath: _libraryPath,
                            onReload: _bump,
                            onLibraryChanged: _onLibraryChanged,
                          ),
                          BatchScrapeScreen(
                            key: ValueKey('batch-$_revision'),
                            libraryPath: _libraryPath,
                          ),
                          SettingsScreen(
                            key: ValueKey('settings-$_revision'),
                            onLibraryChanged: _onLibraryChanged,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
        bottomNavigationBar: _buildBottomBar(),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.88),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: NavigationBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            selectedIndex: _index,
            onDestinationSelected: (index) => setState(() => _index = index),
            destinations: const <NavigationDestination>[
              NavigationDestination(
                icon: Icon(Icons.sports_esports_outlined),
                selectedIcon: Icon(Icons.sports_esports),
                label: '游戏库',
              ),
              NavigationDestination(
                icon: Icon(Icons.auto_awesome_outlined),
                selectedIcon: Icon(Icons.auto_awesome),
                label: '批量搜刮',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: '设置',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
