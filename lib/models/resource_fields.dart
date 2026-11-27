/// 游戏资源字段标识、中文名称与默认选项。
///
/// 同一套标识同时用于：
/// - 设置页「搜刮选项」：决定哪些内容会被搜刮并写入 TOML；
/// - 设置页「游戏详情页设置」：决定详情页展示哪些内容；
/// - 详情页右上角「编辑游戏」弹窗：展示并提供资源路径编辑入口。
class ResourceFields {
  /// 封面（ScreenScraper `box-2D`，写入 TOML 的 `cover`）。
  static const String cover = 'cover';

  /// 游戏视频（写入 TOML 的 `video`）。
  static const String video = 'video';

  /// 游戏简介（写入 TOML 的 `description`）。
  static const String description = 'description';

  /// 开发商（写入 TOML 的 `developpeur`）。
  static const String developer = 'developer';

  /// 发售日期（写入 TOML 的 `dates`）。
  static const String releaseDate = 'release-date';

  /// 默认开启的字段：开发商、发行日期、box2D 封面、简介、视频。
  static const Set<String> defaults = <String>{
    cover,
    video,
    description,
    developer,
    releaseDate,
  };

  /// 全部可选字段（顺序即界面展示顺序）。
  static const List<String> all = <String>[
    cover,
    video,
    description,
    developer,
    releaseDate,
    ...GameResourceTags.tags,
  ];

  /// 设置页 / 弹窗中展示的名称。
  static const Map<String, String> labels = <String, String>{
    cover: '封面（box2D）',
    video: '游戏视频',
    description: '游戏简介',
    developer: '开发商',
    releaseDate: '发行日期',
    'wheel': '轮播图（wheel）',
    'box-texture': '整体包装（box-texture）',
    'box-3D': '3D 封面（box-3D）',
    'support-2D': '游戏卡带（support-2D）',
    'fanart': '同人图（fanart）',
    'mixrbv': '全家福（mixrbv）',
  };

  static String labelOf(String field) => labels[field] ?? field;

  /// 是否为附加媒体资源（下载后写入 `media/<游戏名>/<标签>-<id>.<扩展名>`）。
  static bool isResource(String field) => GameResourceTags.tags.contains(field);
}

/// 附加媒体资源标签（同时用作 TOML 键与文件名前缀）。
class GameResourceTags {
  static const List<String> tags = <String>[
    'wheel',
    'box-texture',
    'box-3D',
    'support-2D',
    'fanart',
    'mixrbv',
  ];
}