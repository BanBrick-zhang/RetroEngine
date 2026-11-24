import 'dart:convert';
import 'dart:io';

import '../models/library.dart';

/// 轻量 TOML 读写器，专门适配 savedeck.toml 的字段结构。
///
/// 支持：顶层键值、`[[games]]` 表、基本/字面字符串、多行字符串、
/// 整数、布尔与简单数组；未识别字段会原样保留，避免回写丢失配置。
class TomlService {
  static const fileName = 'savedeck.toml';

  /// 从磁盘读取并解析平台配置。
  ///
  /// 对编码做容错处理：优先 UTF-8，失败后尝试 GBK/GB18030，最后使用
  /// `allowMalformed` 解码，避免因为非 UTF-8 编码的中文 TOML 导致整个平台加载失败。
  static Future<PlatformLibrary> load(String directory) async {
    final file = File('$directory${Platform.pathSeparator}$fileName');
    final bytes = await file.readAsBytes();
    final content = _decodeTolerant(bytes);
    DateTime? tomlModified;
    try {
      tomlModified = await file.lastModified();
    } catch (_) {}
    final document = parse(content);
    return PlatformLibrary(
      directory: directory,
      platform: document.platform,
      formatVersion: document.formatVersion,
      sort: document.sort,
      launch: document.launch,
      games: document.games.map(GameEntry.fromMap).toList(),
      extras: document.extras,
      gamesInlineEmpty: document.gamesInlineEmpty,
      tomlModified: tomlModified,
    );
  }

  /// 容错解码 TOML 文本（去 BOM，兼容 UTF-8 / GBK / GB18030）。
  static String _decodeTolerant(List<int> bytes) {
    var data = bytes;
    // 去除 UTF-8 BOM
    if (data.length >= 3 && data[0] == 0xEF && data[1] == 0xBB && data[2] == 0xBF) {
      data = data.sublist(3);
    }
    try {
      return const Utf8Decoder().convert(data);
    } catch (_) {}

    // 中文 Windows 常见的 GBK 编码
    for (final encodingName in <String>['gbk', 'gb18030']) {
      try {
        final codec = Encoding.getByName(encodingName);
        if (codec != null) return codec.decode(data);
      } catch (_) {}
    }
    // 最后兜底：忽略非法字节，保证不抛异常
    return utf8.decode(data, allowMalformed: true);
  }

  /// 将平台配置写回磁盘（UTF-8）。
  static Future<void> save(PlatformLibrary library) async {
    final file = File('${library.directory}${Platform.pathSeparator}$fileName');
    await file.parent.create(recursive: true);
    await file.writeAsString(serialize(library), flush: true);
    library.tomlModified = await file.lastModified();
    library.hasToml = true;
  }

  /// 检查文件是否被外部修改。
  static Future<bool> isExternallyModified(PlatformLibrary library) async {
    final file = File('${library.directory}${Platform.pathSeparator}$fileName');
    if (!await file.exists()) return true;
    final current = await file.lastModified();
    final known = library.tomlModified;
    return known == null || current.microsecondsSinceEpoch != known.microsecondsSinceEpoch;
  }

  /// 解析 TOML 文本。
  static TomlDocument parse(String source) {
    final normalized = source.replaceAll('\r\n', '\n');
    final lines = normalized.split('\n');
    final doc = TomlDocument();
    Map<String, dynamic>? currentGame;

    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim();

      if (line.isEmpty || line.startsWith('#')) continue;

      if (line.startsWith('[[') && line.endsWith(']]')) {
        final section = line.substring(2, line.length - 2).trim();
        if (section == 'games') {
          currentGame = <String, dynamic>{};
          doc.games.add(currentGame);
          doc.gamesInlineEmpty = false;
        } else {
          currentGame = null;
        }
        continue;
      }

      if (line.startsWith('[') && line.endsWith(']')) {
        currentGame = null;
        continue;
      }

      final eq = _findEquals(line);
      if (eq < 0) continue;
      final key = line.substring(0, eq).trim();
      var raw = line.substring(eq + 1).trim();
      if (key.isEmpty || raw.isEmpty) continue;

      var isMultiline = false;
      // 多行字符串：累积到结束分隔符。
      if (raw.startsWith('"""')) {
        final consumed = _collectMultiline(lines, i, raw, '"""');
        raw = consumed.value;
        i = consumed.end;
        isMultiline = true;
      } else if (raw.startsWith("'''")) {
        final consumed = _collectMultiline(lines, i, raw, "'''");
        raw = consumed.value;
        i = consumed.end;
        isMultiline = true;
      }

      final dynamic value;
      if (isMultiline) {
        value = raw;
      } else {
        raw = _stripComment(raw).trim();
        if (raw.isEmpty) continue;
        value = _parseValue(raw);
      }

      if (currentGame != null) {
        currentGame[key] = value;
      } else {
        switch (key) {
          case 'format_version':
            doc.formatVersion = value is int ? value : int.tryParse(value.toString()) ?? 1;
            break;
          case 'platform':
            doc.platform = value.toString();
            break;
          case 'sort':
            doc.sort = value.toString();
            break;
          case 'launch':
            doc.launch = value.toString();
            break;
          case 'games':
            if (value is List) {
              doc.gamesInlineEmpty = value.isEmpty;
              // 兼容内联表写法：games = [{ name = "A", file = "a.gba" }, ...]
              for (final item in value) {
                if (item is Map) {
                  doc.games.add(Map<String, dynamic>.from(item));
                } else if (item is String && item.isNotEmpty) {
                  doc.games.add(<String, dynamic>{'name': item, 'file': item});
                }
              }
            }
            break;
          default:
            doc.extras[key] = value;
        }
      }
    }

