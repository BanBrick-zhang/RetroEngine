import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../models/library.dart';
import '../models/resource_fields.dart';
import '../models/scrape_options.dart';
import '../services/background_scrape_service.dart';
import '../services/library_service.dart';
import '../services/preferences_service.dart';
import '../services/screenscraper_service.dart';
import '../services/toml_service.dart';
import '../services/translation_service.dart';
import '../theme.dart';
import 'app_toast.dart';
import 'translation_dialog.dart';

/// 编辑弹窗的关闭结果。
enum GameEditOutcome {
  /// 已保存到 savedeck.toml。
  saved,

  /// 已删除该游戏条目。
  deleted,

  /// 未做任何修改。
  cancelled,
}

class _ManualSearchResult {
  final String query;
  final ScrapeOptions options;

  /// 通过「翻译」得到并用于搜索的英文名；搜刮前需确认是否应用于游戏名。
  final String? translatedName;

  const _ManualSearchResult(this.query, this.options, this.translatedName);
}

/// 游戏编辑弹窗：承载全部可编辑内容（基本信息、简介、媒体资源路径、搜刮与删除）。
///
/// 详情页只负责展示，所有写操作都集中在这里，保存后写入 savedeck.toml。
class GameEditDialog extends StatefulWidget {
  final PlatformLibrary platform;
  final GameEntry game;

  const GameEditDialog({super.key, required this.platform, required this.game});

  static Future<GameEditOutcome> show(
    BuildContext context, {
    required PlatformLibrary platform,
    required GameEntry game,
  }) async {
    final result = await showDialog<GameEditOutcome>(
      context: context,
      barrierDismissible: false,
      builder: (_) => GameEditDialog(platform: platform, game: game),
    );
    return result ?? GameEditOutcome.cancelled;
  }

  @override
  State<GameEditDialog> createState() => _GameEditDialogState();
}

class _GameEditDialogState extends State<GameEditDialog> {
  late final TextEditingController _name;
  late final TextEditingController _file;
  late final TextEditingController _sort;
  late final TextEditingController _description;
  late final TextEditingController _cover;
  late final TextEditingController _video;
  late final TextEditingController _launch;
  late final TextEditingController _id;
  late final TextEditingController _developer;
  late final TextEditingController _releaseDate;
  late final TextEditingController _wheel;
  late final TextEditingController _boxTexture;
  late final TextEditingController _box3D;
  late final TextEditingController _support2D;
  late final TextEditingController _fanart;
  late final TextEditingController _mixrbv;

  bool _busy = false;
  String? _status;
  String? _remoteStatus;
  double _remoteProgress = 0;
  String? _lastRemoteState;

  @override
  void initState() {
    super.initState();
    final game = widget.game;
    _name = TextEditingController(text: game.name);
    _file = TextEditingController(text: game.file);
    _sort = TextEditingController(text: game.sort ?? '');
    _description = TextEditingController(text: game.description ?? '');
    _cover = TextEditingController(text: game.cover ?? '');
    _video = TextEditingController(text: game.video ?? '');
    _launch = TextEditingController(text: game.launch ?? '');
    _id = TextEditingController(text: game.id ?? '');
    _developer = TextEditingController(text: game.developer ?? '');
    _releaseDate = TextEditingController(text: game.releaseDate ?? '');
    _wheel = TextEditingController(text: game.wheel ?? '');
    _boxTexture = TextEditingController(text: game.boxTexture ?? '');
    _box3D = TextEditingController(text: game.box3D ?? '');
    _support2D = TextEditingController(text: game.support2D ?? '');
    _fanart = TextEditingController(text: game.fanart ?? '');
    _mixrbv = TextEditingController(text: game.mixrbv ?? '');
    BackgroundScrapeService.instance.addListener(_onScrapeChanged);
  }

