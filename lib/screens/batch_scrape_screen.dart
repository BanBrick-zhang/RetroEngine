import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../models/library.dart';
import '../services/library_service.dart';
import '../services/preferences_service.dart';
import '../services/screenscraper_service.dart';
import '../services/toml_service.dart';
import '../theme.dart';

class BatchScrapeScreen extends StatefulWidget {
  final String? libraryPath;

  const BatchScrapeScreen({super.key, required this.libraryPath});

  @override
  State<BatchScrapeScreen> createState() => _BatchScrapeScreenState();
}

class _BatchScrapeScreenState extends State<BatchScrapeScreen>
    with WidgetsBindingObserver {
  List<PlatformLibrary> _platforms = <PlatformLibrary>[];
  int _selected = 0;
  final Set<String> _checked = <String>{};
  final Map<String, String> _status = <String, String>{};
  bool _loading = true;
  bool _running = false;
  bool _cover = true;
  bool _video = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 授权返回或切回前台时刷新，保证权限生效后能读到游戏库。
    if (state == AppLifecycleState.resumed && !_running) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final stored = await PreferencesService.libraryPath;
    final path = (stored != null && stored.isNotEmpty) ? stored : widget.libraryPath;
    if (path == null || path.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final platforms = await LibraryService.loadLibrary(path);
      if (mounted) {
        setState(() {
          _platforms = platforms;
          if (_selected >= platforms.length) _selected = 0;
          _checked.clear();
          _status.clear();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  PlatformLibrary? get _platform =>
      _platforms.isEmpty ? null : _platforms[_selected.clamp(0, _platforms.length - 1)];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('批量搜刮'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load),
        ],
      ),
      body: AppTheme.backdrop(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
            : _error != null
                ? Center(child: Text(_error!, style: const TextStyle(color: AppTheme.danger)))
                : _platforms.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(28),
                          child: Text('请先绑定游戏库并添加游戏',
                              style: TextStyle(color: AppTheme.textSecondary)),
                        ),
                      )
                    : _content(),
      ),
      floatingActionButton: _platforms.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _running || _checked.isEmpty ? null : _start,
              backgroundColor: AppTheme.accent,
              foregroundColor: Colors.white,
              icon: _running
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.background),
                    )
                  : const Icon(Icons.auto_awesome),
              label: Text(_running ? '搜刮中…' : '开始搜刮 (${_checked.length})'),
            ),
    );
  }

  Widget _content() {
    final platform = _platform!;
    return Column(
      children: [
        const SizedBox(height: 8),
        SizedBox(
          height: 42,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _platforms.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) => GlassChip(
              label: _platforms[index].platform,
              icon: _platforms[index].hasToml ? null : Icons.auto_awesome_outlined,
              selected: index == _selected,
              onTap: _running ? null : () => setState(() => _selected = index),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                _optionSwitch('封面', _cover, (v) => setState(() => _cover = v)),
                const SizedBox(width: 18),
                _optionSwitch('视频', _video, (v) => setState(() => _video = v)),
                const Spacer(),
                TextButton(
                  onPressed: _running ? null : () => setState(() {
                    _checked.clear();
                    _checked.addAll(platform.games.map((g) => g.file));
                  }),
                  child: const Text('全选'),
                ),
                TextButton(
                  onPressed: _running ? null : () => setState(() => _checked.clear()),
                  child: const Text('清空'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
            itemCount: platform.games.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (context, index) {
              final game = platform.games[index];
              final state = _status[game.file];
              return GlassCard(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                radius: 12,
                onTap: _running
                    ? null
                    : () => setState(() {
                        if (_checked.contains(game.file)) {
                          _checked.remove(game.file);
                        } else {
                          _checked.add(game.file);
                        }
                      }),
                child: Row(
                  children: [
                    Icon(
                      _checked.contains(game.file)
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 20,
                      color: _checked.contains(game.file)
                          ? AppTheme.accent
                          : AppTheme.textSecondary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(game.name.isEmpty ? p.basename(game.file) : game.name,
                              style: const TextStyle(
                                  color: AppTheme.textPrimary, fontSize: 14),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 3),
                          Text(
                            state ?? game.file,
                            style: TextStyle(
                              color: state == null
                                  ? AppTheme.textSecondary
                                  : (state.startsWith('失败')
                                      ? AppTheme.danger
                                      : AppTheme.success),
                              fontSize: 11,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    if (state == '处理中…')
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppTheme.accent),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _optionSwitch(String label, bool value, ValueChanged<bool> onChanged) {
    return Row(
      children: [
        Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
        const SizedBox(width: 4),
        Switch(
          value: value,
          onChanged: _running ? null : onChanged,
          activeColor: AppTheme.accent,
        ),
      ],
    );
  }

  Future<void> _start() async {
    final platform = _platform;
    if (platform == null || _checked.isEmpty) {
      _showMessage('请先选择要搜刮的游戏');
      return;
    }
    final username = await PreferencesService.ssUsername;
    final password = await PreferencesService.ssPassword;
    final language = await PreferencesService.language;
    final overwrite = await PreferencesService.overwriteDescription;
    final devId = await PreferencesService.ssDevId;
    final devPassword = await PreferencesService.ssDevPassword;

    setState(() => _running = true);
    final service = ScreenscraperService(
      username: username,
      password: password,
      preferredLanguage: language,
      devId: devId,
      devPassword: devPassword,
    );

    final games = platform.games.where((g) => _checked.contains(g.file)).toList();
    var success = 0;
    var failed = 0;

    for (final game in games) {
      if (!mounted) break;
      setState(() => _status[game.file] = '处理中…');
      try {
        final result = await service.scrapeAuto(
          platform: platform,
          game: game,
          downloadCover: _cover,
          downloadVideo: _video,
          overwriteDescription: overwrite,
          onProgress: (message) {
            if (mounted) setState(() => _status[game.file] = message);
          },
        );
        if (result == null) {
          setState(() => _status[game.file] = '失败：未找到匹配');
          failed++;
        } else {
          setState(() => _status[game.file] = '已完成');
          success++;
        }
      } catch (e) {
        setState(() => _status[game.file] = '失败：$e');
        failed++;
      }
      await TomlService.save(platform);
      await Future<void>.delayed(const Duration(milliseconds: 700));
    }

    if (mounted) {
      setState(() {
        _running = false;
        _checked.clear();
      });
      _showMessage('批量搜刮完成：成功 $success，失败 $failed');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
