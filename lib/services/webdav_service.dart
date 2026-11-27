import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// WebDAV 返回的条目。
class WebDavEntry {
  final String name;

  /// 相对于 PROPFIND 请求目录的路径，使用 `/` 分隔。
  final String relativePath;

  final bool isDirectory;
  final DateTime? modified;
  final int size;

  int? get modifiedMs => modified?.millisecondsSinceEpoch;

  const WebDavEntry({
    required this.name,
    required this.relativePath,
    required this.isDirectory,
    this.modified,
    this.size = 0,
  });

  @override
  String toString() =>
      'WebDavEntry($relativePath, dir=$isDirectory, size=$size, mtime=$modified)';
}

/// WebDAV 操作异常，[message] 可直接展示给用户。
class WebDavException implements Exception {
  final String message;

  const WebDavException(this.message);

  @override
  String toString() => message;
}

/// 轻量 WebDAV 客户端：只实现云存档同步需要的 PROPFIND / MKCOL / GET / PUT /
/// DELETE / MOVE，兼容坚果云、Nextcloud 等常见服务。
class WebDavService {
  final String baseUrl;
  final String username;
  final String password;

  /// 云同步根目录，例如 `RetroEngine`，可为空表示直接使用 WebDAV 根路径。
  final String remoteRoot;

  final http.Client _client;

  WebDavService({
    required String baseUrl,
    required this.username,
    required this.password,
    String remoteRoot = 'RetroEngine',
    http.Client? client,
  })  : baseUrl = _normalizeBaseUrl(baseUrl),
        remoteRoot = _normalizeRemoteRoot(remoteRoot),
        _client = client ?? http.Client();

  static String _normalizeBaseUrl(String value) {
    var url = value.trim();
    if (url.isEmpty) return url;
    if (!url.startsWith(RegExp(r'https?://', caseSensitive: false))) {
      url = 'https://$url';
    }
    return url.endsWith('/') ? url : '$url/';
  }

  static String _normalizeRemoteRoot(String value) {
    return value
        .trim()
        .replaceAll('\\', '/')
        .split('/')
        .where((s) => s.isNotEmpty && s != '.' && s != '..')
        .join('/');
  }

  Uri get baseUri => Uri.parse(baseUrl);

  Map<String, String> get _headers {
    final token = base64Encode(utf8.encode('$username:$password'));
    return <String, String>{
      'Authorization': 'Basic $token',
      'User-Agent': 'RetroEngine-CloudSave/1.0',
      'Accept': '*/*',
    };
  }

  /// 把相对路径（已解码）拼接到 WebDAV 根地址。
  Uri uriFor(String relativePath, {bool collection = false}) {
    final segments = <String>[
      ...baseUri.pathSegments.where((s) => s.isNotEmpty),
      ...relativePath.split('/').where((s) => s.isNotEmpty),
    ];
    var path = '/${segments.join('/')}';
    if (collection && !path.endsWith('/')) path = '$path/';
    return baseUri.replace(path: path, query: null, fragment: null);
  }

  /// 完整的云存档目录：`remoteRoot/remoteName`。
  String folderPath(String remoteName) {
    final root = remoteRoot;
    final name = _normalizeRemoteRoot(remoteName);
    if (root.isEmpty) return name;
    if (name.isEmpty) return root;
    return '$root/$name';
  }

  Future<bool> testConnection() async {
    final uri = uriFor(remoteRoot, collection: true);
    try {
      final response = await _client
          .send(http.Request('PROPFIND', uri)
            ..headers.addAll(_headers)
            ..headers['Depth'] = '0'
            ..headers['Content-Type'] = 'application/xml; charset=utf-8')
          .timeout(const Duration(seconds: 20));
      final status = response.statusCode;
      await response.stream.drain<void>();
      // 207/200/405 表示根路径可访问；404/403 说明认证通过但目录尚未创建或受限。
      if (status == 207 ||
          status == 200 ||
          status == 405 ||
          status == 404 ||
          status == 403) {
        return true;
      }
      throw _statusError(status);
    } on TimeoutException {
      throw const WebDavException('连接超时，请检查服务器地址与网络');
    } on SocketException catch (e) {
      throw WebDavException('无法连接服务器：${e.message}');
    } on http.ClientException catch (e) {
      throw WebDavException('连接失败：${e.message}');
    }
  }

