import 'package:flutter/material.dart';

import '../models/resource_fields.dart';
import '../services/library_service.dart';
import '../services/preferences_service.dart';
import '../services/screenscraper_service.dart';
import '../services/version_service.dart';
import '../theme.dart';
import '../widgets/app_toast.dart';
import '../widgets/permission_dialog.dart';
import 'file_browser_screen.dart';
import 'library_edit_screen.dart';

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
  final _translateKeyController = TextEditingController();
  String? _libraryPath;
  String? _language;
  Set<String> _scrapeFields = <String>{...ResourceFields.defaults};
  Set<String> _detailFields = <String>{...ResourceFields.defaults};
  bool _autoId = true;
  bool _renameRom = true;
  bool _renameMedia = true;
  bool _obscure = true;
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
    final language = await PreferencesService.language;
    final scrapeFields = await PreferencesService.scrapeFields;
    final detailFields = await PreferencesService.detailFields;
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
      _translateKeyController.text = translateKey ?? '';
      _language = language;
      _scrapeFields = scrapeFields;
      _detailFields = detailFields;
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
            _detailCard(),
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
        const SizedBox(height: 12),
        Material(
          color: AppTheme.subtleFill,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: _libraryPath == null ? null : _openLibraryEdit,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              child: Row(
                children: [
                  const Icon(Icons.tune, size: 18, color: AppTheme.accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '游戏库管理',
                          style: TextStyle(
                            color: _libraryPath == null
                                ? AppTheme.textSecondary
                                : AppTheme.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          '重命名、排序、添加平台、导入 ROM',
                          style: TextStyle(
                              color: AppTheme.textSecondary, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right,
                      size: 18, color: AppTheme.textSecondary),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openLibraryEdit() async {
    await Navigator.of(context).push<void>(
      AppPageRoute(builder: (_) => const LibraryEditScreen()),
    );
    if (mounted) await _load();
  }

  Widget _accountCard() {
    return GlassExpansionCard(
      title: 'ScreenScraper 账号',
      icon: Icons.account_circle_outlined,
      children: [
        Text(
          ScreenscraperConfig.hasBuildCredentials
              ? '开发者凭据已随安装包内置。以下为可选的个人账号，'
                  '填写后可提升每日请求配额；留空则以匿名访客身份调用。'
              : '当前安装包未内置开发者凭据，搜刮将不可用。请在构建时通过环境变量 '
                  'SS_DEV_ID / SS_DEV_PASSWORD（写入 android/local.properties 亦可）或 '
                  '--dart-define 注入后重新打包。\n\n'
                  '用户账号为可选，填写后可提升每日请求配额。',
          style: const TextStyle(
              color: AppTheme.textSecondary, fontSize: 11, height: 1.5),
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
        const SizedBox(height: 12),
        _sectionLabel('搜刮内容（未勾选的字段不会被下载/写入）'),
        ..._scrapeTiles(),
        const SizedBox(height: 12),
        _sectionLabel('保存'),
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

  Widget _detailCard() {
    return GlassExpansionCard(
      title: '游戏详情页设置',
      icon: Icons.dashboard_customize_outlined,
      children: [
        const Text(
          '勾选需要在游戏详情页轮播视图左侧信息栏中展示的内容；'
          '轮播视图右侧会展示全部已下载的媒体资源，未勾选的内容仍可随时在右上角「编辑」弹窗中修改。'
          '媒体文件保存为 media/游戏名/<类型>-<游戏UUID>.<扩展名>，例如 '
          'cover-fae1c5a6-dbac-419a-868d-53de1945c484.webp。',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 11, height: 1.5),
        ),
        const SizedBox(height: 8),
        ..._detailTiles(),
      ],
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: Text(
        text,
        style: const TextStyle(
          color: AppTheme.textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  List<Widget> _scrapeTiles() => ResourceFields.all
      .map((field) => _checkTile(
            field,
            checked: _scrapeFields.contains(field),
            onChanged: (value) {
              final next = <String>{..._scrapeFields};
              if (value) {
                next.add(field);
              } else {
                next.remove(field);
              }
              setState(() => _scrapeFields = next);
              PreferencesService.setScrapeFields(next);
            },
          ))
      .toList();

  List<Widget> _detailTiles() => ResourceFields.all
      .map((field) => _checkTile(
            field,
            checked: _detailFields.contains(field),
            onChanged: (value) {
              final next = <String>{..._detailFields};
              if (value) {
                next.add(field);
              } else {
                next.remove(field);
              }
              setState(() => _detailFields = next);
              PreferencesService.setDetailFields(next);
            },
          ))
      .toList();

  Widget _checkTile(String field,
      {required bool checked, required ValueChanged<bool> onChanged}) {
    return CheckboxListTile(
      value: checked,
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      activeColor: AppTheme.accent,
      title: Text(
        ResourceFields.labelOf(field),
        style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
      ),
      onChanged: (value) => onChanged(value ?? false),
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
    if (mounted) {
      AppToast.show(context, '账号已保存', icon: Icons.check_circle_outline,
          color: AppTheme.success);
    }
  }

  Future<void> _saveTranslateKey() async {
    await PreferencesService.setTranslateKey(_translateKeyController.text.trim());
    if (mounted) {
      _showMessage('翻译 KEY 已保存');
    }
  }

  Future<void> _testConnection() async {
    // 开发者凭据在构建时注入，应用内不再提供填写入口。
    if (!ScreenscraperConfig.hasBuildCredentials) {
      _showMessage('当前安装包未内置开发者凭据，请重新打包后再测试连接');
      return;
    }
    setState(() => _testing = true);
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
    if (!mounted) return;
    AppToast.show(context, message);
  }
}
