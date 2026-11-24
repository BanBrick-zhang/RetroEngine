import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:video_player/video_player.dart';

import '../models/library.dart';
import '../models/scrape_options.dart';
import '../services/background_scrape_service.dart';
import '../services/library_service.dart';
import '../services/preferences_service.dart';
import '../services/screenscraper_service.dart';
import '../services/toml_service.dart';
import '../services/translation_service.dart';
import '../theme.dart';

class _ManualSearchResult {
  final String query;
  final ScrapeOptions options;

  const _ManualSearchResult(this.query, this.options);
}

class GameDetailScreen extends StatefulWidget {
  final PlatformLibrary platform;
  final GameEntry game;

  const GameDetailScreen({super.key, required this.platform, required this.game});

  @override
  State<GameDetailScreen> createState() => _GameDetailScreenState();
}

class _GameDetailScreenState extends State<GameDetailScreen> {
  late final TextEditingController _name;
  late final TextEditingController _file;
  late final TextEditingController _sort;
  late final TextEditingController _description;
  late final TextEditingController _cover;
  late final TextEditingController _video;
  late final TextEditingController _launch;
  late final TextEditingController _id;

  bool _busy = false;
  String? _status;
  String? _remoteStatus;
  double _remoteProgress = 0;
  String? _lastRemoteState;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.game.name);
    _file = TextEditingController(text: widget.game.file);
    _sort = TextEditingController(text: widget.game.sort ?? '');
    _description = TextEditingController(text: widget.game.description ?? '');
    _cover = TextEditingController(text: widget.game.cover ?? '');
    _video = TextEditingController(text: widget.game.video ?? '');
    _launch = TextEditingController(text: widget.game.launch ?? '');
    _id = TextEditingController(text: widget.game.id ?? '');
    BackgroundScrapeService.instance.addListener(_onScrapeChanged);
  }

  @override
  void dispose() {
    BackgroundScrapeService.instance.removeListener(_onScrapeChanged);
    for (final c in [_name, _file, _sort, _description, _cover, _video, _launch, _id]) {
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
      final index = widget.platform.games
          .indexWhere((g) => g.file == widget.game.file);
      if (index >= 0) _syncControllers(widget.platform.games[index]);
    }
  }

  Future<ScreenscraperService> _service() async {
    final username = await PreferencesService.ssUsername;
    final password = await PreferencesService.ssPassword;
    final language = await PreferencesService.language;
    final devId = await PreferencesService.ssDevId;
    final devPassword = await PreferencesService.ssDevPassword;
    return ScreenscraperService(
      username: username,
      password: password,
      preferredLanguage: language,
      devId: devId,
      devPassword: devPassword,
    );
  }

  Future<void> _scrape({
    required String manualQuery,
    ScrapeOptions? options,
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
      final List<ScrapeCandidate> candidates;

      candidates = await service.searchByName(manualQuery, systemId);

      if (!mounted) return;
      setState(() => _busy = false);

      if (candidates.isEmpty) {
        _showMessage('没有找到匹配的游戏，请尝试手动搜索');
        return;
      }
      // 搜索结果全部展示，由用户手动选择要使用的条目。
      _showCandidates(candidates, options);
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

  String get _romPathHint => _file.text.trim().isEmpty ? '（未填写文件）' : _file.text.trim();

  /// 选定候选后交给后台队列下载，本页不阻塞、不弹遮罩。
  Future<void> _apply(
    ScrapeCandidate candidate,
    ScrapeOptions? options,
  ) async {
    final cover =
        options?.downloadCover ?? await PreferencesService.downloadCover;
    final video =
        options?.downloadVideo ?? await PreferencesService.downloadVideo;
    final overwrite = options?.overwriteDescription ??
        await PreferencesService.overwriteDescription;

    BackgroundScrapeService.instance.enqueueCandidate(
      platform: widget.platform,
      game: _currentGame(),
      candidate: candidate,
      systemId: PlatformCatalog.ssIdFor(widget.platform.platform),
      options: ScrapeOptions(
        downloadCover: cover,
        downloadVideo: video,
        overwriteDescription: overwrite,
      ),
    );
    if (!mounted) return;
    setState(() {
      _remoteStatus = '排队中…';
      _remoteProgress = 0;
    });
    _showMessage('已提交到后台下载，可在当前页面查看进度');
  }

  void _showCandidates(
    List<ScrapeCandidate> candidates,
    ScrapeOptions? options,
  ) {
    // 仅用于辅助识别结果的译名缓存，不写入游戏库；保存前可在详情页修改。
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
                          style: const TextStyle(color: AppTheme.textPrimary)),
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
                          try {
                            final text = await TranslationService.autoTranslate(
                                item.name);
                            setSheetState(
                                () => translations[item.gameId] = text);
                          } catch (e) {
                            ScaffoldMessenger.of(sheetContext).showSnackBar(
                              SnackBar(content: Text('翻译失败：$e')),
                            );
                          }
                        },
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        _apply(item, options);
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
    );
  }

  void _syncControllers(GameEntry game) {
    _name.text = game.name;
    _file.text = game.file;
    _sort.text = game.sort ?? '';
    _description.text = game.description ?? '';
    _cover.text = game.cover ?? '';
    _video.text = game.video ?? '';
    _launch.text = game.launch ?? '';
    _id.text = game.id ?? '';
  }

  Future<void> _save() async {
    var updated = _currentGame();
    final index = widget.platform.games.indexWhere((g) => g.file == widget.game.file);
    final newName = updated.name.trim();
    if (newName.isNotEmpty &&
        newName != widget.game.name &&
        await PreferencesService.renameRomOnSave) {
      try {
        final renamed = await LibraryService.renameRomFile(
          widget.platform,
          widget.game,
          newName,
        );
        if (renamed != widget.game.file) {
          updated = updated.copyWith(file: renamed);
        }
      } catch (e) {
        if (mounted) _showMessage('ROM 重命名失败：$e');
        return;
      }
    }
    if (newName.isNotEmpty &&
        newName != widget.game.name &&
        await PreferencesService.renameMediaOnSave) {
      try {
        updated = await LibraryService.renameMediaDirectory(
          widget.platform,
          updated,
          widget.game.name,
          newName,
        );
      } catch (e) {
        if (mounted) _showMessage('媒体目录重命名失败：$e');
        return;
      }
    }
    if (index >= 0) widget.platform.games[index] = updated;
    await TomlService.save(widget.platform);
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('删除游戏', style: TextStyle(color: AppTheme.textPrimary)),
        content: const Text('将从 savedeck.toml 中移除该条目，媒体文件也会一并删除（ROM 保留）。',
            style: TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除', style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    widget.platform.games.removeWhere((g) => g.file == widget.game.file);
    await LibraryService.removeMedia(widget.platform, widget.game.name);
    await TomlService.save(widget.platform);
    if (mounted) Navigator.of(context).pop(true);
  }

  /// 按类型删除媒体资源，并同步清空 TOML 中对应字段。
  Future<void> _deleteMedia() async {
    var cover = true;
    var video = true;
    var description = true;
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
                    style: TextStyle(
                        color: AppTheme.textSecondary, fontSize: 12)),
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  activeColor: AppTheme.accent,
                  title: const Text('封面图片',
                      style: TextStyle(
                          color: AppTheme.textPrimary, fontSize: 13)),
                  value: cover,
                  onChanged: (v) => setDialogState(() => cover = v ?? true),
                ),
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  activeColor: AppTheme.accent,
                  title: const Text('游戏视频',
                      style: TextStyle(
                          color: AppTheme.textPrimary, fontSize: 13)),
                  value: video,
                  onChanged: (v) => setDialogState(() => video = v ?? true),
                ),
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  activeColor: AppTheme.accent,
                  title: const Text('游戏简介',
                      style: TextStyle(
                          color: AppTheme.textPrimary, fontSize: 13)),
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
              child: const Text('删除', style: TextStyle(color: AppTheme.danger)),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    if (!cover && !video && !description) {
      _showMessage('请至少选择一项要删除的内容');
      return;
    }

    if (cover || video) {
      await LibraryService.deleteMediaFiles(
        widget.platform,
        widget.game.name,
        cover: cover,
        video: video,
      );
    }
    final index = widget.platform.games
        .indexWhere((g) => g.file == widget.game.file);
    GameEntry? updated;
    if (index >= 0) {
      updated = widget.platform.games[index].copyWith(
        clearCover: cover,
        clearVideo: video,
        clearDescription: description,
      );
      widget.platform.games[index] = updated;
    }
    widget.platform.hasToml = true;
    await TomlService.save(widget.platform);
    if (!mounted) return;
    if (updated != null) {
      _syncControllers(updated);
    } else {
      if (cover) _cover.clear();
      if (video) _video.clear();
      if (description) _description.clear();
    }
    setState(() {});
    _showMessage('所选媒体内容已删除并保存到 savedeck.toml');
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final coverPath = _cover.text.trim().isEmpty
        ? null
        : p.join(widget.platform.directory, _cover.text.trim());
    final hasCover = coverPath != null && File(coverPath).existsSync();
    final videoPath = _video.text.trim().isEmpty
        ? null
        : p.join(widget.platform.directory, _video.text.trim());

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('编辑游戏'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '删除游戏',
            onPressed: _delete,
          ),
        ],
      ),
      body: AppTheme.backdrop(
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
              children: [
                if (!widget.platform.hasToml)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: GlassCard(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      radius: 12,
                      child: Row(
                        children: const [
                          Icon(Icons.auto_awesome_outlined, size: 17, color: AppTheme.accent),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '该平台尚未建立 savedeck.toml，搜刮或保存后会自动生成',
                              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                GlassCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: hasCover
                                ? Image.file(
                                    File(coverPath),
                                    width: 72,
                                    height: 96,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => _placeholder(),
                                  )
                                : _placeholder(),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _name.text.isEmpty ? '未命名游戏' : _name.text,
                                  style: const TextStyle(
                                      color: AppTheme.textPrimary,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${widget.platform.platform}  ·  ${_file.text}',
                                  style: const TextStyle(
                                      color: AppTheme.textSecondary, fontSize: 12),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: [
                                    TextButton.icon(
                                      onPressed: _busy ? null : _showManualSearch,
                                      icon: const Icon(Icons.search, size: 16),
                                      label: const Text('手动搜索'),
                                    ),
                                    TextButton.icon(
                                      onPressed: _busy ? null : _deleteMedia,
                                      icon: const Icon(
                                          Icons.delete_sweep_outlined,
                                          size: 16),
                                      label: const Text('删除媒体'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 560),
                          child: _VideoPreview(path: videoPath),
                        ),
                      ),
                      _buildScrapeProgress(),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                GlassCard(
                  child: Column(
                    children: [
                      _field(
                        '游戏名称',
                        _name,
                        icon: Icons.title_outlined,
                        trailing: _translateButton(
                          tooltip: '翻译名称（含中文译英，否则译中）',
                          onPressed: _busy ? null : () => _translateField(_name),
                        ),
                      ),
                      _field('ROM 文件（相对路径）', _file, icon: Icons.folder_outlined),
                      _field('排序', _sort, icon: Icons.sort_outlined),
                      _field('封面路径', _cover, icon: Icons.image_outlined),
                      _field('视频路径', _video, icon: Icons.movie_outlined),
                      _field('启动指令', _launch, icon: Icons.terminal_outlined),
                      _field('ID（UUID）', _id, icon: Icons.fingerprint_outlined),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SectionTitle(
                        '游戏简介',
                        trailing: _translateButton(
                          tooltip: '翻译为中文',
                          onPressed: _busy
                              ? null
                              : () => _translateField(_description,
                                  forceChinese: true),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _description,
                        maxLines: 6,
                        style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                        decoration: const InputDecoration(hintText: '搜刮或手动填写游戏简介…'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: FilledButton.icon(
          onPressed: _busy ? null : _save,
          icon: const Icon(Icons.save_outlined, size: 18),
          label: const Text('保存到 savedeck.toml'),
        ),
      ),
    );
  }

  /// 当前游戏的后台搜刮进度：阶段文字 + 真实下载百分比。
  Widget _buildScrapeProgress() {
    final state = _remoteStatus ?? (_busy ? _status : null);
    if (state == null) return const SizedBox.shrink();
    final failed = state.startsWith('失败');
    final done = state == '已完成';
    return Padding(
      padding: const EdgeInsets.only(top: 12),
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

  Widget _placeholder() => Container(
        width: 72,
        height: 96,
        color: AppTheme.subtleFill,
        child: const Icon(Icons.image_outlined, color: AppTheme.textSecondary),
      );

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
          labelStyle: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          prefixIcon: icon == null ? null : Icon(icon, size: 18, color: AppTheme.textSecondary),
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

  /// 翻译指定输入框的内容，结果直接写回输入框，用户可修改后再保存。
  ///
  /// [forceChinese] 为 true 时始终译为中文（用于简介）；否则按内容自动判断方向。
  Future<void> _translateField(
    TextEditingController controller, {
    bool forceChinese = false,
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
      controller.text = translated;
      setState(() {
        _busy = false;
        _status = null;
      });
      _showMessage('翻译完成，可修改后保存');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = null;
      });
      _showMessage('翻译失败：$e');
    }
  }

  void _showManualSearch() {
    final controller = TextEditingController(text: _name.text);
    String? error;
    var translating = false;
    var cover = true;
    var video = true;
    var description = true;

    showDialog<_ManualSearchResult>(
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
                            setDialogState(() {
                              translating = true;
                              error = null;
                            });
                            try {
                              // 翻译结果写回输入框，用户可修改后再搜索。
                              final translated =
                                  await TranslationService.autoTranslate(text);
                              controller.text = translated;
                            } catch (e) {
                              error = e.toString();
                            } finally {
                              setDialogState(() => translating = false);
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
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                activeColor: AppTheme.accent,
                title: const Text('封面图片',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
                value: cover,
                onChanged: (v) => setDialogState(() => cover = v ?? true),
              ),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                activeColor: AppTheme.accent,
                title: const Text('游戏视频',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
                value: video,
                onChanged: (v) => setDialogState(() => video = v ?? true),
              ),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                activeColor: AppTheme.accent,
                title: const Text('游戏简介',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
                value: description,
                onChanged: (v) => setDialogState(() => description = v ?? true),
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
                if (!cover && !video && !description) {
                  setDialogState(() => error = '请至少选择一项要搜刮的内容');
                  return;
                }
                Navigator.pop(
                  dialogContext,
                  _ManualSearchResult(
                    query,
                    ScrapeOptions(
                      downloadCover: cover,
                      downloadVideo: video,
                      overwriteDescription: description,
                    ),
                  ),
                );
              },
              child: const Text('搜索'),
            ),
          ],
        ),
      ),
    ).then((value) {
      if (value != null && value.query.isNotEmpty) {
        _scrape(manualQuery: value.query, options: value.options);
      }
    });
  }
}

/// 详情页内嵌视频小窗：自动播本地视频，无视频时显示占位。
class _VideoPreview extends StatefulWidget {
  final String? path;

  const _VideoPreview({required this.path});

  @override
  State<_VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<_VideoPreview> {
  VideoPlayerController? _controller;
  Timer? _autoPlayTimer;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void didUpdateWidget(covariant _VideoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _autoPlayTimer?.cancel();
      _autoPlayTimer = null;
      _controller?.dispose();
      _controller = null;
      _failed = false;
      _initialize();
    }
  }

  Future<void> _initialize() async {
    final path = widget.path;
    if (path == null || path.isEmpty) return;
    final file = File(path);
    if (!file.existsSync()) return;
    final controller = VideoPlayerController.file(file);
    _controller = controller;
    try {
      await controller.initialize();
    } catch (_) {
      controller.dispose();
      if (!mounted) return;
      setState(() {
        _failed = true;
        _controller = null;
      });
      return;
    }
    if (!mounted) {
      controller.dispose();
      return;
    }
    setState(() {});

    final delay = await PreferencesService.videoAutoPlayDelay;
    if (delay <= 0 || !mounted) return;
    _autoPlayTimer = Timer(Duration(seconds: delay), () {
      if (mounted &&
          controller.value.isInitialized &&
          !controller.value.isPlaying) {
        controller.play();
      }
    });
  }

  @override
  void dispose() {
    _autoPlayTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  Widget _placeholder(String text) => Container(
        width: double.infinity,
        height: 120,
        decoration: BoxDecoration(
          color: AppTheme.subtleFill,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(Icons.movie_outlined,
                size: 26, color: AppTheme.textSecondary),
            const SizedBox(height: 6),
            Text(text,
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 12)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return _placeholder(
          _failed ? '视频无法播放' : '暂无视频（搜刮后自动显示）');
    }
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        if (!value.isInitialized) return _placeholder('视频加载中…');
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              AspectRatio(
                aspectRatio: value.aspectRatio == 0 ? 16 / 9 : value.aspectRatio,
                child: VideoPlayer(controller),
              ),
              Positioned(
                left: 8,
                bottom: 12,
                child: GestureDetector(
                  onTap: () {
                    if (value.isPlaying) {
                      controller.pause();
                    } else {
                      controller.play();
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.45),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      value.isPlaying ? Icons.pause : Icons.play_arrow,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: VideoProgressIndicator(
                  controller,
                  allowScrubbing: true,
                  colors: const VideoProgressColors(
                    playedColor: AppTheme.accent,
                    bufferedColor: AppTheme.border,
                    backgroundColor: Color(0x33FFFFFF),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
