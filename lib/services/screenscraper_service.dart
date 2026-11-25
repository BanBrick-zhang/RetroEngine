import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../models/library.dart';
import 'library_service.dart';
import 'toml_service.dart';

/// ScreenScraper 开发者凭据配置。
///
/// 公开仓库不应硬编码真实凭据，凭据在**构建时**注入，二选一：
///
/// ```
/// # 1. 环境变量（或写入 android/local.properties），直接 flutter build apk 即可
/// SS_DEV_ID=<devid> SS_DEV_PASSWORD=<devpassword> flutter build apk
///
/// # 2. 命令行 --dart-define
/// flutter build apk \
///   --dart-define=SS_DEV_ID=<devid> \
///   --dart-define=SS_DEV_PASSWORD=<devpassword>
/// ```
///
/// 开发者凭据只能在构建期注入，应用内不提供填写入口；
/// 源码与版本库中不包含任何真实凭据。
class ScreenscraperConfig {
  /// 构建期注入的开发者 ID（dart-define / 构建环境变量 `SS_DEV_ID`）。
  static const String buildDevId = String.fromEnvironment('SS_DEV_ID');

  /// 构建期注入的开发者密码（dart-define / 构建环境变量 `SS_DEV_PASSWORD`）。
  static const String buildDevPassword =
      String.fromEnvironment('SS_DEV_PASSWORD');

  /// 搜刮默认语言（简介等文本优先 en）。
  static const String defaultLanguage = 'en';

  /// 是否具备可用的开发者凭据。
  static bool get hasBuildCredentials =>
      buildDevId.isNotEmpty && buildDevPassword.isNotEmpty;
}

/// ScreenScraper.fr API v2 客户端。
///
/// 开发者凭据使用构建期注入值（调用方传入值仅供测试覆盖）；
/// 用户账号为可选（填写后可提升配额），未配置时以匿名访客身份调用。
class ScreenscraperService {
  static const String host = 'api.screenscraper.fr';

  final String username;
  final String password;
  final String preferredLanguage;
  final String devIdOverride;
  final String devPasswordOverride;

  ScreenscraperService({
    String? username,
    String? password,
    this.preferredLanguage = ScreenscraperConfig.defaultLanguage,
    String? devId,
    String? devPassword,
  })  : username = username ?? '',
        password = password ?? '',
        devIdOverride = (devId == null || devId.isEmpty)
            ? ScreenscraperConfig.buildDevId
            : devId,
        devPasswordOverride = (devPassword == null || devPassword.isEmpty)
            ? ScreenscraperConfig.buildDevPassword
            : devPassword {
    if (!hasDevCredentials) {
      throw const SsException(
        '当前安装包未内置 ScreenScraper 开发者凭据。\n'
        '请在构建时通过环境变量（SS_DEV_ID / SS_DEV_PASSWORD，可写入 '
        'android/local.properties）或 --dart-define 注入后重新打包。',
      );
    }
  }

  bool get hasDevCredentials =>
      devIdOverride.isNotEmpty && devPasswordOverride.isNotEmpty;

  bool get hasUserAccount => username.isNotEmpty && password.isNotEmpty;

  /// 供测试访问的认证参数副本。
  Map<String, String> get authForTesting => Map<String, String>.from(_auth);

  /// 认证参数：开发者凭据始终携带；用户账号仅在已配置时附带，
  /// 匿名访问时携带空 ssid/sspassword 会被服务端判为无效用户。
  /// 已实测 softname 为可选参数，这里不发送。
  Map<String, String> get _auth => <String, String>{
        'devid': devIdOverride,
        'devpassword': devPasswordOverride,
        'output': 'json',
        if (hasUserAccount) 'ssid': username,
        if (hasUserAccount) 'sspassword': password,
      };