  @override
  void dispose() {
    BackgroundScrapeService.instance.removeListener(_onScrapeChanged);
    for (final c in <TextEditingController>[
      _name,
      _file,
      _sort,
      _description,
      _cover,
      _video,
      _launch,
      _id,
      _developer,
      _releaseDate,
      _wheel,
      _boxTexture,
      _box3D,
      _support2D,
      _fanart,
      _mixrbv,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// 监听当前游戏的后台下载进度，完成后把结果同步回输入框。
  void _onScrapeChanged() {
    if (!mounted) return;
    final snapshot = BackgroundScrapeService.instance.status;
    final key = '${widget.platform.directory}/${widget.game.file}';
    final state = snapshot.statuses[key];
    if (state == null) return;
    final progress = snapshot.progresses[key] ?? 0;
    final finished = state == '已完成' || state.startsWith('失败');
    final previous = _lastRemoteState;
    if (state == previous && progress == _remoteProgress && !finished) return;
    _lastRemoteState = state;
    setState(() {
      _remoteStatus = state;
      _remoteProgress = progress;
    });
    if (finished && previous != state) {
      final index = _gameIndex;
      if (index >= 0) _syncControllers(widget.platform.games[index]);
    }
  }

  Future<ScreenscraperService> _service() async {
    final username = await PreferencesService.ssUsername;
    final password = await PreferencesService.ssPassword;
    final language = await PreferencesService.language;
    return ScreenscraperService(
      username: username,
      password: password,
      preferredLanguage: language,
    );
  }

  String get _romPathHint =>
      _file.text.trim().isEmpty ? '（未填写文件）' : _file.text.trim();

  /// 在库中定位当前游戏，优先用稳定的 UUID，其次退回文件路径。
  int get _gameIndex {
    final games = widget.platform.games;
    final id = widget.game.id;
    if (id != null && id.isNotEmpty) {
      final byId = games.indexWhere((g) => g.id == id);
      if (byId >= 0) return byId;
    }
    return games.indexWhere((g) => g.file == widget.game.file);
  }

  GameEntry _currentGame() {
    return widget.game.copyWith(
      name: _name.text.trim(),
      file: _file.text.trim(),
      sort: _sort.text.trim().isEmpty ? null : _sort.text.trim(),
      clearSort: _sort.text.trim().isEmpty,
      id: _id.text.trim().isEmpty ? null : _id.text.trim(),
      description: _description.text.trim().isEmpty ? null : _description.text,
      clearDescription: _description.text.trim().isEmpty,
      cover: _cover.text.trim().isEmpty ? null : _cover.text.trim(),
      clearCover: _cover.text.trim().isEmpty,
      video: _video.text.trim().isEmpty ? null : _video.text.trim(),
      clearVideo: _video.text.trim().isEmpty,
      launch: _launch.text.trim().isEmpty ? null : _launch.text.trim(),
      clearLaunch: _launch.text.trim().isEmpty,
      developer: _developer.text.trim().isEmpty ? null : _developer.text.trim(),
      clearDeveloper: _developer.text.trim().isEmpty,
      releaseDate:
          _releaseDate.text.trim().isEmpty ? null : _releaseDate.text.trim(),
      clearReleaseDate: _releaseDate.text.trim().isEmpty,
      wheel: _emptyToNull(_wheel.text),
      clearWheel: _wheel.text.trim().isEmpty,
      boxTexture: _emptyToNull(_boxTexture.text),
      clearBoxTexture: _boxTexture.text.trim().isEmpty,
      box3D: _emptyToNull(_box3D.text),
      clearBox3D: _box3D.text.trim().isEmpty,
      support2D: _emptyToNull(_support2D.text),
      clearSupport2D: _support2D.text.trim().isEmpty,
      fanart: _emptyToNull(_fanart.text),
      clearFanart: _fanart.text.trim().isEmpty,
      mixrbv: _emptyToNull(_mixrbv.text),
      clearMixrbv: _mixrbv.text.trim().isEmpty,
    );
  }

  static String? _emptyToNull(String value) =>
      value.trim().isEmpty ? null : value.trim();

  void _syncControllers(GameEntry game) {
    _name.text = game.name;
    _file.text = game.file;
    _sort.text = game.sort ?? '';
    _description.text = game.description ?? '';
    _cover.text = game.cover ?? '';
    _video.text = game.video ?? '';
    _launch.text = game.launch ?? '';
    _id.text = game.id ?? '';
    _developer.text = game.developer ?? '';
    _releaseDate.text = game.releaseDate ?? '';
    _wheel.text = game.wheel ?? '';
    _boxTexture.text = game.boxTexture ?? '';
    _box3D.text = game.box3D ?? '';
    _support2D.text = game.support2D ?? '';
    _fanart.text = game.fanart ?? '';
    _mixrbv.text = game.mixrbv ?? '';
  }

  Future<void> _save() async {
    var updated = _currentGame();
    final index = _gameIndex;
    if (index < 0) {
      // 条目已在外部（如被删除）消失，无法保存。
      _showMessage('该游戏条目已不存在，请返回后重新扫描游戏库');
      Navigator.of(context).pop(GameEditOutcome.cancelled);
      return;
    }
    // 以库中实际条目为基准：widget.game 可能是打开弹窗时的快照，
    // 之后被后台搜刮更新过（名称/封面已变），直接用旧名会找不到媒体目录。
    final stored = index >= 0 ? widget.platform.games[index] : widget.game;
    final newName = updated.name.trim();
    if (newName.isNotEmpty && newName != stored.name) {
      try {
        updated = await LibraryService.syncGameName(
          widget.platform,
          updated,
          newName,
          renameRom: await PreferencesService.renameRomOnSave,
          renameMedia: await PreferencesService.renameMediaOnSave,
        );
      } catch (e) {
        if (mounted) _showMessage('同步 ROM / 媒体文件名失败：$e');
        return;
      }
    }
    widget.platform.games[index] = updated;
    // 排序值改变后同步调整 [[games]] 在 TOML 中的先后位置。
    LibraryService.reorderGamesBySort(widget.platform);
    await TomlService.save(widget.platform);
    if (mounted) Navigator.of(context).pop(GameEditOutcome.saved);
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('删除游戏',
            style: TextStyle(color: AppTheme.textPrimary)),
        content: const Text('将从 savedeck.toml 中移除该条目，媒体文件也会一并删除（ROM 保留）。',
            style: TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除', style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final index = _gameIndex;
    if (index >= 0) {
      final removed = widget.platform.games.removeAt(index);
      await LibraryService.removeMedia(widget.platform, removed.name);
    }
    await TomlService.save(widget.platform);
    if (mounted) Navigator.of(context).pop(GameEditOutcome.deleted);
  }

  /// 按类型删除媒体资源，并同步清空 TOML 中对应字段。
  Future<void> _deleteMedia() async {
    var cover = true;
    var video = true;
    var description = true;
    var resources = true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppTheme.surface,
          title: const Text('删除媒体资源',
              style: TextStyle(color: AppTheme.textPrimary)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('选择要删除的内容：',
                    style:
                        TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  activeColor: AppTheme.accent,
                  title: const Text('封面图片',
                      style:
                          TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
                  value: cover,
                  onChanged: (v) => setDialogState(() => cover = v ?? true),
                ),
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  activeColor: AppTheme.accent,
                  title: const Text('游戏视频',
                      style:
                          TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
                  value: video,
                  onChanged: (v) => setDialogState(() => video = v ?? true),
                ),
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  activeColor: AppTheme.accent,
                  title: const Text('其他图片资源（wheel/fanart 等）',
                      style:
                          TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
                  value: resources,
                  onChanged: (v) => setDialogState(() => resources = v ?? true),
                ),
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  activeColor: AppTheme.accent,
                  title: const Text('游戏简介',
                      style:
                          TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
                  value: description,
                  onChanged: (v) => setDialogState(() => description = v ?? true),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消')),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('删除',
                  style: TextStyle(color: AppTheme.danger)),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    if (!cover && !video && !description && !resources) {
      _showMessage('请至少选择一项要删除的内容');
      return;
    }

    final index = _gameIndex;
    if (index >= 0 && (cover || video || resources)) {
      await LibraryService.deleteMediaFiles(
        widget.platform,
        widget.platform.games[index].name,
        cover: cover,
        video: video,
        resources: resources,
      );
    }
    if (index >= 0) {
      widget.platform.games[index] = widget.platform.games[index].copyWith(
        clearCover: cover,
        clearVideo: video,
        clearDescription: description,
        clearWheel: resources,
        clearBoxTexture: resources,
        clearBox3D: resources,
        clearSupport2D: resources,
        clearFanart: resources,
        clearMixrbv: resources,
      );
    }
    widget.platform.hasToml = true;
    await TomlService.save(widget.platform);
    if (!mounted) return;
    if (index >= 0 && index < widget.platform.games.length) {
      setState(() => _syncControllers(widget.platform.games[index]));
    }
    _showMessage('所选媒体内容已删除，点击保存写入 savedeck.toml');
  }

  void _showMessage(String message) {
    if (!mounted) return;
    AppToast.show(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final landscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    return Dialog(
      backgroundColor: AppTheme.surface,
      insetPadding: EdgeInsets.symmetric(
        horizontal: landscape ? 24 : 16,
        vertical: landscape ? 10 : 16,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: landscape ? 1080 : 720,
          maxHeight: size.height * (landscape ? 0.96 : 0.9),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(),
            const Divider(height: 1),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const padding = EdgeInsets.fromLTRB(16, 12, 16, 12);
                  // 双列布局：宽度足够时把基本信息与媒体资源并排，减少纵向滚动。
                  final twoColumn = constraints.maxWidth >= 620;
                  if (!twoColumn) {
                    return SingleChildScrollView(
                      padding: padding,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildScrapeProgress(),
                          ..._basicFields(),
                          const SizedBox(height: 8),
                          ..._mediaFields(),
                        ],
                      ),
                    );
                  }
                  return SingleChildScrollView(
                    padding: padding,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildScrapeProgress(),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: _basicFields(),
                              ),
                            ),
                            const SizedBox(width: 22),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: _mediaFields(),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: _busy ? null : _delete,
                    icon: const Icon(Icons.delete_outline,
                        size: 16, color: AppTheme.danger),
                    label: const Text('删除游戏',
                        style: TextStyle(color: AppTheme.danger, fontSize: 13)),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () =>
                        Navigator.of(context).pop(GameEditOutcome.cancelled),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 6),
                  FilledButton.icon(
                    onPressed: _busy ? null : _save,
                    icon: const Icon(Icons.save_outlined, size: 18),
                    label: const Text('保存'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 顶部标题栏：标题 + 当前 ROM + 常用操作（手动搜刮、删除媒体）。
  /// 窄屏下搜索按钮退化为图标，避免标题被挤没。
  Widget _header() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 480;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          child: Row(
            children: [
              const Icon(Icons.edit_note, size: 20, color: AppTheme.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '编辑游戏',
                      style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600),
                    ),
                    Text(
                      _romPathHint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 11),
                    ),
                  ],
                ),
              ),
              if (compact)
                IconButton(
                  tooltip: '手动搜刮',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.search, size: 20),
                  onPressed: _busy ? null : _showManualSearch,
                )
              else
                FilledButton.icon(
                  onPressed: _busy ? null : _showManualSearch,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 34),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  icon: const Icon(Icons.search, size: 16),
                  label: const Text('手动搜刮'),
                ),
              IconButton(
                tooltip: '删除媒体资源',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.delete_sweep_outlined, size: 20),
                onPressed: _busy ? null : _deleteMedia,
              ),
              IconButton(
                tooltip: '关闭',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, size: 20),
                onPressed: () =>
                    Navigator.of(context).pop(GameEditOutcome.cancelled),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 左列：基本信息与简介。
  List<Widget> _basicFields() => [
        _sectionTitle('基本信息'),
        _field('游戏名称', _name,
            icon: Icons.title_outlined,
            trailing: _translateButton(
              tooltip: '翻译名称（含中文译英，否则译中）',
              onPressed: _busy
                  ? null
                  : () =>
                      _translateField(_name, title: '翻译名称', maxLines: 2),
            )),
        _field('ROM 文件（相对路径）', _file, icon: Icons.folder_outlined),
        _field('排序', _sort, icon: Icons.sort_outlined),
        _field('开发商（developpeur）', _developer,
            icon: Icons.business_outlined),
        _field('发售日期（dates）', _releaseDate, icon: Icons.event_outlined),
        _field('启动指令', _launch, icon: Icons.terminal_outlined),
        _field('ID（UUID）', _id, icon: Icons.fingerprint_outlined),
        const SizedBox(height: 6),
        _sectionTitle('游戏简介',
            trailing: _translateButton(
              tooltip: '翻译为中文',
              onPressed: _busy
                  ? null
                  : () => _translateField(_description,
                      forceChinese: true, title: '翻译简介', maxLines: 10),
            )),
        TextField(
          controller: _description,
          maxLines: 6,
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
          decoration: const InputDecoration(hintText: '搜刮或手动填写游戏简介…'),
        ),
      ];

  /// 右列：封面、视频与其他资源路径。
  List<Widget> _mediaFields() => [
        _sectionTitle('媒体资源'),
        const Text(
          '路径相对游戏库的平台目录，例如 media/游戏名/cover-<UUID>.webp；留空表示不使用该资源。'
          '可点击顶部「手动搜刮」自动填写。',
          style:
              TextStyle(color: AppTheme.textSecondary, fontSize: 11, height: 1.6),
        ),
        const SizedBox(height: 12),
        _field('封面路径（cover / box2D）', _cover,
            icon: Icons.image_outlined),
        _field('视频路径（video）', _video, icon: Icons.movie_outlined),
        for (final tag in GameResourceTags.tags)
          _field('${ResourceFields.labelOf(tag)} 路径',
              _resourceControllers[tag]!,
              icon: _resourceIcons[tag]),
      ];

  Widget _sectionTitle(String title, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SectionTitle(title, trailing: trailing),
    );
  }

  /// 当前游戏的后台搜刮进度：阶段文字 + 真实下载百分比。
  Widget _buildScrapeProgress() {
    final state = _remoteStatus ?? (_busy ? _status : null);
    if (state == null) return const SizedBox.shrink();
    final failed = state.startsWith('失败');
    final done = state == '已完成';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.subtleFill,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  failed
                      ? Icons.error_outline
                      : (done ? Icons.check_circle_outline : Icons.download),
                  size: 15,
                  color: failed
                      ? AppTheme.danger
                      : (done ? AppTheme.success : AppTheme.accent),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    done ? '后台下载完成，资料已更新' : state,
                    style: TextStyle(
                      color: failed ? AppTheme.danger : AppTheme.textPrimary,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (!done && !failed) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: _remoteProgress > 0 ? _remoteProgress : null,
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

  static const Map<String, IconData> _resourceIcons = <String, IconData>{
    'wheel': Icons.view_carousel_outlined,
    'box-texture': Icons.inventory_2_outlined,
    'box-3D': Icons.view_in_ar_outlined,
    'support-2D': Icons.sd_card_outlined,
    'fanart': Icons.palette_outlined,
    'mixrbv': Icons.photo_library_outlined,
  };

  /// TOML 标签 → 对应路径输入框。
  Map<String, TextEditingController> get _resourceControllers =>
      <String, TextEditingController>{
        'wheel': _wheel,
        'box-texture': _boxTexture,
        'box-3D': _box3D,
        'support-2D': _support2D,
        'fanart': _fanart,
        'mixrbv': _mixrbv,
      };

  Widget _field(
    String label,
    TextEditingController controller, {
    IconData? icon,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          labelStyle:
              const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          prefixIcon: icon == null
              ? null
              : Icon(icon, size: 18, color: AppTheme.textSecondary),
          suffixIcon: trailing,
        ),
      ),
    );
  }

  Widget _translateButton({
    required VoidCallback? onPressed,
    String tooltip = '翻译',
  }) {
    return IconButton(
      tooltip: tooltip,
      iconSize: 18,
      visualDensity: VisualDensity.compact,
      color: AppTheme.textSecondary,
      icon: const Icon(Icons.translate),
      onPressed: onPressed,
    );
  }

  /// 翻译指定输入框的内容，结果以弹窗展示，用户确认并（可修改后）应用才写回。
  ///
  /// [forceChinese] 为 true 时始终译为中文（用于简介）；否则按内容自动判断方向。
  Future<void> _translateField(
    TextEditingController controller, {
    bool forceChinese = false,
    String title = '翻译结果',
    int maxLines = 3,
  }) async {
    final text = controller.text.trim();
    if (text.isEmpty) {
      _showMessage('没有可翻译的内容');
      return;
    }

    final toChinese = forceChinese || !TranslationService.containsChinese(text);
    setState(() {
      _busy = true;
      _status = toChinese ? '正在翻译为中文…' : '正在翻译为英文…';
    });

    try {
      final translated = toChinese
          ? await TranslationService.toChinese(text)
          : await TranslationService.toEnglish(text);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = null;
      });

      // 先预览再应用：取消则保留原文，应用则写入（可在弹窗内修改）。
      final applied = await showTranslationResultDialog(
        context,
        original: text,
        translated: translated,
        title: title,
        directionLabel: toChinese ? '译文：中文' : '译文：英文',
        maxLines: maxLines,
      );
      if (!mounted || applied == null || applied.isEmpty) return;
      controller.text = applied;
      _showMessage('已应用翻译，可继续修改后保存');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = null;
      });
      _showMessage('翻译失败：$e');
    }
  }

  Future<void> _scrape({
    required String manualQuery,
    ScrapeOptions? options,
    String? translatedName,
  }) async {
    final romPath = p.join(widget.platform.directory, _file.text.trim());
    if (!await File(romPath).exists()) {
      _showMessage('ROM 文件不存在：$_romPathHint');
      return;
    }

    setState(() {
      _busy = true;
      _status = '正在搜索：$manualQuery';
    });

    try {
      final service = await _service();
      final systemId = PlatformCatalog.ssIdFor(widget.platform.platform);
      final candidates = await service.searchByName(manualQuery, systemId);

      if (!mounted) return;
      setState(() => _busy = false);

      if (candidates.isEmpty) {
        _showMessage('没有找到匹配的游戏，请尝试手动搜索');
        return;
      }
      // 搜索结果全部展示，由用户手动选择要使用的条目。
      _showCandidates(candidates, options, translatedName);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = null;
        });
        _showMessage('搜刮失败：$e');
      }
    }
  }

  /// 搜刮前确认是否把翻译后的英文名写为游戏名称（默认不应用）。
  Future<bool> _confirmTranslatedName({
    required String translatedName,
    required String currentName,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('应用翻译后的名称？',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 17)),
        content: Text(
          '搜索使用的英文名：$translatedName\n'
          '当前游戏名称：$currentName\n\n'
          '默认保留当前名称。',
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('不应用'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('应用'),
          ),
        ],
      ),
    );
    // 点击遮罩或返回键视为「不应用」。
    return result ?? false;
  }

  /// 选定候选后交给后台队列下载，弹窗不阻塞、不弹遮罩。
  Future<void> _apply(
    ScrapeCandidate candidate,
    ScrapeOptions? options,
    String? translatedName,
  ) async {
    final currentName = _currentGame().name;
    var applyTranslatedName = false;
    if (translatedName != null &&
        translatedName.isNotEmpty &&
        translatedName != currentName) {
      applyTranslatedName = await _confirmTranslatedName(
        translatedName: translatedName,
        currentName: currentName,
      );
      if (!mounted) return;
    }

    // 未在手动搜索弹窗中单独选择时，使用设置页保存的搜刮内容。
    final effective =
        options ?? ScrapeOptions.of(await PreferencesService.scrapeFields);

    BackgroundScrapeService.instance.enqueueCandidate(
      platform: widget.platform,
      game: _currentGame(),
      candidate: candidate,
      systemId: PlatformCatalog.ssIdFor(widget.platform.platform),
      options: effective,
      // 使用过翻译名但选择「不应用」时，保留原游戏名。
      renameGame: translatedName == null || applyTranslatedName,
      nameOverride: applyTranslatedName ? translatedName : null,
    );
    if (!mounted) return;
    setState(() {
      _remoteStatus = '排队中…';
      _remoteProgress = 0;
    });
    _showMessage('已提交到后台下载，进度显示在弹窗顶部');
  }

  void _showCandidates(
    List<ScrapeCandidate> candidates,
    ScrapeOptions? options,
    String? translatedName,
  ) {
    // 仅用于辅助识别结果的译名缓存，不写入游戏库；保存前可在编辑弹窗修改。
    final translations = <String, String>{};
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('选择匹配的游戏（共 ${candidates.length} 条）',
                    style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600)),
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: candidates.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = candidates[index];
                    final translated = translations[item.gameId];
                    return ListTile(
                      title: Text(item.name,
                          style:
                              const TextStyle(color: AppTheme.textPrimary)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            [item.region, item.systemName]
                                .where((e) => e != null)
                                .join(' · '),
                            style: const TextStyle(
                                color: AppTheme.textSecondary, fontSize: 12),
                          ),
                          if (translated != null)
                            Text(translated,
                                style: const TextStyle(
                                    color: AppTheme.accent, fontSize: 12)),
                        ],
                      ),
                      trailing: IconButton(
                        tooltip: '翻译名称',
                        iconSize: 18,
                        icon: const Icon(Icons.translate),
                        onPressed: () async {
                          // 记住当前弹层路由，返回后据此判断弹层是否已被关闭。
                          final route = ModalRoute.of(sheetContext);
                          try {
                            final text = await TranslationService.autoTranslate(
                                item.name);
                            if (route != null && !route.isCurrent) return;
                            // ignore: use_build_context_synchronously
                            final applied = await showTranslationResultDialog(
                              sheetContext,
                              original: item.name,
                              translated: text,
                              title: '翻译名称',
                              directionLabel:
                                  TranslationService.containsChinese(item.name)
                                      ? '译文：英文'
                                      : '译文：中文',
                              maxLines: 2,
                            );
                            if (applied == null || applied.isEmpty) return;
                            if (route != null && !route.isCurrent) return;
                            setSheetState(
                                () => translations[item.gameId] = applied);
                          } catch (e) {
                            if (route != null && route.isCurrent) {
                              AppToast.show(
                                sheetContext,
                                '翻译失败：$e',
                                icon: Icons.error_outline,
                                color: AppTheme.danger,
                              );
                            }
                          }
                        },
                      ),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _apply(item, options, translatedName);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showManualSearch() async {
    // 勾选项默认取设置页「搜刮选项」中保存的内容。
    final preset = await PreferencesService.scrapeFields;
    if (!mounted) return;
    final controller = TextEditingController(text: _name.text);
    String? error;
    var translating = false;
    final selected = <String>{...preset};
    // 记录搜索框内容是否来自「翻译」，用于搜刮前询问是否应用译名。
    String? translatedName;

    final result = await showDialog<_ManualSearchResult>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppTheme.surface,
          title: const Text('按名称搜索',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 17)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: const InputDecoration(hintText: '输入游戏名称'),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: translating
                          ? null
                          : () async {
                              final text = controller.text.trim();
                              if (text.isEmpty) return;
                              final route = ModalRoute.of(context);
                              setDialogState(() {
                                translating = true;
                                error = null;
                              });
                              try {
                                final translated =
                                    await TranslationService.autoTranslate(text);
                                if (route != null && !route.isCurrent) return;
                                if (!mounted) return;
                                // 弹窗确认（可修改）后再写回输入框。
                                final applied =
                                    await showTranslationResultDialog(
                                  context,
                                  original: text,
                                  translated: translated,
                                  title: '翻译搜索结果',
                                  directionLabel:
                                      TranslationService.containsChinese(text)
                                          ? '译文：英文'
                                          : '译文：中文',
                                  maxLines: 2,
                                );
                                if (applied != null && applied.isNotEmpty) {
                                  controller.text = applied;
                                  translatedName = applied;
                                }
                              } catch (e) {
                                error = e.toString();
                              } finally {
                                if (route == null || route.isCurrent) {
                                  setDialogState(() => translating = false);
                                }
                              }
                            },
                      icon: translating
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: AppTheme.accent),
                            )
                          : const Icon(Icons.translate, size: 16),
                      label: const Text('翻译'),
                    ),
                    const Expanded(
                      child: Text('含中文译英，否则译中',
                          style: TextStyle(
                              color: AppTheme.textSecondary, fontSize: 11)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text('选择要搜刮的内容',
                    style: TextStyle(
                        color: AppTheme.textSecondary, fontSize: 12)),
                ...ResourceFields.all.map(
                  (field) => CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    activeColor: AppTheme.accent,
                    title: Text(ResourceFields.labelOf(field),
                        style: const TextStyle(
                            color: AppTheme.textPrimary, fontSize: 13)),
                    value: selected.contains(field),
                    onChanged: (v) => setDialogState(() {
                      if (v == true) {
                        selected.add(field);
                      } else {
                        selected.remove(field);
                      }
                    }),
                  ),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(error!,
                        style: const TextStyle(
                            color: AppTheme.danger, fontSize: 12)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('取消')),
            TextButton(
              onPressed: () {
                final query = controller.text.trim();
                if (query.isEmpty) return;
                if (selected.isEmpty) {
                  setDialogState(() => error = '请至少选择一项要搜刮的内容');
                  return;
                }
                // 只有翻译出英文名时才在选定结果后询问是否应用为游戏名。
                final translated = translatedName != null &&
                        !TranslationService.containsChinese(query)
                    ? query
                    : null;
                Navigator.pop(
                  dialogContext,
                  _ManualSearchResult(
                    query,
                    ScrapeOptions.of(selected),
                    translated,
                  ),
                );
              },
              child: const Text('搜索'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || result == null) return;
    await _scrape(
      manualQuery: result.query,
      options: result.options,
      translatedName: result.translatedName,
    );
  }
}