    return doc;
  }

  /// 序列化为符合 savedeck 规范的 TOML 文本。
  static String serialize(PlatformLibrary library) {
    final buffer = StringBuffer();

    buffer.writeln('format_version = ${library.formatVersion}');
    buffer.writeln('platform = ${quote(library.platform)}');
    if (library.sort != null && library.sort!.isNotEmpty) {
      buffer.writeln('sort = ${quote(library.sort!)}');
    }
    if (library.launch != null && library.launch!.isNotEmpty) {
      buffer.writeln('launch = ${quote(library.launch!)}');
    }
    for (final entry in library.extras.entries) {
      if (entry.value == null) continue;
      buffer.writeln('${entry.key} = ${formatValue(entry.value)}');
    }

    if (library.games.isEmpty) {
      buffer.writeln('games = []');
    } else {
      for (final game in library.games) {
        final map = game.toMap();
        buffer.writeln();
        buffer.writeln('[[games]]');
        _writeField(buffer, 'name', map['name']);
        _writeField(buffer, 'file', map['file']);
        _writeField(buffer, 'sort', map['sort'], skipNull: true);
        _writeField(buffer, 'id', map['id'], skipNull: true);
        _writeField(buffer, 'description', map['description'], skipNull: true);
        _writeField(buffer, 'cover', map['cover'], skipNull: true);
        _writeField(buffer, 'video', map['video'], skipNull: true);
        _writeField(buffer, 'launch', map['launch'], skipNull: true);
        for (final entry in game.extras.entries) {
          if (entry.value == null) continue;
          _writeField(buffer, entry.key, entry.value, skipNull: true);
        }
      }
    }

    return buffer.toString();
  }

  static void _writeField(StringBuffer buffer, String key, dynamic value, {bool skipNull = false}) {
    if (skipNull && (value == null || value.toString().isEmpty)) return;
    buffer.writeln('$key = ${formatValue(value ?? '')}');
  }

  /// 将 Dart 值格式化为 TOML 字面量。
  static String formatValue(dynamic value) {
    if (value is bool) return value.toString();
    if (value is int) return value.toString();
    if (value is double) return value.toString();
    if (value is List) {
      return '[${value.map((e) => quote(e.toString())).join(', ')}]';
    }
    return quote(value.toString());
  }

  /// TOML 基本字符串转义。
  static String quote(String value) {
    final escaped = value
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"')
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r')
        .replaceAll('\t', '\\t');
    return '"$escaped"';
  }

  static int _findEquals(String line) {
    var quoteChar = '';
    var escaped = false;
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (c == '\\' && quoteChar == '"') {
        escaped = true;
        continue;
      }
      if (quoteChar.isEmpty) {
        if (c == '"' || c == "'") {
          quoteChar = c;
        } else if (c == '=') {
          return i;
        }
      } else if (c == quoteChar) {
        quoteChar = '';
      }
    }
    return -1;
  }

  static String _stripComment(String raw) {
    var quoteChar = '';
    var escaped = false;
    for (var i = 0; i < raw.length; i++) {
      final c = raw[i];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (c == '\\' && quoteChar == '"') {
        escaped = true;
        continue;
      }
      if (quoteChar.isEmpty) {
        if (c == '"' || c == "'") {
          quoteChar = c;
        } else if (c == '#') {
          return raw.substring(0, i);
        }
      } else if (c == quoteChar) {
        quoteChar = '';
      }
    }
    return raw;
  }

  static _MultilineResult _collectMultiline(
    List<String> lines,
    int start,
    String firstLine,
    String delimiter,
  ) {
    final buffer = StringBuffer(firstLine);
    var i = start;
    while (!buffer.toString().trimRight().endsWith(delimiter) && i + 1 < lines.length) {
      i++;
      buffer.writeln();
      buffer.write(lines[i]);
    }
    var text = buffer.toString().trim();
    if (text.startsWith(delimiter)) text = text.substring(delimiter.length);
    if (text.endsWith(delimiter)) {
      text = text.substring(0, text.length - delimiter.length);
    }
    if (delimiter == '"""') {
      text = text.replaceAll('\\n', '\n').replaceAll('\\"', '"').replaceAll('\\\\', '\\');
    }
    return _MultilineResult(text, i);
  }

  static dynamic _parseValue(String raw) {
    if (raw.startsWith('"""') && raw.endsWith('"""') && raw.length >= 6) {
      return raw.substring(3, raw.length - 3).replaceAll('\\n', '\n');
    }
    if (raw.startsWith("'''") && raw.endsWith("'''") && raw.length >= 6) {
      return raw.substring(3, raw.length - 3);
    }
    if (raw.startsWith('"') && raw.endsWith('"') && raw.length >= 2) {
      return _unescape(raw.substring(1, raw.length - 1));
    }
    if (raw.startsWith("'") && raw.endsWith("'") && raw.length >= 2) {
      return raw.substring(1, raw.length - 1);
    }
    if (raw == 'true') return true;
    if (raw == 'false') return false;
    if (raw.startsWith('[') && raw.endsWith(']')) {
      final inner = raw.substring(1, raw.length - 1).trim();
      if (inner.isEmpty) return <String>[];
      return _splitTopLevel(inner)
          .map((e) => _parseValue(e.trim()))
          .toList();
    }
    if (raw.startsWith('{') && raw.endsWith('}')) {
      final inner = raw.substring(1, raw.length - 1).trim();
      final map = <String, dynamic>{};
      if (inner.isEmpty) return map;
      for (final part in _splitTopLevel(inner)) {
        final eq = _findEquals(part);
        if (eq < 0) continue;
        var key = part.substring(0, eq).trim();
        if (key.length >= 2 &&
            ((key.startsWith('"') && key.endsWith('"')) ||
                (key.startsWith("'") && key.endsWith("'")))) {
          key = key.substring(1, key.length - 1);
        }
        map[key] = _parseValue(part.substring(eq + 1).trim());
      }
      return map;
    }
    final asInt = int.tryParse(raw);
    if (asInt != null) return asInt;
    return raw;
  }

  /// 按顶层逗号拆分数组/内联表内容，忽略引号与嵌套括号内的逗号。
  static List<String> _splitTopLevel(String input) {
    final parts = <String>[];
    var depth = 0;
    var quote = '';
    var escaped = false;
    final buffer = StringBuffer();
    for (var i = 0; i < input.length; i++) {
      final c = input[i];
      if (escaped) {
        buffer.write(c);
        escaped = false;
        continue;
      }
      if (c == '\\' && quote.isNotEmpty) {
        buffer.write(c);
        escaped = true;
        continue;
      }
      if (quote.isNotEmpty) {
        buffer.write(c);
        if (c == quote) quote = '';
        continue;
      }
      if (c == '"' || c == "'") {
        quote = c;
        buffer.write(c);
        continue;
      }
      if (c == '{' || c == '[') {
        depth++;
        buffer.write(c);
        continue;
      }
      if (c == '}' || c == ']') {
        depth--;
        buffer.write(c);
        continue;
      }
      if (c == ',' && depth == 0) {
        parts.add(buffer.toString().trim());
        buffer.clear();
        continue;
      }
      buffer.write(c);
    }
    final tail = buffer.toString().trim();
    if (tail.isNotEmpty) parts.add(tail);
    return parts;
  }

  static String _unescape(String value) {
    return value
        .replaceAll('\\"', '"')
        .replaceAll('\\n', '\n')
        .replaceAll('\\r', '\r')
        .replaceAll('\\t', '\t')
        .replaceAll('\\\\', '\\');
  }
}

class TomlDocument {
  int formatVersion = 1;
  String platform = '';
  String? sort;
  String? launch;
  List<Map<String, dynamic>> games = <Map<String, dynamic>>[];
  Map<String, dynamic> extras = <String, dynamic>{};
  bool gamesInlineEmpty = false;
}

class _MultilineResult {
  final String value;
  final int end;
  const _MultilineResult(this.value, this.end);
}
