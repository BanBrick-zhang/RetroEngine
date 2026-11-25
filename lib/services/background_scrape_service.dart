import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../models/library.dart';
import '../models/scrape_options.dart';
import 'preferences_service.dart';
import 'screenscraper_service.dart';

/// 后台搜刮队列中的一个游戏条目。
class ScrapeJob {
  final PlatformLibrary platform;
  final GameEntry game;

  /// 手动搜刮时用户选定的候选；为空则自动匹配（批量搜刮）。
  final ScrapeCandidate? candidate;
  final int? systemId;
  final ScrapeOptions options;

  const ScrapeJob({
    required this.platform,
    required this.game,
    this.candidate,
    this.systemId,
    this.options = const ScrapeOptions(),
  });

  /// 跨页面稳定标识，用于展示每个游戏的进度。
  String get key => '${platform.directory}/${game.file}';
}

/// 后台队列的当前状态快照。
class ScrapeStatus {
  final int total;
  final int completed;
  final int success;
  final int failed;
  final String currentName;
  final String message;
  final bool running;
  final Map<String, String> statuses;
  final Map<String, double> progresses;

  const ScrapeStatus({
    required this.total,
    required this.completed,
    required this.success,
    required this.failed,
    required this.currentName,
    required this.message,
    required this.running,
    required this.statuses,
    required this.progresses,
  });

  double get progress => total == 0 ? 0 : completed / total;
}

/// 应用级后台搜刮队列。
///
/// 任务提交后不依赖任何页面 State，切换 Tab 或打开其他界面时仍继续执行；
/// 通过 ChangeNotifier 广播阶段文本与下载百分比，供全局进度条和详情页订阅。
class BackgroundScrapeService extends ChangeNotifier {
  static final BackgroundScrapeService instance =
      BackgroundScrapeService._internal();

  BackgroundScrapeService._internal();

  final Queue<ScrapeJob> _queue = Queue<ScrapeJob>();
  final Map<String, String> _statuses = <String, String>{};
  final Map<String, double> _progresses = <String, double>{};

  bool _running = false;
  int _total = 0;
  int _completed = 0;
  int _success = 0;
  int _failed = 0;
  String _currentName = '';
  String _message = '';

  ScrapeStatus get status => ScrapeStatus(
        total: _total,
        completed: _completed,
        success: _success,
        failed: _failed,
        currentName: _currentName,
        message: _message,
        running: _running,
        statuses: Map<String, String>.unmodifiable(_statuses),
        progresses: Map<String, double>.unmodifiable(_progresses),
      );

  bool get isRunning => _running;

  /// 把任务追加到队列；若当前空闲则立即开始处理。
  void enqueue(List<ScrapeJob> jobs, {ScrapeOptions? options}) {
    if (jobs.isEmpty) return;
    final effective = options == null
        ? jobs
        : jobs
            .map((job) => ScrapeJob(
                  platform: job.platform,
                  game: job.game,
                  candidate: job.candidate,
                  systemId: job.systemId,
                  options: options,
                ))
            .toList();
    _queue.addAll(effective);
    _total += effective.length;
    for (final job in effective) {
      _statuses[job.key] = '排队中…';
      _progresses[job.key] = 0;
    }
    _notify();
    if (!_running) _run();
  }

  /// 手动搜刮：按用户选定的候选在后台下载，提交后立即返回。
  void enqueueCandidate({
    required PlatformLibrary platform,
    required GameEntry game,
    required ScrapeCandidate candidate,
    required ScrapeOptions options,
    int? systemId,
  }) {
    enqueue(<ScrapeJob>[
      ScrapeJob(
        platform: platform,
        game: game,
        candidate: candidate,
        systemId: systemId,
        options: options,
      ),
    ]);
  }

  /// 清除已完成的历史记录（运行中不可清除）。
  void clear() {
    if (_running) return;
    _statuses.clear();
    _progresses.clear();
    _total = 0;
    _completed = 0;
    _success = 0;
    _failed = 0;
    _currentName = '';
    _message = '';
    _notify();
  }

  Future<void> _run() async {
    _running = true;
    _message = '正在准备搜刮…';
    _notify();

    final username = await PreferencesService.ssUsername;
    final password = await PreferencesService.ssPassword;
    final language = await PreferencesService.language;
    final devId = await PreferencesService.ssDevId;
    final devPassword = await PreferencesService.ssDevPassword;

    final ScreenscraperService service;
    try {
      service = ScreenscraperService(
        username: username,
        password: password,
        preferredLanguage: language,
        devId: devId,
        devPassword: devPassword,
      );
    } catch (e) {
      // 缺少开发者凭据等致命配置错误：一次性失败掉所有排队任务。
      for (final job in _queue) {
        _statuses[job.key] = '失败：$e';
      }
      _failed += _queue.length;
      _completed += _queue.length;
      _queue.clear();
      _running = false;
      _currentName = '';
      _message = '后台搜刮未开始：$e';
      _notify();
      return;
    }

    while (_queue.isNotEmpty) {
      final job = _queue.removeFirst();
      _currentName = job.game.name.isEmpty ? job.game.file : job.game.name;
      _statuses[job.key] = '处理中…';
      _progresses[job.key] = 0;
      _message = '正在搜刮：$_currentName';
      _notify();

      void onProgress(String message) {
        _statuses[job.key] = message;
        _message = '$_currentName：$message';
        _notify();
      }

      void onDownloadProgress(int received, int? total) {
        _progresses[job.key] = (total != null && total > 0)
            ? (received / total).clamp(0.0, 1.0).toDouble()
            : 0.5;
        _notify();
      }

      try {
        final GameEntry? result;
        if (job.candidate != null) {
          result = await service.applyCandidate(
            platform: job.platform,
            game: job.game,
            candidate: job.candidate!,
            systemId: job.systemId,
            downloadCover: job.options.downloadCover,
            downloadVideo: job.options.downloadVideo,
            overwriteDescription: job.options.overwriteDescription,
            onProgress: onProgress,
            onDownloadProgress: onDownloadProgress,
          );
        } else {
          result = await service.scrapeAuto(
            platform: job.platform,
            game: job.game,
            downloadCover: job.options.downloadCover,
            downloadVideo: job.options.downloadVideo,
            overwriteDescription: job.options.overwriteDescription,
            onProgress: onProgress,
            onDownloadProgress: onDownloadProgress,
          );
        }
        if (result == null) {
          _statuses[job.key] = '失败：未找到匹配';
          _failed++;
        } else {
          _statuses[job.key] = '已完成';
          _progresses[job.key] = 1;
          _success++;
        }
      } catch (e) {
        _statuses[job.key] = '失败：$e';
        _failed++;
      }

      _completed++;
      _notify();
      // 给接口和 UI 留出喘息间隔，避免突发请求触发配额限制。
      await Future<void>.delayed(const Duration(milliseconds: 700));
    }

    _running = false;
    _currentName = '';
    _message = '后台搜刮完成：成功 $_success，失败 $_failed';
    _notify();
  }

  void _notify() => notifyListeners();
}
