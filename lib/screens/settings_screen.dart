import 'package:flutter/material.dart';

import '../services/library_service.dart';
import '../services/preferences_service.dart';
import '../services/screenscraper_service.dart';
import '../theme.dart';
import '../widgets/permission_dialog.dart';
import 'file_browser_screen.dart';

class SettingsScreen extends StatefulWidget {
  final ValueChanged<String> onLibraryChanged;

  const SettingsScreen({super.key, required this.onLibraryChanged});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  final _userController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _libraryPath;
  String? _language;
  bool _cover = true;
  bool _video = true;
  bool _overwrite = true;
  bool _autoId = true;
  bool _obscure = true;
  bool _testing = false;

  /// 是否因缺少权限而等待用户从系统设置返回后自动继续选择目录。
  bool _pendingPick = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _userController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _pendingPick) {
      _pendingPick = false;
      _resumePickLibrary();
    }
  }

  /// 授权返回后：已授权则自动继续打开目录选择器，否则提示一次。
  Future<void> _resumePickLibrary() async {
    if (!mounted) return;
    if (!await LibraryService.hasStorageAccess()) {
      if (mounted) _showMessage('尚未开启“所有文件访问权限”，请重试');
      return;
    }
    if (mounted) await _pickLibrary();
  }

  Future<void> _load() async {
    final path = await PreferencesService.libraryPath;
    final user = await PreferencesService.ssUsername;
    final password = await PreferencesService.ssPassword;
    final language = await PreferencesService.language;
    final cover = await PreferencesService.downloadCover;
    final video = await PreferencesService.downloadVideo;
    final overwrite = await PreferencesService.overwriteDescription;
    final autoId = await PreferencesService.autoId;
    if (!mounted) return;
    setState(() {
      _libraryPath = path;
      _userController.text = user ?? '';
      _passwordController.text = password ?? '';
      _language = language;
      _cover = cover;
      _video = video;
      _overwrite = overwrite;
      _autoId = autoId;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('设置')),
      body: AppTheme.backdrop(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
          children: [
            _libraryCard(),
            const SizedBox(height: 14),
            _accountCard(),
            const SizedBox(height: 14),
            _optionsCard(),
            const SizedBox(height: 14),
            _aboutCard(),
          ],
        ),
      ),
    );
  }

  Widget _libraryCard() {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle('游戏库', icon: Icons.folder_shared_outlined),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.subtleFill,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              _libraryPath ?? '尚未绑定游戏库总目录',
              style: TextStyle(
                color: _libraryPath == null ? AppTheme.textSecondary : AppTheme.textPrimary,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton.tonalIcon(
                onPressed: _pickLibrary,
                icon: const Icon(Icons.folder_open, size: 16),
                label: const Text('选择目录'),
                style: FilledButton.styleFrom(
                  foregroundColor: AppTheme.textPrimary,
                  backgroundColor: AppTheme.subtleFill,
                ),
              ),
              const SizedBox(width: 10),
              TextButton.icon(
                onPressed: _libraryPath == null ? null : () => widget.onLibraryChanged(_libraryPath!),
                icon: const Icon(Icons.link, size: 16),
                label: const Text('应用绑定'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _accountCard() {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle('ScreenScraper 账号', icon: Icons.account_circle_outlined),
          const SizedBox(height: 6),
          const Text(
            '开发者凭据已内置，无需填写。填写你的 ScreenScraper 账号（用户名，非邮箱）'
            '可提升每日请求配额；留空则以匿名访客身份调用。',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 11, height: 1.5),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _userController,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
            decoration: const InputDecoration(
              labelText: '用户名 / SSID',
              prefixIcon: Icon(Icons.person_outline, size: 18, color: AppTheme.textSecondary),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _passwordController,
            obscureText: _obscure,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              labelText: '密码',
              prefixIcon: const Icon(Icons.lock_outline, size: 18, color: AppTheme.textSecondary),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              FilledButton.tonal(
                onPressed: _saveAccount,
                style: FilledButton.styleFrom(
                  foregroundColor: AppTheme.textPrimary,
                  backgroundColor: AppTheme.subtleFill,
                ),
                child: const Text('保存账号'),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: _testing ? null : _testConnection,
                icon: _testing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accent),
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
      ),
    );
  }

  Widget _optionsCard() {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle('搜刮选项', icon: Icons.tune),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.translate_outlined, size: 18, color: AppTheme.textSecondary),
              const SizedBox(width: 10),
              const Text('首选语言', style: TextStyle(color: AppTheme.textPrimary, fontSize: 14)),
              const Spacer(),
              DropdownButton<String>(
                value: _language ?? 'en',
                dropdownColor: AppTheme.surface,
                style: const TextStyle(color: AppTheme.textPrimary),
                underline: const SizedBox(),
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem(value: 'zh', child: Text('中文')),
                  DropdownMenuItem(value: 'en', child: Text('English')),
                  DropdownMenuItem(value: 'ja', child: Text('日本語')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _language = value);
                  PreferencesService.setLanguage(value);
                },
              ),
            ],
          ),
          _switchTile('下载 box2D 封面到 media/游戏名/cover.png', _cover,
              (v) => setState(() => _cover = v), (v) => PreferencesService.setDownloadCover(v)),
          _switchTile('下载游戏视频到 media/游戏名/video.mp4', _video,
              (v) => setState(() => _video = v), (v) => PreferencesService.setDownloadVideo(v)),
          _switchTile('用搜刮简介覆盖已有简介', _overwrite,
              (v) => setState(() => _overwrite = v),
              (v) => PreferencesService.setOverwriteDescription(v)),
          _switchTile('新游戏自动生成 UUID', _autoId,
              (v) => setState(() => _autoId = v), (v) => PreferencesService.setAutoId(v)),
        ],
      ),
    );
  }

  Widget _switchTile(String label, bool value, ValueChanged<bool> onUiChanged,
      Future<void> Function(bool) persist) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          ),
          Switch(
            value: value,
            activeColor: AppTheme.accent,
            onChanged: (v) {
              onUiChanged(v);
              persist(v);
            },
          ),
        ],
      ),
    );
  }

  Widget _aboutCard() {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          SectionTitle('关于', icon: Icons.info_outline),
          SizedBox(height: 10),
          Text(
            '本工具完全兼容 SaveDeck 游戏库规范：\n'
            '· 每个平台目录含一份 savedeck.toml\n'
            '· ROM 与 toml 同级，媒体位于 media/游戏名/\n'
            '· 所有修改实时写回 TOML，SaveDeck 刷新即可识别\n'
            '· 封面 box2D、视频与简介来自 ScreenScraper API',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, height: 1.8),
          ),
        ],
      ),
    );
  }

  Future<void> _pickLibrary() async {
    // Android 11+ 无“所有文件访问权限”时文件浏览器读不到共享存储，先引导授权；
    // 用户从系统设置返回后自动继续选择目录。
    final access = await ensureStorageAccessPrompt(
      context,
      isMounted: () => mounted,
    );
    if (!mounted) return;
    if (access == StorageAccessPrompt.openedSettings) {
      _pendingPick = true;
      return;
    }
    if (access != StorageAccessPrompt.granted) return;

    final root = await LibraryService.defaultRoot();
    if (!mounted) return;
    final path = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => FileBrowserScreen(initialPath: root, title: '选择游戏库总目录'),
      ),
    );
    if (path == null || !mounted) return;

    // 1. 先持久化路径，保证从系统设置授权返回后无需重新选择。
    await PreferencesService.setLibraryPath(path);
    if (!mounted) return;
    setState(() => _libraryPath = path);

    // 2. 在通知父级（会重建本页、销毁 State）之前完成授权引导，
    //    否则对话框会随 State 一起消失。
    final outcome = await ensureDirectoryAccess(
      context,
      path,
      isMounted: () => mounted,
    );
    if (!mounted) return;
    if (outcome == DirectoryAccessOutcome.awaitingSettings) {
      _showMessage('目录已保存，开启“所有文件访问权限”后返回应用会自动读取');
    }

    // 3. 再同步给主页面。
    widget.onLibraryChanged(path);
  }

  Future<void> _saveAccount() async {
    await PreferencesService.setSsUsername(_userController.text.trim());
    await PreferencesService.setSsPassword(_passwordController.text.trim());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('账号已保存')),
      );
    }
  }

  Future<void> _testConnection() async {
    setState(() => _testing = true);
    // 开发者凭据已内置，这里只需传入可选的用户账号。
    final service = ScreenscraperService(
      username: _userController.text.trim(),
      password: _passwordController.text.trim(),
      preferredLanguage: _language ?? ScreenscraperConfig.defaultLanguage,
    );
    try {
      // 采用 ssuserInfos.php 做凭据校验（与 neostation-frontend 一致）。
      final info = await service.verifyCredentials(
        _userController.text.trim(),
        _passwordController.text.trim(),
      );
      final user = info['response']?['ssuser'] as Map?;
      final level = user?['niveau']?.toString();
      final requestsToday = user?['requeststoday']?.toString();
      if (mounted) {
        _showMessage(
          level == null
              ? '连接成功，凭据有效'
              : '连接成功，凭据有效（等级 $level，今日请求 $requestsToday）',
        );
      }
    } catch (e) {
      if (!mounted) return;
      // 附加脱敏的实际请求与原始响应，便于判断是参数还是凭据问题。
      var detail = e.toString();
      try {
        final diag = await service.diagnose(
          _userController.text.trim(),
          _passwordController.text.trim(),
        );
        detail += '\n\n--- 请求诊断 ---\n'
            'URL: ${diag['url']}\n'
            '状态码: ${diag['status']}\n'
            '响应: ${diag['body']}';
      } catch (_) {}
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppTheme.surface,
          title: const Text('连接失败',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 17)),
          content: SingleChildScrollView(
            child: SelectableText(detail,
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 13, height: 1.6)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}