  /// 列出目录下的直接子项。[path] 为相对 WebDAV 根目录的路径。
  Future<List<WebDavEntry>> list(String path) async {
    final uri = uriFor(path, collection: true);
    final body = utf8.encode('<?xml version="1.0" encoding="utf-8"?>'
        '<d:propfind xmlns:d="DAV:"><d:prop>'
        '<d:displayname/><d:getlastmodified/><d:getcontentlength/>'
        '<d:resourcetype/></d:prop></d:propfind>');
    http.Response response;
    try {
      response = await _client
          .send(http.Request('PROPFIND', uri)
            ..headers.addAll(_headers)
            ..headers['Depth'] = '1'
            ..headers['Content-Type'] = 'application/xml; charset=utf-8'
            ..bodyBytes = body)
          .timeout(const Duration(seconds: 30))
          .then(http.Response.fromStream);
    } on TimeoutException {
      throw const WebDavException('获取云端目录超时');
    } on SocketException catch (e) {
      throw WebDavException('连接云端失败：${e.message}');
    }

    if (response.statusCode == 404) {
      throw const WebDavException('云端路径不存在（404）');
    }
    if (response.statusCode != 207 && response.statusCode != 200) {
      throw _statusError(response.statusCode);
    }
    return _parseMultiStatus(response.bodyBytes, path);
  }

  /// 逐级创建目录，已存在的层级忽略。
  Future<void> ensureDirectory(String path) async {
    final parts = path.split('/').where((s) => s.isNotEmpty).toList();
    var current = '';
    for (final part in parts) {
      current = current.isEmpty ? part : '$current/$part';
      final uri = uriFor(current, collection: true);
      try {
        final response = await _client
            .send(http.Request('MKCOL', uri)
              ..headers.addAll(_headers)
              ..headers['Content-Length'] = '0')
            .timeout(const Duration(seconds: 20));
        await response.stream.drain<void>();
        final status = response.statusCode;
        // 201 创建成功；405 已存在；301/302 部分服务会重定向；403 可能已存在但无权限。
        if (status == 201 || status == 200 || status == 405 || status == 301) {
          continue;
        }
        if (status == 401) throw _statusError(status);
        if (status == 409) {
          throw const WebDavException('云端父目录不存在或没有写入权限（409）');
        }
        throw _statusError(status);
      } on TimeoutException {
        throw const WebDavException('创建云端目录超时');
      } on SocketException catch (e) {
        throw WebDavException('连接云端失败：${e.message}');
      }
    }
  }