  /// 用 Uri.encodeComponent 逐项编码参数。
  ///
  /// 借鉴 neostation-frontend：Uri.https 会把空格编码为 `+`，而 ScreenScraper
  /// 文档示例使用 `%20`；若用户名/密码含空格等特殊字符，`+` 会被服务端
  /// 当作字面字符导致凭据校验失败。逐项编码可保证特殊字符完整传递。
  static Uri buildApiUrl(String endpoint, Map<String, String> params) {
    final query = params.entries
        .map((e) =>
            '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');
    return Uri.parse('https://$host/api2/$endpoint?$query');
  }

  /// 带指数退避重试的 GET（借鉴 neostation-frontend 的 ScreenscraperClient）。
  Future<http.Response> _getWithRetry(Uri uri) async {
    const maxRetries = 3;
    for (var attempt = 0; attempt < maxRetries; attempt++) {
      try {
        final response = await http
            .get(
              uri,
              headers: const <String, String>{
                'User-Agent': 'SaveDeckToolkit/1.0 (android)',
                'Accept': 'application/json',
              },
            )
            .timeout(const Duration(seconds: 40));
        // 5xx 服务端错误时重试；403/430 等直接返回由上层解析错误信息。
        if (response.statusCode >= 500 && attempt < maxRetries - 1) {
          await Future<void>.delayed(Duration(milliseconds: 500 * (attempt + 1)));
          continue;
        }
        return response;
      } on TimeoutException {
        if (attempt < maxRetries - 1) {
          await Future<void>.delayed(Duration(milliseconds: 500 * (attempt + 1)));
          continue;
        }
        rethrow;
      }
    }
    throw const SsException('请求失败');
  }

  /// 通用 GET 请求，返回解析后的 JSON。
  Future<Map<String, dynamic>> _request(
    String endpoint,
    Map<String, String> params,
  ) async {
    final query = <String, String>{..._auth, ...params};
    final uri = buildApiUrl(endpoint, query);
    final response = await _getWithRetry(uri);
    final status = response.statusCode;
    final body = response.body;

    // 借鉴 neostation-frontend 的状态码映射。
    if (status == 403 || status == 401) {
      throw const SsException(
        'ScreenScraper 拒绝访问（HTTP 403/401）：开发者凭据或用户账号无效。'
        '开发者凭据在构建时注入，请确认打包配置；用户账号可在设置中检查。',
      );
    }
    if (status == 423) {
      throw const SsException('ScreenScraper API 服务暂不可用（HTTP 423），请稍后再试');
    }
    if (status == 426) {
      throw const SsException('ScreenScraper 要求更新应用（HTTP 426）');
    }
    if (status == 429 || status == 430 || status == 431) {
      throw const SsException('ScreenScraper 请求配额已用尽，请明天再试');
    }
    if (status == 404) {
      throw const SsException('未找到该游戏（HTTP 404）');
    }

    if (body.trim().isEmpty) {
      throw const SsException('接口返回空内容');
    }
    if (body.trimLeft().startsWith('Erreur')) {
      final raw = body.trim();
      if (raw.contains('identifiants developpeur') ||
          raw.contains('identifiants développeur')) {
        throw SsException(
          'ScreenScraper 开发者凭据无效（devid/devpassword）：$raw\n'
          '请确认该开发者账号已在 ScreenScraper 后台激活，'
          '并检查构建时注入的凭据后重新打包。',
        );
      }
      if (raw.contains('identifiants utilisateurs') ||
          raw.contains('identifiants utilisateur')) {
        throw SsException(
          'ScreenScraper 用户账号无效：$raw\n请在设置中检查用户名与密码。',
        );
      }
      throw SsException(raw);
    }
    if (status != 200) {
      throw SsException('HTTP $status');
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      throw SsException('接口返回格式异常：${body.substring(0, body.length.clamp(0, 80))}');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const SsException('接口返回格式异常');
    }

    final header = decoded['header'];
    // 借鉴 neostation：必须严格为字符串 'true' 才算成功，避免非布尔值误判。
    if (header is Map && header['success']?.toString() != 'true') {
      throw SsException(header['error']?.toString() ?? '接口请求失败');
    }
    return decoded;
  }

