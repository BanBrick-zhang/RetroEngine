/// 游戏库数据模型与平台目录。
import '../data/platform_extensions.dart';
import '../data/screenscraper_systems.dart';

/// 单个游戏条目，对应 savedeck.toml 中一个 [[games]] 区块。
class GameEntry {
  String name;
  String file;
  String? sort;
  String? id;
  String? description;
  String? cover;
  String? video;
  String? launch;

  /// 保留配置中出现的其他字段，避免回写时丢失。
  Map<String, dynamic> extras;

  GameEntry({
    required this.name,
    required this.file,
    this.sort,
    this.id,
    this.description,
    this.cover,
    this.video,
    this.launch,
    Map<String, dynamic>? extras,
  }) : extras = extras ?? <String, dynamic>{};

  factory GameEntry.fromMap(Map<String, dynamic> map) {
    final extras = <String, dynamic>{};
    String str(String key) => (map[key] ?? '').toString();
    String? opt(String key) =>
        map.containsKey(key) ? map[key]?.toString() : null;

    for (final entry in map.entries) {
      if (!_known.contains(entry.key)) extras[entry.key] = entry.value;
    }

    return GameEntry(
      name: str('name'),
      file: str('file'),
      sort: opt('sort'),
      id: opt('id'),
      description: opt('description'),
      cover: opt('cover'),
      video: opt('video'),
      launch: opt('launch'),
      extras: extras,
    );
  }

  static const Set<String> _known = <String>{
    'name',
    'file',
    'sort',
    'id',
    'description',
    'cover',
    'video',
    'launch',
  };

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{'name': name, 'file': file};
    if (sort != null && sort!.isNotEmpty) map['sort'] = sort;
    if (id != null && id!.isNotEmpty) map['id'] = id;
    if (description != null && description!.isNotEmpty) {
      map['description'] = description;
    }
    if (cover != null && cover!.isNotEmpty) map['cover'] = cover;
    if (video != null && video!.isNotEmpty) map['video'] = video;
    if (launch != null && launch!.isNotEmpty) map['launch'] = launch;
    map.addAll(extras);
    return map;
  }

  GameEntry copyWith({
    String? name,
    String? file,
    String? sort,
    String? id,
    String? description,
    String? cover,
    String? video,
    String? launch,
    bool clearSort = false,
    bool clearDescription = false,
    bool clearCover = false,
    bool clearVideo = false,
    bool clearLaunch = false,
  }) {
    return GameEntry(
      name: name ?? this.name,
      file: file ?? this.file,
      sort: clearSort ? null : (sort ?? this.sort),
      id: id ?? this.id,
      description: clearDescription ? null : (description ?? this.description),
      cover: clearCover ? null : (cover ?? this.cover),
      video: clearVideo ? null : (video ?? this.video),
      launch: clearLaunch ? null : (launch ?? this.launch),
      extras: Map<String, dynamic>.from(extras),
    );
  }
}

/// 一个平台目录及其 savedeck.toml 配置。
class PlatformLibrary {
  /// 平台目录绝对路径。
  final String directory;

  String platform;
  int formatVersion;
  String? sort;
  String? launch;
  List<GameEntry> games;
  Map<String, dynamic> extras;
  bool gamesInlineEmpty;

  /// 保存时记录的文件修改时间，用于检测外部改动。
  DateTime? tomlModified;

  /// 目录是否存在 savedeck.toml。为 false 时条目由 ROM 文件自动识别生成。
  bool hasToml;

  /// 加载配置时的错误信息，用于诊断（正常为 null）。
  String? loadError;

  PlatformLibrary({
    required this.directory,
    required this.platform,
    this.formatVersion = 1,
    this.sort,
    this.launch,
    List<GameEntry>? games,
    Map<String, dynamic>? extras,
    this.gamesInlineEmpty = false,
    this.tomlModified,
    this.hasToml = true,
    this.loadError,
  }) : games = games ?? <GameEntry>[],
       extras = extras ?? <String, dynamic>{};

  String get name => platform;
}

/// 目录访问权限的真实检测结果。
class DirectoryAccessResult {
  final bool exists;
  final bool canRead;
  final bool canWrite;
  final bool? manageGranted;
  final bool? legacyGranted;

  const DirectoryAccessResult({
    required this.exists,
    required this.canRead,
    required this.canWrite,
    this.manageGranted,
    this.legacyGranted,
  });

  bool get ok => exists && canRead && canWrite;
}

/// ScreenScraper 搜索结果（尚未下载媒体）。
class ScrapeCandidate {
  final String gameId;
  final String name;
  final String? description;
  final String? coverUrl;
  final String? coverFormat;
  final String? videoUrl;
  final String? videoFormat;
  final String? region;
  final String? systemName;

