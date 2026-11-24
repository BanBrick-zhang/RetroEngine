/// 各平台 ROM 文件扩展名数据。
///
/// 数据来源：ES-DE (EmulationStation Desktop Edition) 官方系统配置 stable-3.0
/// https://gitlab.com/es-de/emulationstation-de/-/raw/stable-3.0/resources/systems/unix/es_systems.xml
/// 覆盖 192 个平台，为 RetroArch / Libretro 生态广泛采用的权威扩展名表。
/// 抓取整理时间：2026-11-20
class PlatformExtensions {
  /// 通用压缩格式：压缩 ROM 无法从后缀判断内部平台，统一视为 ROM。
  static const Set<String> archives = <String>{
    'zip', '7z', 'rar', 'tar', 'gz', 'bz2', 'xz', 'tgz', 'tbz2', 'zst', 'lzma',
  };

  /// 明确的非 ROM 文件（文档/图片/音频/配置/系统文件）。
  ///
  /// 平台目录内媒体统一放在 media/ 子目录（扫描时已跳过），因此除这些
  /// 明确类型外的文件基本都是 ROM，可作为兜底识别依据。
  static const Set<String> nonRomExtensions = <String>{
    // 文档与配置
    'txt', 'md', 'nfo', 'ini', 'cfg', 'conf', 'toml', 'json', 'xml', 'yaml', 'yml',
    'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'csv', 'log', 'bak', 'tmp',
    // 图片
    'png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp', 'svg', 'ico', 'tif', 'tiff', 'avif',
    // 音视频
    'mp3', 'wav', 'ogg', 'flac', 'aac', 'm4a', 'wma', 'mp4', 'mkv', 'avi', 'webm',
    'mov', 'wmv', 'flv', 'm4v', 'srt', 'sub', 'ass', 'vtt',
    // 程序与系统
    'exe', 'dll', 'so', 'dylib', 'apk', 'bat', 'sh', 'cmd', 'py', 'js', 'html',
    'css', 'db', 'sqlite', 'ds_store', 'thumb', 'lnk', 'url', 'part', 'crdownload',
  };

  /// ES-DE 系统目录名 -> 本工具平台名，用于识别各种命名的平台文件夹。
  static const Map<String, String> esdeAliases = <String, String>{
    'nes': 'FC',
    'famicom': 'FC',
    'fds': 'FC',
    'sgb': 'FC',
    'snes': 'SFC',
    'sfc': 'SFC',
    'snesna': 'SFC',
    'gb': 'GB',
    'gbc': 'GBC',
    'gba': 'GBA',
    'n64': 'N64',
    'n64dd': 'N64',
    'nds': 'NDS',
    'n3ds': '3DS',
    'wii': 'Wii',
    'wiiu': 'WiiU',
    'switch': 'Switch',
    'megadrive': 'MD',
    'genesis': 'MD',
    'megadrivejp': 'MD',
    'mastersystem': 'SMS',
    'sg-1000': 'SMS',
    'gamegear': 'GG',
    'psx': 'PSX',
    'ps2': 'PS2',
    'psp': 'PSP',
    'psvita': 'Vita',
    'ps3': 'PS3',
    'gc': 'NGC',
    'saturn': 'Saturn',
    'saturnjp': 'Saturn',
    'dreamcast': 'DC',
    'pcengine': 'PCE',
    'pcenginecd': 'PCE',
    'tg16': 'PCE',
    'tg-cd': 'PCE',
    'supergrafx': 'PCE',
    'neogeo': 'NeoGeo',
    'neogeocd': 'NeoGeo',
    'neogeocdjp': 'NeoGeo',
    'atari2600': 'A2600',
    'atari5200': 'A5200',
    'atari7800': 'A7800',
    'atarilynx': 'Lynx',
    'atarijaguar': 'Jaguar',
    'atarijaguarcd': 'Jaguar',
    'virtualboy': 'VB',
    'wonderswan': 'WS',
    'wonderswancolor': 'WS',
    'ngp': 'NGP',
    'ngpc': 'NGP',
    '3do': '3DO',
    'mame': 'MAME',
    'fbneo': 'MAME',
    'arcade': 'MAME',
    'cps': 'MAME',
    'cps1': 'MAME',
    'cps2': 'MAME',
    'cps3': 'MAME',
    'naomi': 'MAME',
    'naomigd': 'MAME',
    'atomiswave': 'MAME',
    'model2': 'MAME',
    'model3': 'MAME',
    'segacd': 'SegACD',
    'megacd': 'SegACD',
    'sega32x': 'SegACD',
    'msx': 'MSX',
    'msx1': 'MSX',
    'msx2': 'MSX',
    'c64': 'C64',
    'amiga': 'Amiga',
    'amiga1200': 'Amiga',
    'amiga600': 'Amiga',
    'amigacd32': 'Amiga',
    'amstradcpc': 'CPC',
    'zxspectrum': 'ZX',
    'zx81': 'ZX',
    'zxnext': 'ZX',
    'dos': 'DOS',
    'atarist': 'AtariST',
    'intellivision': 'Intellivision',
    'colecovision': 'ColecoVision',
    'vectrex': 'Vectrex',
    'pico8': 'Pico8',
  };

