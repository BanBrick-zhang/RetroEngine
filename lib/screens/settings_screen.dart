import 'package:flutter/material.dart';

import '../services/library_service.dart';
import '../services/preferences_service.dart';
import '../services/screenscraper_service.dart';
import '../services/version_service.dart';
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
  final _devIdController = TextEditingController();
  final _devPasswordController = TextEditingController();
  final _translateKeyController = TextEditingController();
  String? _libraryPath;
  String? _language;
  bool _cover = true;
  bool _video = true;
  bool _overwrite = true;
  bool _autoId = true;
  bool _renameRom = true;
  bool _renameMedia = true;
  bool _obscure = true;
  bool _obscureDev = true;
  bool _testing = false;
  int _videoDelay = 2;
  String _version = '加载中…';

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
    _devIdController.dispose();
    _devPasswordController.dispose();
    _translateKeyController.dispose();
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
    final devId = await PreferencesService.ssDevId;
    final devPassword = await PreferencesService.ssDevPassword;
    final language = await PreferencesService.language;
    final cover = await PreferencesService.downloadCover;
    final video = await PreferencesService.downloadVideo;
    final overwrite = await PreferencesService.overwriteDescription;
    final autoId = await PreferencesService.autoId;
    final renameRom = await PreferencesService.renameRomOnSave;
    final renameMedia = await PreferencesService.renameMediaOnSave;
    final translateKey = await PreferencesService.translateKey;
    final videoDelay = await PreferencesService.videoAutoPlayDelay;
    final version = await VersionService.load();
    if (!mounted) return;
    setState(() {
      _libraryPath = path;
      _userController.text = user ?? '';
      _passwordController.text = password ?? '';
      _devIdController.text =
          (devId == null || devId.isEmpty) ? ScreenscraperConfig.buildDevId : devId;
      _devPasswordController.text = (devPassword == null || devPassword.isEmpty)
          ? ScreenscraperConfig.buildDevPassword
          : devPassword;
      _translateKeyController.text = translateKey ?? '';
      _language = language;
      _cover = cover;
      _video = video;
      _overwrite = overwrite;
      _autoId = autoId;
      _renameRom = renameRom;
      _renameMedia = renameMedia;
      _videoDelay = videoDelay;
      _version = version;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('设置')),
      body: SafeArea(
        child: AppTheme.backdrop(
          child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
          children: [
            _libraryCard(),
            const SizedBox(height: 14),
            _accountCard(),
            const SizedBox(height: 14),
            _translateCard(),
            const SizedBox(height: 14),
            _optionsCard(),
            const SizedBox(height: 14),
            _aboutCard(),
          ],
        ),
        ),
      ),
    );
  }

  Widget _libraryCard() {
    return GlassExpansionCard(
      title: '游戏库',
      icon: Icons.folder_shared_outlined,
      children: [
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
    );
  }

  Widget _accountCard() {
    return GlassExpansionCard(
      title: 'ScreenScraper 账号',
      icon: Icons.account_circle_outlined,
      children: [
        const Text(
          '开发者凭据请自行向 ScreenScraper 申请后填写，构建时也可通过 '
          '--dart-define=SS_DEV_ID / SS_DEV_PASSWORD 注入，源码中不再内置。',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 11, height: 1.5),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _devIdController,
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
          decoration: const InputDecoration(
            labelText: '开发者 ID（devid）',
            prefixIcon: Icon(Icons.badge_outlined,
                size: 18, color: AppTheme.textSecondary),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _devPasswordController,
          obscureText: _obscureDev,
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            labelText: '开发者密码（devpassword）',
            prefixIcon: const Icon(Icons.key_outlined,
                size: 18, color: AppTheme.textSecondary),
            suffixIcon: IconButton(
              icon: Icon(_obscureDev
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined),
              onPressed: () => setState(() => _obscureDev = !_obscureDev),
            ),
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          '以下为可选的个人账号，填写后可提升每日请求配额；留空则以匿名访客身份调用。',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 11, height: 1.5),
        ),
        const SizedBox(height: 10),
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
    );
  }

  Widget _translateCard() {
    return GlassExpansionCard(
      title: '翻译',
      icon: Icons.translate,
      children: [
        const Text(
          '用于翻译游戏名与简介。请填写接口盒子（apihz.cn）用户中心的通讯密钥；'
          '开发者 ID 10021309 已内置。免费账号约 10 次/分钟，请勿频繁请求。',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 11, height: 1.5),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _translateKeyController,
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
          decoration: const InputDecoration(
            labelText: '翻译接口 KEY',
            prefixIcon: Icon(Icons.vpn_key_outlined,
                size: 18, color: AppTheme.textSecondary),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.tonal(
          onPressed: _saveTranslateKey,
          style: FilledButton.styleFrom(
            foregroundColor: AppTheme.textPrimary,
            backgroundColor: AppTheme.subtleFill,
          ),
          child: const Text('保存 KEY'),
        ),
      ],
    );
  }

  Widget _optionsCard() {
    return GlassExpansionCard(
      title: '搜刮选项',
      icon: Icons.tune,
      children: [
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
        const SizedBox(height: 8),
        Row(
          children: [
            const Icon(Icons.play_circle_outline,
                size: 18, color: AppTheme.textSecondary),
            const SizedBox(width: 10),
            const Expanded(
              child: Text('视频自动播放',
                  style: TextStyle(color: AppTheme.textPrimary, fontSize: 14)),
            ),
            DropdownButton<int>(
              value: _videoDelay,
              dropdownColor: AppTheme.surface,
              style: const TextStyle(color: AppTheme.textPrimary),
              underline: const SizedBox(),
              items: const <DropdownMenuItem<int>>[
                DropdownMenuItem(value: 0, child: Text('不自动播放')),
                DropdownMenuItem(value: 2, child: Text('2 秒后')),
                DropdownMenuItem(value: 5, child: Text('5 秒后')),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _videoDelay = value);
                PreferencesService.setVideoAutoPlayDelay(value);
              },
            ),
          ],
        ),
        _switchTile('下载 box2D 正面封面到 media/游戏名/cover.png', _cover,
            (v) => setState(() => _cover = v), (v) => PreferencesService.setDownloadCover(v)),
        _switchTile('下载游戏视频到 media/游戏名/video.mp4', _video,
            (v) => setState(() => _video = v), (v) => PreferencesService.setDownloadVideo(v)),
        _switchTile('用搜刮简介覆盖已有简介', _overwrite,
            (v) => setState(() => _overwrite = v),
            (v) => PreferencesService.setOverwriteDescription(v)),
        _switchTile('新游戏自动生成 UUID', _autoId,
            (v) => setState(() => _autoId = v), (v) => PreferencesService.setAutoId(v)),
        _switchTile('保存时按游戏名重命名 ROM 文件（保留扩展名）', _renameRom,
            (v) => setState(() => _renameRom = v),
            (v) => PreferencesService.setRenameRomOnSave(v)),
        _switchTile('保存时同步重命名 media 媒体文件夹', _renameMedia,
            (v) => setState(() => _renameMedia = v),
            (v) => PreferencesService.setRenameMediaOnSave(v)),
      ],
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
    return GlassExpansionCard(
      title: '关于',
      icon: Icons.info_outline,
      children: [
        const Text(
          '本工具完全兼容 SaveDeck 游戏库规范：\n'
          '· 每个平台目录含一份 savedeck.toml\n'
          '· ROM 与 toml 同级，媒体位于 media/游戏名/\n'
          '· 所有修改实时写回 TOML，SaveDeck 刷新即可识别\n'
          '· 封面 box2D、视频与简介来自 ScreenScraper API',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, height: 1.8),
        ),
        const SizedBox(height: 12),
        Text(
          '当前版本：$_version',
          style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600),
        ),
      ],
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
      AppPageRoute(
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
    await PreferencesService.setSsDevId(_devIdController.text.trim());
    await PreferencesService.setSsDevPassword(_devPasswordController.text.trim());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('凭据与账号已保存')),
      );
    }
  }

  Future<void> _saveTranslateKey() async {
    await PreferencesService.setTranslateKey(_translateKeyController.text.trim());
    if (mounted) {
      _showMessage('翻译 KEY 已保存');
    }
  }

  Future<void> _testConnection() async {
    // 开发者凭据优先使用设置页填写值，其次使用构建期注入值。
    final devId = _devIdController.text.trim();
    final devPassword = _devPasswordController.text.trim();
    if (devId.isEmpty || devPassword.isEmpty) {
      _showMessage('请先填写开发者 ID 与开发者密码');
      return;
    }
    setState(() => _testing = true);
    final service = ScreenscraperService(
      username: _userController.text.trim(),
      password: _passwordController.text.trim(),
      preferredLanguage: _language ?? ScreenscraperConfig.defaultLanguage,
      devId: devId,
      devPassword: devPassword,
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