  const ScrapeCandidate({
    required this.gameId,
    required this.name,
    this.description,
    this.coverUrl,
    this.coverFormat,
    this.videoUrl,
    this.videoFormat,
    this.region,
    this.systemName,
  });
}

/// 平台信息：显示名、别名、ScreenScraper 系统 ID 与常见 ROM 扩展名。
class PlatformInfo {
  final String name;
  final List<String> aliases;
  final int ssId;
  final List<String> extensions;

  const PlatformInfo(this.name, this.aliases, this.ssId, this.extensions);
}

/// 常见平台目录及对应的 ScreenScraper systemeid。
class PlatformCatalog {
  static const List<PlatformInfo> all = <PlatformInfo>[
    PlatformInfo('FC', ['fc', 'nes', 'famicom', '红白机', '任天堂'], 3, ['nes', 'fc', 'fds']),
    PlatformInfo('SFC', ['sfc', 'snes', 'super nintendo', '超任'], 4, ['sfc', 'snes', 'smc']),
    PlatformInfo('GB', ['gb', 'gameboy', 'game boy'], 9, ['gb']),
    PlatformInfo('GBC', ['gbc', 'gameboycolor', 'game boy color'], 10, ['gbc']),
    PlatformInfo('GBA', ['gba', 'gameboyadvance', 'game boy advance'], 12, ['gba']),
    PlatformInfo('N64', ['n64', 'nintendo64'], 14, ['n64', 'z64', 'v64']),
    PlatformInfo('NDS', ['nds', 'ds', 'nintendods'], 15, ['nds']),
    PlatformInfo('Wii', ['wii'], 16, ['iso', 'wbfs', 'rvz']),
    PlatformInfo('3DS', ['3ds'], 17, ['3ds', 'cci', 'cxi']),
    PlatformInfo('WiiU', ['wiiu', 'wii u'], 18, ['iso', 'wud', 'wux']),
    PlatformInfo('MD', ['md', 'megadrive', 'genesis', 'genesis/megadrive'], 1, ['md', 'gen', 'bin']),
    PlatformInfo('SMS', ['sms', 'mastersystem', 'master system'], 2, ['sms']),
    PlatformInfo('GG', ['gg', 'gamegear', 'game gear'], 21, ['gg']),
    PlatformInfo('PSX', ['psx', 'ps1', 'playstation', 'playstation1'], 57, ['bin', 'cue', 'chd', 'pbp', 'iso']),
    PlatformInfo('PS2', ['ps2', 'playstation2'], 58, ['iso', 'chd', 'bin', 'cue']),
    PlatformInfo('PSP', ['psp'], 61, ['iso', 'cso', 'chd', 'pbp']),
    PlatformInfo('Vita', ['vita', 'psvita', 'psv'], 62, ['iso', 'vpk']),
    PlatformInfo('NGC', ['ngc', 'gamecube', 'gc'], 13, ['iso', 'gcm', 'rvz']),
    PlatformInfo('Saturn', ['saturn', 'ss'], 22, ['bin', 'cue', 'chd', 'iso']),
    PlatformInfo('DC', ['dc', 'dreamcast'], 23, ['bin', 'cue', 'chd', 'gdi', 'iso']),
    PlatformInfo('PCE', ['pce', 'pcengine', 'turbografx', 'turbo grafx'], 31, ['pce', 'bin', 'cue']),
    PlatformInfo('NeoGeo', ['neogeo', 'neogeo', 'ng'], 142, ['zip', 'bin', 'iso']),
    PlatformInfo('A2600', ['a2600', 'atari2600', 'atari 2600'], 26, ['a26', 'bin']),
    PlatformInfo('MAME', ['mame', 'arcade', '街机'], 142, ['zip']),
  ];

  static PlatformInfo? byFolderName(String name) {
    final key = name.trim().toLowerCase();
    for (final info in all) {
      if (info.name.toLowerCase() == key) return info;
      if (info.aliases.any((a) => a.toLowerCase() == key)) return info;
    }
    // ES-DE / RetroArch 常见系统目录名（nes、n3ds、psvita、megadrive 等）
    final esdePlatform = PlatformExtensions.esdeAliases[key];
    if (esdePlatform != null) return byName(esdePlatform);
    return null;
  }

  static PlatformInfo? byName(String platformName) {
    final key = platformName.trim().toLowerCase();
    for (final info in all) {
      if (info.name.toLowerCase() == key) return info;
    }
    return null;
  }

