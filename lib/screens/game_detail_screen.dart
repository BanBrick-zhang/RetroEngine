import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../models/library.dart';
import '../services/library_service.dart';
import '../services/preferences_service.dart';
import '../services/screenscraper_service.dart';
import '../services/toml_service.dart';
import '../theme.dart';

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
  }

  @override
  void dispose() {
    for (final c in [_name, _file, _sort, _description, _cover, _video, _launch, _id]) {
      c.dispose();
    }
    super.dispose();
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

  Future<void> _scrape({String? manualQuery}) async {
    final romPath = p.join(widget.platform.directory, _file.text.trim());
    if (!await File(romPath).exists()) {
      _showMessage('ROM 文件不存在：$_romPathHint');
      return;
    }

    setState(() {
      _busy = true;
      _status = manualQuery == null ? '正在识别游戏…' : '正在搜索：$manualQuery';
    });

    try {
      final service = await _service();
      final systemId = PlatformCatalog.ssIdFor(widget.platform.platform);
      final List<ScrapeCandidate> candidates;

      if (manualQuery != null) {
        candidates = await service.searchByName(manualQuery, systemId);
      } else {
        candidates = await service.findCandidates(
          romPath: romPath,
          gameName: _name.text.trim(),
          systemId: systemId,
        );
      }

      if (!mounted) return;
      setState(() => _busy = false);

      if (candidates.isEmpty) {
        _showMessage('没有找到匹配的游戏，请尝试手动搜索');
        return;
      }
      // 搜索结果全部展示，由用户手动选择要使用的条目。
      _showCandidates(candidates, service);
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

  Future<void> _apply(ScrapeCandidate candidate, ScreenscraperService service) async {
    setState(() {
      _busy = true;
      _status = '正在获取资料…';
    });
    try {
      final cover = await PreferencesService.downloadCover;
      final video = await PreferencesService.downloadVideo;
      final overwrite = await PreferencesService.overwriteDescription;

      final current = _currentGame();
      final updated = await service.applyCandidate(
        platform: widget.platform,
        game: current,
        candidate: candidate,
        systemId: PlatformCatalog.ssIdFor(widget.platform.platform),
        downloadCover: cover,
        downloadVideo: video,
        overwriteDescription: overwrite,
        onProgress: (message) {
          if (mounted) setState(() => _status = message);
        },
      );
      _syncControllers(updated);
      if (mounted) {
        setState(() {
          _busy = false;
          _status = '搜刮完成';
        });
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = null;
        });
        _showMessage('写入失败：$e');
      }
    }
  }

  void _showCandidates(List<ScrapeCandidate> candidates, ScreenscraperService service) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
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
                  return ListTile(
                    title: Text(item.name, style: const TextStyle(color: AppTheme.textPrimary)),
                    subtitle: Text(
                      [item.region, item.systemName].where((e) => e != null).join(' · '),
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _apply(item, service);
                    },
                  );
                },
              ),
            ),
          ],
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
    final updated = _currentGame();
    final index = widget.platform.games.indexWhere((g) => g.file == widget.game.file);
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
                  child: Row(
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
                            const SizedBox(width: 4),
                            Text(
                              '${widget.platform.platform}  ·  ${_file.text}',
                              style: const TextStyle(
                                  color: AppTheme.textSecondary, fontSize: 12),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 8),
                            FilledButton.tonalIcon(
                              onPressed: _busy ? null : () => _scrape(),
                              icon: const Icon(Icons.auto_awesome, size: 16),
                              label: const Text('一键搜刮'),
                              style: FilledButton.styleFrom(
                                foregroundColor: AppTheme.textPrimary,
                                backgroundColor: AppTheme.subtleFill,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                GlassCard(
                  child: Column(
                    children: [
                      _field('游戏名称', _name, icon: Icons.title_outlined),
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
                      const SectionTitle('游戏简介'),
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
                const SizedBox(height: 12),
                GlassCard(
                  child: Row(
                    children: [
                      const Icon(Icons.search, size: 18, color: AppTheme.textSecondary),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text('搜刮结果不理想？按名称手动搜索',
                            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                      ),
                      TextButton(
                        onPressed: _busy ? null : _showManualSearch,
                        child: const Text('手动搜索'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_busy)
              Positioned.fill(
                child: Container(
                  color: Colors.white.withOpacity(0.74),
                  child: Center(
                    child: GlassCard(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(color: AppTheme.accent),
                          const SizedBox(height: 16),
                          Text(_status ?? '处理中…',
                              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                ),
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

  Widget _placeholder() => Container(
        width: 72,
        height: 96,
        color: AppTheme.subtleFill,
        child: const Icon(Icons.image_outlined, color: AppTheme.textSecondary),
      );

  Widget _field(String label, TextEditingController controller, {IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          prefixIcon: icon == null ? null : Icon(icon, size: 18, color: AppTheme.textSecondary),
        ),
      ),
    );
  }

  void _showManualSearch() {
    final controller = TextEditingController(text: _name.text);
    showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('按名称搜索',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 17)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: const InputDecoration(hintText: '输入游戏名称'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('搜索'),
          ),
        ],
      ),
    ).then((value) {
      if (value != null && value.isNotEmpty) _scrape(manualQuery: value);
    });
  }
}