  Future<void> upload(String path, File file) async {
    final uri = uriFor(path);
    Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } on FileSystemException catch (e) {
      throw WebDavException('读取本地文件失败：${e.message}');
    }
    try {
      final response = await _client
          .put(uri, headers: {
            ..._headers,
            'Content-Type': 'application/octet-stream',
          }, body: bytes)
          .timeout(const Duration(seconds: 90));
      if (response.statusCode != 200 &&
          response.statusCode != 201 &&
          response.statusCode != 204) {
        throw _statusError(response.statusCode);
      }
    } on TimeoutException {
      throw const WebDavException('上传超时，请检查网络');
    } on SocketException catch (e) {
      throw WebDavException('上传失败：${e.message}');
    }
  }

  Future<Uint8List> download(String path) async {
    final uri = uriFor(path);
    try {
      final response =
          await _client.get(uri, headers: _headers).timeout(const Duration(seconds: 90));
      if (response.statusCode == 404) {
        throw const WebDavException('云端文件不存在（404）');
      }
      if (response.statusCode != 200) {
        throw _statusError(response.statusCode);
      }
      return response.bodyBytes;
    } on TimeoutException {
      throw const WebDavException('下载超时，请检查网络');
    } on SocketException catch (e) {
      throw WebDavException('下载失败：${e.message}');
    }
  }

  Future<void> delete(String path) async {
    final uri = uriFor(path);
    try {
      final response =
          await _client.delete(uri, headers: _headers).timeout(const Duration(seconds: 30));
      final status = response.statusCode;
      if (status == 200 || status == 204 || status == 404) return;
      throw _statusError(status);
    } on TimeoutException {
      throw const WebDavException('删除云端文件超时');
    } on SocketException catch (e) {
      throw WebDavException('删除失败：${e.message}');
    }
  }

  /// 重命名/移动云端文件，用于冲突时保留云端副本。
  Future<void> move(String from, String to) async {
    final source = uriFor(from);
    final destination = uriFor(to);
    try {
      final response = await _client
          .send(http.Request('MOVE', source)
            ..headers.addAll(_headers)
            ..headers['Destination'] = destination.toString()
            ..headers['Overwrite'] = 'F')
          .timeout(const Duration(seconds: 30));
      await response.stream.drain<void>();
      final status = response.statusCode;
      if (status == 201 || status == 204 || status == 200) return;
      throw _statusError(status);
    } on TimeoutException {
      throw const WebDavException('移动云端文件超时');
    } on SocketException catch (e) {
      throw WebDavException('移动云端文件失败：${e.message}');
    }
  }

  void close() => _client.close();

  List<WebDavEntry> _parseMultiStatus(Uint8List bytes, String requestPath) {
    final xml = utf8.decode(bytes, allowMalformed: true);
    final blocks = RegExp(
      r'<(?:\w+:)?response\b[^>]*>([\s\S]*?)</(?:\w+:)?response>',
      caseSensitive: false,
    ).allMatches(xml);

    final request = requestPath.replaceAll(RegExp(r'^/+|/+$'), '');
    final entries = <WebDavEntry>[];

    for (final block in blocks) {
      final body = block.group(1) ?? '';
      // 跳过 404 的占位 entry。
      final statusText = _firstTag(body, 'status');
      if (statusText != null && statusText.contains('404')) continue;

      final hrefRaw = _firstTag(body, 'href');
      if (hrefRaw == null || hrefRaw.isEmpty) continue;

      Uri href;
      try {
        href = Uri.parse(hrefRaw);
      } catch (_) {
        continue;
      }
      String decodedPath;
      try {
        decodedPath = Uri.decodeComponent(href.path);
      } catch (_) {
        decodedPath = href.path;
      }
      final isDirectory = body.toLowerCase().contains(':collection') ||
          decodedPath.endsWith('/');
      decodedPath = decodedPath.replaceAll(RegExp(r'/+$'), '');

      // href 可能是服务器完整路径（例如 Nextcloud 的 /remote.php/dav/...），
      // 因此按路径段匹配请求目录，取其后的部分作为相对路径。
      final hrefSegments = decodedPath
          .split('/')
          .where((s) => s.isNotEmpty)
          .toList(growable: false);
      final requestSegments =
          request.split('/').where((s) => s.isNotEmpty).toList(growable: false);
      final matchIndex = _findSegments(hrefSegments, requestSegments);

      String relative;
      if (matchIndex >= 0) {
        final rest =
            hrefSegments.sublist(matchIndex + requestSegments.length);
        // 目录自身也出现在 Multi-Status 中，跳过。
        if (rest.isEmpty) continue;
        relative = rest.join('/');
      } else if (hrefSegments.isNotEmpty) {
        // 兼容反向代理等 href 前缀完全不同的情况，退化为取文件名。
        relative = hrefSegments.last;
      } else {
        continue;
      }
      if (relative.isEmpty) continue;

      final name = relative.split('/').last;

      final modified = _parseHttpDate(_firstTag(body, 'getlastmodified'));
      final size = int.tryParse(_firstTag(body, 'getcontentlength') ?? '') ?? 0;

      entries.add(WebDavEntry(
        name: name,
        relativePath: relative,
        isDirectory: isDirectory,
        modified: modified,
        size: size,
      ));
    }
    return entries;
  }

  /// 在 [haystack] 中查找连续出现的路径段序列 [needle]，返回起始下标。
  static int _findSegments(List<String> haystack, List<String> needle) {
    if (needle.isEmpty || needle.length > haystack.length) return -1;
    for (var i = 0; i <= haystack.length - needle.length; i++) {
      var matched = true;
      for (var j = 0; j < needle.length; j++) {
        if (haystack[i + j] != needle[j]) {
          matched = false;
          break;
        }
      }
      if (matched) return i;
    }
    return -1;
  }

  static String? _firstTag(String xml, String localName) {
    final match = RegExp(
      '<(?:\\w+:)?$localName\\b[^>]*>([\\s\\S]*?)</(?:\\w+:)?$localName>',
      caseSensitive: false,
    ).firstMatch(xml);
    return match?.group(1)?.trim();
  }

  static DateTime? _parseHttpDate(String? value) {
    if (value == null || value.isEmpty) return null;
    try {
      return HttpDate.parse(value);
    } catch (_) {
      try {
        return DateTime.parse(value);
      } catch (_) {
        return null;
      }
    }
  }

  WebDavException _statusError(int status) {
    switch (status) {
      case 401:
        return const WebDavException('WebDAV 认证失败，请检查账号与密码（401）');
      case 403:
        return const WebDavException('WebDAV 拒绝访问，可能触发了服务商限流（403）');
      case 404:
        return const WebDavException('云端路径不存在（404）');
      case 409:
        return const WebDavException('云端目录冲突或父目录不存在（409）');
      case 423:
        return const WebDavException('云端文件被锁定（423）');
      case 507:
        return const WebDavException('云端空间不足（507）');
      default:
        return WebDavException('WebDAV 请求失败（HTTP $status）');
    }
  }
}