  /// 可作为 ROM 识别的全部扩展名（合并 ES-DE 192 个平台 + 压缩格式）。
  static Set<String> get romExtensions => PlatformExtensions.all;

  /// 判断某个文件是否为 ROM。
  ///
  /// 压缩格式（zip/7z/rar 等）一律视为 ROM；其余扩展名匹配 ES-DE 平台扩展名表。
  static bool isRomFile(String filePath) {
    final ext = _extension(filePath);
    if (ext.isEmpty) return false;
    if (PlatformExtensions.archives.contains(ext)) return true;
    return PlatformExtensions.all.contains(ext);
  }

  /// 针对具体平台判断文件是否为 ROM（优先使用该平台的扩展名列表）。
  ///
  /// 识别顺序：压缩格式 -> 该平台扩展名 -> 全局扩展名 -> 兜底（非已知杂项文件即 ROM）。
  static bool isRomForPlatform(String filePath, String? platformName) {
    final ext = _extension(filePath);
    if (ext.isEmpty) return false;
    if (PlatformExtensions.archives.contains(ext)) return true;

    final info = platformName == null ? null : byFolderName(platformName);
    if (info != null) {
      final platformExts = PlatformExtensions.byPlatform[info.name];
      // 该平台明确的扩展名优先（如 Pico8 的 .png 就是合法 ROM）。
      if (platformExts != null && platformExts.contains(ext)) return true;
    }

    // 明确的非 ROM 文件（文档/图片/音视频/系统文件）直接排除。
    if (PlatformExtensions.nonRomExtensions.contains(ext)) return false;
    if (PlatformExtensions.all.contains(ext)) return true;

    // 兜底：平台目录内其余未知格式都按 ROM 处理，避免漏掉罕见格式。
    return true;
  }

  static String _extension(String filePath) {
    final name = filePath.split(RegExp(r'[\\/]')).last;
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  static PlatformInfo? byExtension(String filePath) {
    final ext = _extension(filePath);
    if (ext.isEmpty || PlatformExtensions.archives.contains(ext)) return null;

    // 扩展名可能对应多个平台，交由目录名优先判断；这里只给出没有歧义的项。
    const unique = <String, String>{
      'nes': 'FC', 'fds': 'FC', 'unf': 'FC', 'unif': 'FC',
      'sfc': 'SFC', 'snes': 'SFC', 'smc': 'SFC', 'swc': 'SFC', 'fig': 'SFC',
      'gb': 'GB', 'gbc': 'GBC', 'gba': 'GBA', 'agb': 'GBA',
      'n64': 'N64', 'z64': 'N64', 'v64': 'N64', 'ndd': 'N64',
      'nds': 'NDS', '3ds': '3DS', 'cci': '3DS', 'cxi': '3DS',
      'sms': 'SMS', 'gg': 'GG', 'pce': 'PCE',
      'md': 'MD', 'gen': 'MD', 'smd': 'MD',
      'gdi': 'DC', 'vpk': 'Vita', 'a26': 'A2600',
      'wbfs': 'Wii', 'wud': 'WiiU', 'wux': 'WiiU', 'xci': 'Switch', 'nsp': 'Switch',
      'chd': 'PSX', 'pbp': 'PSP', 'cso': 'PSP', 'bin': 'PSX', 'cue': 'PSX', 'iso': 'PSX',
    };
    final name = unique[ext];
    if (name != null) return byName(name);

    for (final entry in PlatformExtensions.byPlatform.entries) {
      if (entry.value.contains(ext)) return byName(entry.key);
    }
    return null;
  }

  /// 根据目录名与 ROM 扩展名推断平台；目录名优先，扩展名按出现次数投票。
  static PlatformInfo? detectPlatform(String directoryName, Iterable<String> romPaths) {
    final byNameInfo = byFolderName(directoryName);
    if (byNameInfo != null) return byNameInfo;

    final votes = <String, int>{};
    for (final path in romPaths) {
      final info = byExtension(path);
      if (info != null) votes[info.name] = (votes[info.name] ?? 0) + 1;
    }
    if (votes.isEmpty) return null;
    final winner = votes.entries.reduce((a, b) => a.value >= b.value ? a : b);
    return byName(winner.key);
  }

  /// 根据目录名推断 ScreenScraper 系统 ID。
  ///
  /// 优先使用 `assets/screenscraper_systems.json`（由 systemesListe.php 生成，
  /// 覆盖更全）；未加载或未匹配时回退到内置平台表。
  static int? ssIdFor(String folderName) =>
      ScreenscraperSystems.resolveId(folderName) ?? byFolderName(folderName)?.ssId;
}