  /// 按平台分组的扩展名（不含前导点，已去重并小写，含 zip/7z 压缩格式）。
  static const Map<String, List<String>> byPlatform = <String, List<String>>{
    'FC': <String>[
      '7z', 'fds', 'gb', 'gbc', 'nes', 'sgb', 'unf', 'unif', 'zip',
    ],
    'SFC': <String>[
      '7z', 'bin', 'bml', 'bs', 'bsx', 'dx2', 'fig', 'gd3', 'gd7', 'mgd', 'sfc', 'smc', 'st', 'swc',
      'zip',
    ],
    'GB': <String>[
      '7z', 'bs', 'cgb', 'dmg', 'gb', 'gbc', 'sfc', 'sgb', 'smc', 'zip',
    ],
    'GBC': <String>[
      '7z', 'bs', 'cgb', 'dmg', 'gb', 'gbc', 'sfc', 'sgb', 'smc', 'zip',
    ],
    'GBA': <String>[
      '7z', 'agb', 'bin', 'cgb', 'dmg', 'gb', 'gba', 'gbc', 'sgb', 'zip',
    ],
    'N64': <String>[
      '7z', 'bin', 'd64', 'n64', 'ndd', 'u1', 'v64', 'z64', 'zip',
    ],
    'NDS': <String>[
      '7z', 'app', 'bin', 'nds', 'zip',
    ],
    '3DS': <String>[
      '3ds', '3dsx', '7z', 'app', 'axf', 'cci', 'cxi', 'zip',
    ],
    'Wii': <String>[
      '7z', 'ciso', 'dff', 'dol', 'gcm', 'gcz', 'iso', 'm3u', 'rvz', 'tgc', 'wad', 'wbfs', 'wia', 'zip',
    ],
    'WiiU': <String>[
      '7z', 'rpx', 'tmd', 'wua', 'wud', 'wuhb', 'wux', 'zip',
    ],
    'Switch': <String>[
      '7z', 'nca', 'nro', 'nso', 'nsp', 'xci', 'zip',
    ],
    'MD': <String>[
      '32x', '68k', '7z', 'bin', 'bms', 'chd', 'cue', 'gen', 'gg', 'iso', 'm3u', 'mdx', 'sg', 'sgd',
      'smd', 'sms', 'zip',
    ],
    'SMS': <String>[
      '68k', '7z', 'bin', 'bms', 'chd', 'col', 'cue', 'gen', 'gg', 'iso', 'm3u', 'mdx', 'ri', 'rom',
      'sg', 'sgd', 'smd', 'sms', 'zip',
    ],
    'GG': <String>[
      '68k', '7z', 'bin', 'bms', 'chd', 'col', 'cue', 'gen', 'gg', 'iso', 'm3u', 'mdx', 'rom', 'sg',
      'sgd', 'smd', 'sms', 'zip',
    ],
    'PSX': <String>[
      '7z', 'bin', 'cbn', 'ccd', 'chd', 'cue', 'ecm', 'img', 'iso', 'm3u', 'mdf', 'mds', 'minipsf', 'pbp',
      'psexe', 'psf', 'toc', 'z', 'zip', 'znx',
    ],
    'PS2': <String>[
      '7z', 'bin', 'chd', 'ciso', 'cso', 'dump', 'gz', 'img', 'iso', 'isz', 'm3u', 'mdf', 'ngr', 'nrg',
      'zip', 'zso',
    ],
    'PSP': <String>[
      '7z', 'chd', 'cso', 'iso', 'pbp', 'prx', 'zip',
    ],
    'Vita': <String>[
      '7z', 'psvita', 'zip',
    ],
    'PS3': <String>[
      '7z', 'ps3', 'ps3dir', 'zip',
    ],
    'NGC': <String>[
      '7z', 'ciso', 'dff', 'dol', 'gcm', 'gcz', 'iso', 'm3u', 'rvz', 'tgc', 'wad', 'wbfs', 'wia', 'zip',
    ],
    'Saturn': <String>[
      '7z', 'bin', 'ccd', 'chd', 'cue', 'iso', 'm3u', 'mds', 'toc', 'zip',
    ],
    'DC': <String>[
      '7z', 'cdi', 'chd', 'cue', 'dat', 'gdi', 'iso', 'lst', 'm3u', 'zip',
    ],
    'PCE': <String>[
      '7z', 'ccd', 'chd', 'cue', 'img', 'iso', 'm3u', 'pce', 'sgx', 'toc', 'zip',
    ],
    'NeoGeo': <String>[
      '7z', 'chd', 'cue', 'neo', 'zip',
    ],
    'A2600': <String>[
      '7z', 'a26', 'bin', 'zip',
    ],
    'A5200': <String>[
      '7z', 'a52', 'atr', 'atx', 'bin', 'car', 'cas', 'cdm', 'rom', 'xex', 'xfd', 'zip',
    ],
    'A7800': <String>[
      '7z', 'a78', 'bin', 'zip',
    ],
    'Lynx': <String>[
      '7z', 'lnx', 'zip',
    ],
    'Jaguar': <String>[
      '7z', 'abs', 'bin', 'cdi', 'cof', 'cue', 'j64', 'jag', 'prg', 'rom', 'zip',
    ],
    'VB': <String>[
      '7z', 'bin', 'vb', 'vboy', 'zip',
    ],
    'WS': <String>[
      '7z', 'pc2', 'ws', 'wsc', 'zip',
    ],
    'NGP': <String>[
      '7z', 'ngc', 'ngp', 'ngpc', 'npc', 'zip',
    ],
    '3DO': <String>[
      '7z', 'bin', 'chd', 'cue', 'iso', 'zip',
    ],
    'MAME': <String>[
      '7z', 'bin', 'dat', 'lst', 'neo', 'zip',
    ],
    'SegACD': <String>[
      '32x', '68k', '7z', 'bin', 'bms', 'chd', 'cue', 'gen', 'gg', 'iso', 'm3u', 'mdx', 'sg', 'sgd',
      'smd', 'sms', 'zip',
    ],
    'MSX': <String>[
      '7z', 'cas', 'col', 'di1', 'di2', 'dmk', 'dsk', 'fd1', 'fd2', 'm3u', 'mx1', 'mx2', 'ogv', 'ri',
      'rom', 'sc', 'sg', 'wav', 'xsa', 'zip',
    ],
    'C64': <String>[
      '7z', 'bin', 'crt', 'd2m', 'd4m', 'd64', 'd6z', 'd71', 'd7z', 'd80', 'd81', 'd82', 'd8z', 'g41',
      'g4z', 'g64', 'g6z', 'gz', 'lnx', 'm3u', 'nbz', 'nib', 'p00', 'prg', 't64', 'tap', 'vfl', 'vsf',
      'x64', 'x6z', 'zip',
    ],
    'Amiga': <String>[
      '7z', 'adf', 'adz', 'ccd', 'chd', 'cue', 'dms', 'fdi', 'hdf', 'hdz', 'ipf', 'iso', 'lha', 'm3u',
      'mds', 'nrg', 'rp9', 'uae', 'zip',
    ],
    'CPC': <String>[
      '7z', 'cdt', 'cpr', 'dsk', 'kcr', 'm3u', 'sna', 'tap', 'tar', 'voc', 'zip',
    ],
    'ZX': <String>[
      '7z', 'dsk', 'gz', 'img', 'mgt', 'nex', 'p', 'rzx', 'scl', 'sna', 'szx', 'tap', 'trd', 'tzx',
      'udi', 'z80', 'zip',
    ],
    'DOS': <String>[
      '7z', 'com', 'cue', 'dosz', 'iso', 'zip',
    ],
    'AtariST': <String>[
      '7z', 'dim', 'ipf', 'm3u', 'msa', 'st', 'stx', 'zip',
    ],
    'Intellivision': <String>[
      '7z', 'bin', 'int', 'rom', 'zip',
    ],
    'ColecoVision': <String>[
      '7z', 'bin', 'cas', 'col', 'cv', 'dsk', 'm3u', 'mx1', 'mx2', 'ri', 'rom', 'sc', 'sg', 'zip',
    ],
    'Vectrex': <String>[
      '7z', 'bin', 'gam', 'vc', 'vec', 'zip',
    ],
    'Pico8': <String>[
      '7z', 'p8', 'png', 'zip',
    ],
  };

  /// 全部扩展名的并集（含压缩格式）。
  static Set<String> get all {
    final result = <String>{...archives};
    for (final list in byPlatform.values) {
      result.addAll(list);
    }
    return result;
  }
}