  /// 用 ssuserInfos.php 校验 ScreenScraper 凭据（借鉴 neostation-frontend）。
  ///
  /// [username] 必须是账号用户名，而不是邮箱（ssid 只匹配用户名）。
  Future<Map<String, dynamic>> verifyCredentials(
    String username,
    String password,
  ) async {
    final params = <String, String>{
      ..._auth,
      'ssid': username,
      'sspassword': password,
    };
    final uri = buildApiUrl('ssuserInfos.php', params);
    final response = await _getWithRetry(uri);
    final body = response.body;
    if (body.trim().isEmpty) {
      throw const SsException('接口返回空内容');
    }
    if (response.statusCode == 403) {
      throw const SsException(
        '凭据校验失败：请确认用户名为 ScreenScraper 账号用户名（非邮箱），'
        '并检查用户密码；开发者凭据由构建时注入。',
      );
    }
    if (response.statusCode != 200) {
      throw SsException('HTTP ${response.statusCode}');
    }
    dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      throw const SsException('接口返回格式异常');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const SsException('接口返回格式异常');
    }
    final header = decoded['header'];
    if (header is Map && header['success']?.toString() != 'true') {
      throw SsException(header['error']?.toString() ?? '凭据校验失败');
    }
    return decoded;
  }

  /// 诊断：返回实际请求 URL（脱敏密码）与原始响应，便于确认是参数还是凭据问题。
  Future<Map<String, String>> diagnose(String username, String password) async {
    final params = <String, String>{
      ..._auth,
      'ssid': username,
      'sspassword': password,
      'recherche': 'Mario',
      'systemeid': '3',
    };
    final uri = buildApiUrl('jeuRecherche.php', params);
    final response = await _getWithRetry(uri);
    final safeUrl = uri
        .toString()
        .replaceAll('devpassword=${Uri.encodeComponent(devPasswordOverride)}',
            'devpassword=***')
        .replaceAll('sspassword=${Uri.encodeComponent(password)}',
            'sspassword=***');
    return <String, String>{
      'url': safeUrl,
      'status': response.statusCode.toString(),
      'body': response.body.length > 500
          ? '${response.body.substring(0, 500)}…'
          : response.body,
    };
  }

  /// 按名称搜索游戏（最多 30 条）。
  ///
  /// `jeuRecherche.php` 的返回项已包含 `medias` 与 `synopsis`，
  /// 因此直接解析为完整候选，选中后无需再次请求详情。
  Future<List<ScrapeCandidate>> searchByName(String query, int? systemId) async {
    if (query.trim().isEmpty) return <ScrapeCandidate>[];
    final params = <String, String>{'recherche': query.trim()};
    if (systemId != null) params['systemeid'] = systemId.toString();

    final data = await _request('jeuRecherche.php', params);
    final games = _locateList(data, const <String>['jeux', 'jeu']);
    final results = <ScrapeCandidate>[];
    for (final item in games) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      if ((map['id']?.toString() ?? '').isEmpty) continue;
      results.add(_candidateFromDetail(
        map,
        fallbackName: query.trim(),
        detailed: false,
      ));
    }
    return results;
  }

  /// 通过 ROM 校验值精确匹配；失败时返回 null，由调用方回退到名称搜索。
  Future<ScrapeCandidate?> matchByHash({
    required String filePath,
    required int systemId,
  }) async {
    if (LibraryService.isArchive(filePath)) return null;

    final params = <String, String>{
      'systemeid': systemId.toString(),
      'romtype': 'rom',
      'romnom': p.basename(filePath),
      'crc': await LibraryService.crc32(filePath),
      'md5': await LibraryService.md5(filePath),
      'sha1': await LibraryService.sha1(filePath),
      'romtaille': (await LibraryService.fileSize(filePath)).toString(),
    };

    final data = await _request('jeuInfos.php', params);
    final jeu = _locateMap(data, const <String>['jeu']);
    if (jeu == null || jeu.isEmpty) return null;
    return _candidateFromDetail(jeu);
  }

  /// 按 ScreenScraper 游戏 ID 获取完整信息（含媒体与简介）。
  Future<ScrapeCandidate?> fetchByGameId(String gameId, {int? systemId}) async {
    final params = <String, String>{'gameid': gameId};
    if (systemId != null) params['systemeid'] = systemId.toString();
    final data = await _request('jeuInfos.php', params);
    final jeu = _locateMap(data, const <String>['jeu']);
    if (jeu == null || jeu.isEmpty) return null;
    return _candidateFromDetail(jeu);
  }

  /// 按游戏名 + 平台 systemeid 搜索候选，结果全部交给用户手动选择。
  ///
  /// 搜索失败或结果为空时，会去掉文件名中的地区/版本标记再试一次。
  Future<List<ScrapeCandidate>> findCandidates({
    required String romPath,
    required String gameName,
    int? systemId,
  }) async {
    final query = gameName.trim().isNotEmpty
        ? gameName.trim()
        : LibraryService.gameNameFromRom(romPath);

    var results = await searchByName(query, systemId);
    if (results.isEmpty) {
      final cleaned = LibraryService.gameNameFromRom(romPath);
      if (cleaned.isNotEmpty && cleaned != query) {
        results = await searchByName(cleaned, systemId);
      }
    }
    return results;
  }

  /// 视频优先使用归一化（`video-normalized`）版本，其次才回退到原始 `video`。
  static const List<String> preferredVideoTypes = <String>[
    'video-normalized',
    'video',
  ];

  /// 附加媒体资源：TOML 标签 -> 候选 ScreenScraper 媒体类型（按优先级）。
  static const Map<String, List<String>> resourceMediaTypes =
      <String, List<String>>{
    'wheel': <String>['wheel', 'wheel-hd'],
    'box-texture': <String>['box-texture', 'box-2D-texture'],
    'box-3D': <String>['box-3D'],
    'support-2D': <String>['support-2D'],
    'fanart': <String>['fanart'],
    'mixrbv': <String>['mixrbv', 'mixrbv2', 'mixrbv1'],
  };

  /// 资源下载时展示给用户的中文名称。
  static const Map<String, String> resourceLabels = <String, String>{
    'wheel': '轮播图',
    'box-texture': '整体包装',
    'box-3D': '3D 封面',
    'support-2D': '游戏卡带',
    'fanart': '同人图',
    'mixrbv': '全家福',
  };

  static const List<String> _imageExtensions = <String>[
    'png',
    'jpg',
    'jpeg',
    'webp',
    'gif',
  ];

  /// 执行搜刮并把媒体写入 SaveDeck 游戏库，更新 [[games]] 条目。
  ///
  /// [renameGame] 为 false 时保留现有游戏名（手动搜刮选择「不应用翻译名」）；
  /// [nameOverride] 非空时用它代替 ScreenScraper 返回的名称。
  /// [onProgress] 用于汇报阶段文本。
  Future<GameEntry> applyCandidate({
    required PlatformLibrary platform,
    required GameEntry game,
    required ScrapeCandidate candidate,
    int? systemId,
    bool downloadCover = true,
    bool downloadVideo = true,
    bool overwriteDescription = true,
    bool renameGame = true,
    String? nameOverride,
    void Function(String message)? onProgress,
    void Function(int received, int? total)? onDownloadProgress,
  }) async {
    var detail = candidate;
    final lacksAllMedia = candidate.coverUrl == null &&
        candidate.videoUrl == null &&
        candidate.description == null;
    // 搜索接口只返回部分字段；开发商、发售日期和附加资源来自完整详情。
    // 补拉详情同时可确保视频使用归一化（video-normalized）版本。
    if (!candidate.detailed || lacksAllMedia) {
      onProgress?.call('正在获取游戏详情…');
      ScrapeCandidate? fetched;
      try {
        fetched = await fetchByGameId(candidate.gameId, systemId: systemId);
      } catch (_) {
        if (lacksAllMedia) rethrow;
      }
      if (fetched != null) {
        detail = fetched;
      } else if (lacksAllMedia) {
        throw const SsException('未能获取游戏详情，请换一个搜索结果重试');
      }
    }

    final oldName = game.name;
    final overrideName = nameOverride?.trim() ?? '';
    final scrapedName = detail.name.isNotEmpty
        ? detail.name
        : (candidate.name.isNotEmpty ? candidate.name : oldName);
    final newName = !renameGame
        ? oldName
        : (overrideName.isNotEmpty ? overrideName : scrapedName);

    // 名称变化时一次性迁移媒体目录并修正 TOML 路径（搜刮不改 ROM 文件名）。
    if (newName != oldName) {
      game = await LibraryService.syncGameName(
        platform,
        game,
        newName,
        renameRom: false,
        renameMedia: true,
      );
    }
    var cover = game.cover;
    var video = game.video;
    var description = game.description;

    final mediaDir = await LibraryService.mediaDirectory(platform, newName);

    if (downloadCover && detail.coverUrl != null) {
      onProgress?.call('正在下载封面…');
      final ext = _mediaExtension(detail.coverFormat, 'png');
      final file = File(p.join(mediaDir.path, 'cover.$ext'));
      await LibraryService.downloadStream(
        detail.coverUrl!,
        file.path,
        onProgress: onDownloadProgress,
      );
      cover = LibraryService.mediaRelativePath(newName, p.basename(file.path));
      for (final oldExt in _imageExtensions) {
        if (oldExt == ext) continue;
        final old = File(p.join(mediaDir.path, 'cover.$oldExt'));
        if (await old.exists()) await old.delete();
      }
    }

    if (downloadVideo && detail.videoUrl != null) {
      onProgress?.call('正在下载视频…');
      final ext = _mediaExtension(detail.videoFormat, 'mp4');
      final file = File(p.join(mediaDir.path, 'video.$ext'));
      try {
        await LibraryService.downloadStream(
          detail.videoUrl!,
          file.path,
          onProgress: onDownloadProgress,
        );
        video = LibraryService.mediaRelativePath(newName, p.basename(file.path));
        for (final oldExt in const <String>['mp4', 'webm', 'avi']) {
          if (oldExt == ext) continue;
          final old = File(p.join(mediaDir.path, 'video.$oldExt'));
          if (await old.exists()) await old.delete();
        }
      } catch (_) {
        onProgress?.call('视频下载失败，已跳过');
      }
    }

    // 附加资源：文件名即 TOML 标签（wheel.png、box-texture.png 等）。
    final resourcePaths = <String, String?>{
      for (final tag in GameEntry.resourceTags) tag: game.resourcePath(tag),
    };
    for (final tag in GameEntry.resourceTags) {
      final media = detail.resources[tag];
      if (media == null || media.url.isEmpty) continue;
      final label = resourceLabels[tag] ?? tag;
      onProgress?.call('正在下载$label…');
      final ext = _mediaExtension(media.format, 'png');
      final file = File(p.join(mediaDir.path, '$tag.$ext'));
      try {
        await LibraryService.downloadStream(
          media.url,
          file.path,
          onProgress: onDownloadProgress,
        );
        resourcePaths[tag] =
            LibraryService.mediaRelativePath(newName, p.basename(file.path));
        for (final oldExt in _imageExtensions) {
          if (oldExt == ext) continue;
          final old = File(p.join(mediaDir.path, '$tag.$oldExt'));
          if (await old.exists()) await old.delete();
        }
      } catch (_) {
        onProgress?.call('$label下载失败，已跳过');
      }
    }

    if (overwriteDescription && detail.description != null && detail.description!.isNotEmpty) {
      description = detail.description;
    }

    final developer = (detail.developer?.trim().isNotEmpty ?? false)
        ? detail.developer!.trim()
        : game.developer;
    final releaseDate = (detail.releaseDate?.trim().isNotEmpty ?? false)
        ? detail.releaseDate!.trim()
        : game.releaseDate;

    final updated = game.copyWith(
      name: newName,
      description: description,
      cover: cover,
      video: video,
      developer: developer,
      releaseDate: releaseDate,
      wheel: resourcePaths['wheel'],
      boxTexture: resourcePaths['box-texture'],
      box3D: resourcePaths['box-3D'],
      support2D: resourcePaths['support-2D'],
      fanart: resourcePaths['fanart'],
      mixrbv: resourcePaths['mixrbv'],
      clearDescription: description == null,
      clearCover: cover == null,
      clearVideo: video == null,
      clearWheel: resourcePaths['wheel'] == null,
      clearBoxTexture: resourcePaths['box-texture'] == null,
      clearBox3D: resourcePaths['box-3D'] == null,
      clearSupport2D: resourcePaths['support-2D'] == null,
      clearFanart: resourcePaths['fanart'] == null,
      clearMixrbv: resourcePaths['mixrbv'] == null,
    );

    final index = platform.games.indexWhere((g) => g.file == game.file);
    if (index >= 0) platform.games[index] = updated;

    onProgress?.call('正在写入 savedeck.toml…');
    await TomlService.save(platform);
    return updated;
  }

  /// 一次性搜刮：自动匹配 + 应用第一个候选（用于批量任务）。
  Future<GameEntry?> scrapeAuto({
    required PlatformLibrary platform,
    required GameEntry game,
    bool downloadCover = true,
    bool downloadVideo = true,
    bool overwriteDescription = true,
    void Function(String message)? onProgress,
    void Function(int received, int? total)? onDownloadProgress,
  }) async {
    final systemId = PlatformCatalog.ssIdFor(platform.platform);
    final romPath = p.join(platform.directory, game.file);
    if (!await File(romPath).exists()) {
      throw const SsException('ROM 文件不存在');
    }
    final candidates = await findCandidates(
      romPath: romPath,
      gameName: game.name.isNotEmpty ? game.name : LibraryService.gameNameFromRom(romPath),
      systemId: systemId,
    );
    if (candidates.isEmpty) return null;
    return applyCandidate(
      platform: platform,
      game: game,
      candidate: candidates.first,
      systemId: systemId,
      downloadCover: downloadCover,
      downloadVideo: downloadVideo,
      overwriteDescription: overwriteDescription,
      onProgress: onProgress,
      onDownloadProgress: onDownloadProgress,
    );
  }

  static String _mediaExtension(String? format, String fallback) {
    if (format == null || format.isEmpty) return fallback;
    final f = format.toLowerCase();
    if (f.contains('jpeg')) return 'jpg';
    if (['png', 'jpg', 'webp', 'mp4', 'webm', 'avi'].contains(f)) return f;
    return fallback;
  }

  ScrapeCandidate _candidateFromDetail(
    Map<dynamic, dynamic> jeu, {
    String fallbackName = '',
    bool detailed = true,
  }) {
    final name = _pickName(jeu['noms'], preferredLanguage) ??
        _mapValue(jeu['name'], 'text') ??
        fallbackName;
    final medias = (jeu['medias'] as List?) ?? const <dynamic>[];
    final cover = pickMedia(medias, const <String>['box-2D', 'box-3D']);
    final video = pickMedia(medias, preferredVideoTypes);

    final resources = <String, ScrapeMedia>{};
    for (final entry in resourceMediaTypes.entries) {
      final media = pickMedia(medias, entry.value);
      if (media == null) continue;
      final url = media['url']?.toString() ?? '';
      if (url.isEmpty) continue;
      resources[entry.key] = ScrapeMedia(
        url: url,
        format: media['format']?.toString() ?? '',
        type: media['type']?.toString() ?? '',
      );
    }

    return ScrapeCandidate(
      gameId: jeu['id']?.toString() ?? '',
      name: name,
      description: _preferredText(jeu['synopsis'], preferredLanguage),
      coverUrl: cover?['url']?.toString(),
      coverFormat: cover?['format']?.toString(),
      videoUrl: video?['url']?.toString(),
      videoFormat: video?['format']?.toString(),
      videoType: video?['type']?.toString(),
      region: _firstRegion(jeu['noms']),
      systemName: _mapValue(jeu['systeme'], 'text'),
      developer: _scalarText(jeu['developpeur']),
      releaseDate: pickReleaseDate(jeu['dates']),
      resources: resources,
      detailed: detailed,
    );
  }

  /// 从 `dates` 数组选取发售日期：jp 优先，其次 us，最后取第一个非空值。
  static String? pickReleaseDate(dynamic value) {
    if (value == null) return null;
    if (value is String) {
      final text = value.trim();
      return text.isEmpty ? null : text;
    }
    if (value is Map) {
      final text = value['text']?.toString().trim() ?? '';
      return text.isEmpty ? null : text;
    }
    if (value is List) {
      final items = value.whereType<Map>().toList();
      for (final region in const <String>['jp', 'us']) {
        for (final item in items) {
          if ((item['region']?.toString() ?? '').toLowerCase() == region) {
            final text = item['text']?.toString().trim() ?? '';
            if (text.isNotEmpty) return text;
          }
        }
      }
      for (final item in items) {
        final text = item['text']?.toString().trim() ?? '';
        if (text.isNotEmpty) return text;
      }
    }
    return null;
  }

  /// 提取可能是字符串、`{text: ...}` 或数组的简单文本字段。
  static String? _scalarText(dynamic value) {
    if (value == null) return null;
    if (value is String) {
      final text = value.trim();
      return text.isEmpty ? null : text;
    }
    if (value is Map) return _scalarText(value['text']);
    if (value is List) {
      for (final item in value) {
        final text = _scalarText(item);
        if (text != null) return text;
      }
      return null;
    }
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  /// 从媒体列表中选择最合适的项。
  ///
  /// 只做媒体类型的**精确**匹配（归一化大小写与 `-`/`_`/空格）。
  /// ScreenScraper 同时提供 `box-2D`（正面）、`box-2D-back`（背面）和
  /// `box-2D-side`（书脊/侧边），若用模糊匹配会把侧边图误当作正面封面。
  /// 非正面类型（side/spine/back）一律排除；同类型内按区域优先级挑选。
  static Map<String, dynamic>? pickMedia(
    List medias,
    List<String> types,
  ) {
    // 借鉴 neostation-frontend 的区域优先级表。
    const regionOrder = <String>[
      'wor', 'us', 'eu', 'jp', 'sp', 'fr', 'de', 'it', 'kr', 'cn', 'zh', 'ko',
    ];
    final all = medias
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .where((m) => (m['url']?.toString() ?? '').isNotEmpty)
        .toList();
    if (all.isEmpty) return null;

    int regionRank(Map<String, dynamic> media) {
      final region = (media['region']?.toString() ?? 'zz').toLowerCase();
      final index = regionOrder.indexOf(region);
      return index < 0 ? 99 : index;
    }

    for (final type in types) {
      final normalizedType = _normalizeMediaType(type);
      final matched = all.where((m) {
        final raw = m['type']?.toString() ?? '';
        if (_isNonFrontCoverType(raw)) return false;
        return _normalizeMediaType(raw) == normalizedType;
      }).toList();
      if (matched.isEmpty) continue;
      matched.sort((a, b) => regionRank(a).compareTo(regionRank(b)));
      return matched.first;
    }
    return null;
  }

  static String _normalizeMediaType(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[-_\s]'), '');

  /// 背面、侧边（书脊）不是游戏正面封面，必须排除。
  static bool _isNonFrontCoverType(String rawType) {
    final type = _normalizeMediaType(rawType);
    return type.contains('side') || type.contains('spine') || type.contains('back');
  }

  /// 从多语言名称数组中挑选显示名。
  ///
  /// `noms` 的每一项用 region 标记（ss/us/eu/jp...），因此英文名应优先匹配
  /// us/eu/wor 区域，而不是按 langue 匹配（那里没有 en）。
  static String? _pickName(dynamic value, String preferred) {
    if (value == null) return null;
    if (value is String) return value.isEmpty ? null : value;
    if (value is Map) {
      final text = value['text']?.toString();
      return (text == null || text.isEmpty) ? null : text;
    }
    if (value is List) {
      final items = value.whereType<Map>().toList();
      if (items.isEmpty) return null;

      String? textOf(Map item) {
        final text = item['text']?.toString();
        return (text == null || text.isEmpty) ? null : text;
      }

      // 1. 英文区域优先。
      const englishRegions = <String>['us', 'eu', 'wor', 'uk', 'au'];
      for (final region in englishRegions) {
        for (final item in items) {
          if ((item['region']?.toString() ?? '').toLowerCase() == region) {
            final text = textOf(item);
            if (text != null) return text;
          }
        }
      }

      // 2. 按首选语言/区域匹配。
      final target = preferred.toLowerCase();
      for (final item in items) {
        final lang = (item['langue'] ?? item['language'] ?? item['region'] ?? '')
            .toString()
            .toLowerCase();
        if (lang == target) {
          final text = textOf(item);
          if (text != null) return text;
        }
      }

      // 3. 兜底：第一个非空名称。
      for (final item in items) {
        final text = textOf(item);
        if (text != null) return text;
      }
    }
    return null;
  }

  /// 从多语言文本数组中按首选语言提取文本。
  static String? _preferredText(dynamic value, String preferred) {
    if (value == null) return null;
    if (value is String) return value.isEmpty ? null : value;
    if (value is Map) {
      final text = value['text']?.toString();
      return (text == null || text.isEmpty) ? null : text;
    }
    if (value is List) {
      final items = value.whereType<Map>().toList();
      if (items.isEmpty) return null;
      final match = items.where((m) {
        final lang = (m['langue'] ?? m['language'] ?? m['region'] ?? '').toString().toLowerCase();
        return lang == preferred.toLowerCase();
      }).firstWhere((m) => (m['text']?.toString().isNotEmpty ?? false), orElse: () => <String, dynamic>{});
      if (match['text'] != null && match['text'].toString().isNotEmpty) {
        return match['text'].toString();
      }
      for (final lang in <String>['en', 'zh', 'fr', 'jp']) {
        final alt = items.firstWhere(
          (m) => (m['langue'] ?? m['language'] ?? '').toString().toLowerCase() == lang &&
              (m['text']?.toString().isNotEmpty ?? false),
          orElse: () => <String, dynamic>{},
        );
        if (alt['text'] != null) return alt['text'].toString();
      }
      final any = items.firstWhere(
        (m) => m['text']?.toString().isNotEmpty ?? false,
        orElse: () => <String, dynamic>{},
      );
      return any['text']?.toString();
    }
    return null;
  }

  static String? _firstRegion(dynamic value) {
    if (value is List) {
      for (final item in value) {
        if (item is Map && item['region'] != null) return item['region'].toString();
      }
    }
    return null;
  }

  static String? _mapValue(dynamic value, String key) {
    if (value is Map) return value[key]?.toString();
    return null;
  }

  static List<dynamic> _locateList(Map<String, dynamic> data, List<String> keys) {
    final candidates = <dynamic>[
      (data['response'] as Map?)?['jeux'],
      (data['response'] as Map?)?['jeu'],
      data['jeux'],
      data['jeu'],
    ];
    for (final c in candidates) {
      if (c is List) return c;
      if (c is Map) return <dynamic>[c];
    }
    for (final key in keys) {
      final v = data[key];
      if (v is List) return v;
    }
    return const <dynamic>[];
  }

  static Map<dynamic, dynamic>? _locateMap(Map<String, dynamic> data, List<String> keys) {
    final candidates = <dynamic>[
      (data['response'] as Map?)?['jeu'],
      data['jeu'],
    ];
    for (final c in candidates) {
      if (c is Map) return c;
    }
    for (final key in keys) {
      final v = data[key];
      if (v is Map) return v;
      if (v is List && v.isNotEmpty && v.first is Map) return v.first;
    }
    return null;
  }
}

class SsException implements Exception {
  final String message;
  const SsException(this.message);

  @override
  String toString() => message;
}
