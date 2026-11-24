import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';

import '../models/library.dart';
import 'toml_service.dart';

/// 文件系统与权限相关的服务。
class LibraryService {
  static const String tomlFileName = TomlService.fileName;
  static const MethodChannel _permissionChannel =
      MethodChannel('com.savedeck.toolkit/permission');

  static int? _cachedSdkInt;

  /// 当前 Android SDK 版本（API Level）。取不到时返回 0，调用方按“未知”处理。
  static Future<int> androidSdkInt() async {
    if (!Platform.isAndroid) return 0;
    final cached = _cachedSdkInt;
    if (cached != null && cached > 0) return cached;
    try {
      final value = await _permissionChannel.invokeMethod<int>('sdkInt');
      if (value != null && value > 0) {
        _cachedSdkInt = value;
        return value;
      }
    } catch (_) {}
    return 0;
  }

  /// 请求文件访问权限（Android 11+ 需要“所有文件访问权限”）。
  ///
  /// 注意：MANAGE_EXTERNAL_STORAGE 无法通过运行时弹窗授予，只能跳转到系统
  /// 设置页由用户手动打开，因此这里不强制跳转（避免打断启动），
  /// 由绑定目录时的授权引导负责。仅 API 29 及以下尝试传统存储权限。
  static Future<bool> ensureStoragePermission() async {
    if (!Platform.isAndroid) return true;
    if (await hasAllFilesAccessNative()) return true;

    final sdk = await androidSdkInt();
    // Android 11（API 30）起共享存储只能靠 MANAGE_EXTERNAL_STORAGE 访问；
    // 传统 READ/WRITE_EXTERNAL_STORAGE 在 Android 13 上已失效。
    if (sdk > 0 && sdk < 30) {
      try {
        final legacy = await Permission.storage.request();
        if (legacy.isGranted) return true;
      } catch (_) {
        // 部分 ROM 上 request 可能抛异常，忽略并继续。
      }
    }

    return await hasAllFilesAccessNative();
  }

  /// 是否已具备存储访问权限。
  static Future<bool> hasStorageAccess() async {
    if (!Platform.isAndroid) return true;
    if (await hasAllFilesAccessNative()) return true;

    final sdk = await androidSdkInt();
    // API 30+ 只认“所有文件访问权限”，避免误判为已授权。
    if (sdk >= 30) return false;

    try {
      return await Permission.storage.isGranted;
    } catch (_) {
      // Android 13+ 上 READ_EXTERNAL_STORAGE 已移除，检查可能抛异常，按未授权处理。
      return false;
    }
  }

  /// 直接打开“所有文件访问权限”的系统设置页。
  ///
  /// [openAppSettings] 只会进入应用详情页，那里通常看不到该特殊权限入口；
  /// 必须通过系统 Intent 直达。原生通道失败时再回退到应用详情页。
  static Future<void> requestManageStorageSettings() async {
    if (!Platform.isAndroid) return;
    try {
      final opened = await _permissionChannel
          .invokeMethod<bool>('openAllFilesAccessSettings');
      if (opened == true) return;
    } on MissingPluginException catch (_) {
      // 原生通道不可用时回退。
    } catch (_) {}
    await openAppSettings();
  }

  /// 原生层检查是否拥有“所有文件访问权限”。
  static Future<bool> hasAllFilesAccessNative() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _permissionChannel.invokeMethod<bool>('hasAllFilesAccess') ?? false;
    } catch (_) {
      return await Permission.manageExternalStorage.isGranted;
    }
  }

  /// 目录访问权限的真实检测结果。
  static Future<DirectoryAccessResult> verifyDirectoryAccess(String path) async {
    if (!Platform.isAndroid) {
      return const DirectoryAccessResult(exists: true, canRead: true, canWrite: true);
    }

    final dir = Directory(path);
    bool exists;
    try {
      exists = await dir.exists();
    } catch (_) {
      exists = false;
    }
    if (!exists) {
      return const DirectoryAccessResult(exists: false, canRead: false, canWrite: false);
    }

    // 真实尝试列出目录内容（这是 ROM 扫描能否工作的关键）。
    var canRead = false;
    try {
      await dir.list().firstWhere((_) => true, orElse: () => dir);
      canRead = true;
    } catch (_) {
      canRead = false;
    }

    // 真实尝试在目录内创建并删除一个探针文件，验证写权限。
    var canWrite = false;
    final probe = File(p.join(path, '.savedeck_perm_probe'));
    try {
      await probe.writeAsString('ok');
      canWrite = true;
    } catch (_) {
      canWrite = false;
    } finally {
      try {
        if (await probe.exists()) await probe.delete();
      } catch (_) {}
    }

    return DirectoryAccessResult(
      exists: true,
      canRead: canRead,
      canWrite: canWrite,
      manageGranted: await hasAllFilesAccessNative(),
      legacyGranted: await Permission.storage.isGranted,
    );
  }

  /// 默认起始目录：优先使用共享存储根目录，便于找到游戏库。
  static Future<String> defaultRoot() async {
    const sharedRoot = '/storage/emulated/0';
    if (Platform.isAndroid && await Directory(sharedRoot).exists()) {
      return sharedRoot;
    }
    try {
      final dir = await getExternalStorageDirectory();
      if (dir != null) return dir.path;
    } catch (_) {}
    return sharedRoot;
  }

  /// 列出目录下的子目录与文件（按名称排序，目录在前）。
  static Future<List<FileSystemEntity>> listDirectory(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) return <FileSystemEntity>[];
    final items = await dir.list().toList();
    items.sort((a, b) {
      final aDir = a is Directory;
      final bDir = b is Directory;
      if (aDir != bDir) return aDir ? -1 : 1;
      return p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase());
    });
    return items;
  }

  /// 列出可列出子目录（用于文件浏览器）。
  static Future<List<Directory>> listDirectories(String path) async {
    final items = await listDirectory(path);
    return items.whereType<Directory>().toList();
  }

  /// 诊断平台目录：统计文件总数、识别为 ROM 的数量与被忽略的扩展名。
  static Future<Map<String, dynamic>> inspectPlatform(String platformDir) async {
    var total = 0;
    final romExts = <String>{};
    final ignoredExts = <String>{};
    final platformName = p.basename(platformDir);

    Future<void> walk(Directory dir, int depth) async {
      if (depth > 4) return;
      late final List<FileSystemEntity> entities;
      try {
        entities = await dir.list().toList();
      } catch (_) {
        return;
      }
      for (final entity in entities) {
        final name = p.basename(entity.path);
        if (name.startsWith('.') || name.toLowerCase() == 'media') continue;
        if (entity is Directory) {
          await walk(entity, depth + 1);
        } else if (entity is File) {
          total++;
          final ext = p.extension(entity.path).toLowerCase().replaceFirst('.', '');
          if (isRomFile(entity.path, platformName: platformName)) {
            romExts.add(ext.isEmpty ? '(无扩展名)' : ext);
          } else {
            ignoredExts.add(ext.isEmpty ? '(无扩展名)' : ext);
          }
        }
      }
    }

    await walk(Directory(platformDir), 0);
    return <String, dynamic>{
      'total': total,
      'romExtensions': romExts.toList()..sort(),
      'ignoredExtensions': ignoredExts.toList()..sort(),
    };
  }

  /// 扫描游戏库根目录。
  ///
  /// - 含 savedeck.toml 的目录：读取配置并展示媒体，同时补充尚未登记的 ROM；
  /// - 无配置文件的目录：按 ROM 扩展名自动识别游戏并生成条目（hasToml = false），
  ///   用户搜刮或保存时会自动创建 savedeck.toml。
  static Future<List<PlatformLibrary>> loadLibrary(String rootPath) async {
    final root = Directory(rootPath);
    if (!await root.exists()) return <PlatformLibrary>[];
    final dirs = (await root.list().toList())
        .whereType<Directory>()
        .where((dir) => _isPlatformCandidate(p.basename(dir.path)))
        .toList();
    final libraries = <PlatformLibrary>[];

    for (final dir in dirs) {
      final folderName = p.basename(dir.path);
      final romFiles = await scanRomFiles(dir.path, platformName: folderName);
      final hasToml = await File(p.join(dir.path, tomlFileName)).exists();
      if (!hasToml && romFiles.isEmpty) continue;

      PlatformLibrary library;
      if (hasToml) {
        try {
          library = await TomlService.load(dir.path);
          if (library.platform.isEmpty) {
            library.platform = folderName.toUpperCase();
          }
          final registered = library.games.map((g) => g.file.replaceAll('\\', '/')).toSet();
          for (final relative in romFiles) {
            if (registered.contains(relative)) continue;
            library.games.add(GameEntry(
              name: gameNameFromRom(relative),
              file: relative,
              id: newId(),
            ));
          }
        } catch (e) {
          // 配置文件存在但解析失败：保留 hasToml 状态并记录错误，避免误报“尚未建立”。
          library = _platformFromRoms(dir.path, romFiles);
          library.hasToml = true;
          library.loadError = e.toString();
        }
      } else {
        library = _platformFromRoms(dir.path, romFiles);
      }
      libraries.add(library);
    }

    // 边界情况：用户绑定的目录本身就是平台目录（ROM 与 toml 直接在根目录）。
    // 仅检查根目录下的直接文件，避免把子平台目录的 ROM 重复汇总成一个平台。
    final rootHasToml = await File(p.join(rootPath, tomlFileName)).exists();
    if (libraries.isEmpty && rootHasToml) {
      final rootRoms = <String>[];
      try {
        for (final entity in await root.list().toList()) {
          if (entity is File &&
              isRomFile(entity.path, platformName: p.basename(rootPath))) {
            rootRoms.add(p.basename(entity.path));
          }
        }
      } catch (_) {}
      try {
        libraries.add(await TomlService.load(rootPath));
      } catch (e) {
        final lib = _platformFromRoms(rootPath, rootRoms);
        lib.hasToml = true;
        lib.loadError = e.toString();
        libraries.add(lib);
      }
    }

    libraries.sort((a, b) {
      final aSort = a.sort ?? '';
      final bSort = b.sort ?? '';
      if (aSort != bSort) return aSort.compareTo(bSort);
      return a.platform.compareTo(b.platform);
    });
    return libraries;
  }

  static PlatformLibrary _platformFromRoms(String dirPath, List<String> romFiles) {
    final dirName = p.basename(dirPath);
    final detected = PlatformCatalog.detectPlatform(dirName, romFiles);
    return PlatformLibrary(
      directory: dirPath,
      platform: detected?.name ?? dirName.toUpperCase(),
      games: romFiles
          .map((relative) => GameEntry(
                name: gameNameFromRom(relative),
                file: relative,
                id: newId(),
              ))
          .toList(),
      hasToml: false,
    );
  }

  static bool _isPlatformCandidate(String name) {
    if (name.startsWith('.')) return false;
    const excluded = <String>{
      'media', 'android', 'lost.dir', 'system volume information', '\$recycle.bin',
    };
    return !excluded.contains(name.toLowerCase());
  }

  /// 判断文件是否可能是 ROM（使用 ES-DE 权威扩展名表）。
  static bool isRomFile(String path, {String? platformName}) =>
      PlatformCatalog.isRomForPlatform(path, platformName);

  /// 递归扫描平台目录中的 ROM，返回相对于平台目录的路径（使用 `/`）。
  ///
  /// 跳过 media 目录与隐藏文件；同一游戏存在同名 .cue 时忽略 .bin，避免重复条目。
  static Future<List<String>> scanRomFiles(
    String platformDir, {
    int maxDepth = 4,
    String? platformName,
  }) async {
    final found = <String>[];

    Future<void> walk(Directory dir, int depth) async {
      if (depth > maxDepth) return;
      late final List<FileSystemEntity> entities;
      try {
        entities = await dir.list().toList();
      } catch (_) {
        return;
      }
      for (final entity in entities) {
        final name = p.basename(entity.path);
        if (name.startsWith('.') || name.toLowerCase() == 'media') continue;
        if (entity is Directory) {
          await walk(entity, depth + 1);
        } else if (entity is File && isRomFile(entity.path, platformName: platformName)) {
          found.add(p.relative(entity.path, from: platformDir).replaceAll('\\', '/'));
        }
      }
    }

    await walk(Directory(platformDir), 0);
    found.sort();

    // 同名 .bin + .cue / .chd 等多碟镜像只保留一个主条目。
    final discBases = found
        .where((path) => const <String>{'.cue', '.chd', '.m3u', '.toc'}
            .contains(p.extension(path).toLowerCase()))
        .map((path) => path.substring(0, path.length - p.extension(path).length))
        .toSet();
    return found.where((path) {
      if (p.extension(path).toLowerCase() != '.bin') return true;
      return !discBases.contains(path.substring(0, path.length - 4));
    }).toList();
  }

  /// 创建一个新平台目录及空的 savedeck.toml。
  static Future<PlatformLibrary> createPlatform(String rootPath, String name) async {
    final dir = Directory(p.join(rootPath, name));
    await dir.create(recursive: true);
    final library = PlatformLibrary(directory: dir.path, platform: name.toUpperCase());
    await TomlService.save(library);
    return library;
  }

  /// 将 ROM 复制到平台目录，返回相对路径（ savedeck.toml 的 file 字段值）。
  static Future<String> copyRomToPlatform(String sourcePath, PlatformLibrary platform) async {
    // 源文件已在目标平台目录（含子目录）内时直接引用，不重复复制。
    if (p.isWithin(platform.directory, sourcePath)) {
      return p.relative(sourcePath, from: platform.directory).replaceAll('\\', '/');
    }
    final fileName = p.basename(sourcePath);
    final dest = File(p.join(platform.directory, fileName));
    if (p.equals(sourcePath, dest.path)) return fileName;

    var target = dest;
    var counter = 1;
    while (await target.exists()) {
      final ext = p.extension(fileName);
      final base = p.basenameWithoutExtension(fileName);
      target = File(p.join(platform.directory, '$base ($counter)$ext'));
      counter++;
    }
    await File(sourcePath).copy(target.path);
    return p.basename(target.path);
  }

  /// 把 ROM 重命名为游戏名，保留原扩展名与所在子目录，返回新的相对路径。
  /// 目标文件已存在时自动追加序号，避免覆盖其他 ROM。
  static Future<String> renameRomFile(
    PlatformLibrary platform,
    GameEntry game,
    String newName,
  ) async {
    final relative = game.file.replaceAll('\\', '/');
    final source = File(p.join(platform.directory, relative));
    if (!await source.exists()) return relative;

    final base = _safeName(newName);
    if (base.isEmpty) return relative;
    final extension = p.extension(relative);
    final parent = p.dirname(relative);
    final directory = parent == '.' ? '' : parent;

    String targetRelative(String name) =>
        p.join(directory, '$name$extension').replaceAll('\\', '/');

    var candidate = targetRelative(base);
    var target = File(p.join(platform.directory, candidate));
    var counter = 1;
    while (await target.exists() && !p.equals(source.path, target.path)) {
      candidate = targetRelative('$base ($counter)');
      target = File(p.join(platform.directory, candidate));
      counter++;
    }
    if (p.equals(source.path, target.path)) return relative;

    await source.rename(target.path);
    return candidate;
  }

  /// 为游戏创建媒体目录并返回其绝对路径。
  static Future<Directory> mediaDirectory(PlatformLibrary platform, String gameName) async {
    final dir = Directory(p.join(platform.directory, 'media', _safeName(gameName)));
    await dir.create(recursive: true);
    return dir;
  }

  /// 计算游戏媒体相对路径。
  static String mediaRelativePath(String gameName, String fileName) =>
      p.join('media', _safeName(gameName), fileName).replaceAll('\\', '/');

  /// 把媒体目录重命名为新游戏名，并同步修正 cover/video 相对路径。
  /// 目标目录已存在时合并文件后删除旧目录，不覆盖已有文件。
  static Future<GameEntry> renameMediaDirectory(
    PlatformLibrary platform,
    GameEntry game,
    String oldName,
    String newName,
  ) async {
    final oldSafe = _safeName(oldName);
    final newSafe = _safeName(newName);
    if (oldSafe == newSafe) return game;
    final oldDir = Directory(p.join(platform.directory, 'media', oldSafe));
    if (!await oldDir.exists()) return game;
    final newDir = Directory(p.join(platform.directory, 'media', newSafe));

    if (await newDir.exists()) {
      for (final entity in await oldDir.list().toList()) {
        if (entity is File) {
          final target = File(p.join(newDir.path, p.basename(entity.path)));
          if (!await target.exists()) await entity.copy(target.path);
        }
      }
      await oldDir.delete(recursive: true);
    } else {
      await oldDir.rename(newDir.path);
    }

    String? fix(String? value) =>
        value?.replaceFirst('media/$oldSafe/', 'media/$newSafe/');
    return game.copyWith(
      cover: fix(game.cover),
      video: fix(game.video),
      clearCover: game.cover == null,
      clearVideo: game.video == null,
    );
  }

  static String _safeName(String name) {
    return name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  }

  /// 删除游戏对应的媒体目录。
  static Future<void> removeMedia(PlatformLibrary platform, String gameName) async {
    final dir = Directory(p.join(platform.directory, 'media', _safeName(gameName)));
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  /// 按类型删除媒体文件；目录内没有剩余文件时一并删除目录。
  static Future<void> deleteMediaFiles(
    PlatformLibrary platform,
    String gameName, {
    bool cover = false,
    bool video = false,
  }) async {
    final dir = Directory(p.join(platform.directory, 'media', _safeName(gameName)));
    if (!await dir.exists()) return;
    if (cover) {
      for (final ext in const <String>['png', 'jpg', 'jpeg', 'webp']) {
        final file = File(p.join(dir.path, 'cover.$ext'));
        if (await file.exists()) await file.delete();
      }
    }
    if (video) {
      for (final ext in const <String>['mp4', 'webm', 'avi']) {
        final file = File(p.join(dir.path, 'video.$ext'));
        if (await file.exists()) await file.delete();
      }
    }
    if ((await dir.list().toList()).isEmpty) await dir.delete();
  }

  /// 下载远程文件到本地。
  static Future<File> downloadFile(
    String url,
    String destination, {
    Map<String, String>? headers,
    void Function(int received, int? total)? onProgress,
  }) async {
    final request = await http.Client().get(Uri.parse(url), headers: headers);
    if (request.statusCode != 200) {
      throw HttpException('HTTP ${request.statusCode}', uri: Uri.parse(url));
    }
    final file = File(destination);
    await file.parent.create(recursive: true);
    final totalBytes = request.contentLength;
    var received = 0;
    final sink = file.openWrite();
    for (final chunk in request.bodyBytes) {
      sink.add(<int>[chunk]);
      received++;
      onProgress?.call(received, totalBytes);
    }
    await sink.close();
    return file;
  }

  /// 流式下载大文件（视频），避免一次性占用过多内存。
  static Future<File> downloadStream(
    String url,
    String destination, {
    Map<String, String>? headers,
    void Function(int received, int? total)? onProgress,
  }) async {
    final client = http.Client();
    final request = http.Request('GET', Uri.parse(url));
    if (headers != null) request.headers.addAll(headers);
    final response = await client.send(request);
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode}', uri: Uri.parse(url));
    }
    final file = File(destination);
    await file.parent.create(recursive: true);
    final sink = file.openWrite();
    var received = 0;
    final total = response.contentLength;
    await for (final chunk in response.stream) {
      sink.add(chunk);
      received += chunk.length;
      onProgress?.call(received, total);
    }
    await sink.close();
    client.close();
    return file;
  }

  /// 计算文件 SHA1（小写十六进制）。
  static Future<String> sha1(String path) async {
    final bytes = await File(path).readAsBytes();
    return crypto.sha1.convert(bytes).toString();
  }

  /// 计算文件 MD5（小写十六进制）。
  static Future<String> md5(String path) async {
    final bytes = await File(path).readAsBytes();
    return crypto.md5.convert(bytes).toString();
  }

  /// 计算 CRC32（大写十六进制，ScreenScraper 要求）。
  static Future<String> crc32(String path) async {
    final bytes = await File(path).readAsBytes();
    var crc = 0xFFFFFFFF;
    for (final byte in bytes) {
      crc ^= byte;
      for (var i = 0; i < 8; i++) {
        crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
      }
    }
    final value = (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
    return value.toRadixString(16).toUpperCase().padLeft(8, '0');
  }

  /// 获取文件大小。
  static Future<int> fileSize(String path) async => await File(path).length();

  /// 生成符合 savedeck 规范的 UUID。
  static String newId() => const Uuid().v4().toLowerCase();

  /// 判断文件是否为压缩包（需要先按文件名匹配）。
  static bool isArchive(String path) {
    final ext = p.extension(path).toLowerCase();
    return const <String>{'.zip', '.7z', '.rar', '.tar', '.gz'}.contains(ext);
  }

  /// 从 ROM 文件名推断较干净的游戏名（去掉地区/版本标记）。
  static String gameNameFromRom(String path) {
    var name = p.basenameWithoutExtension(path);
    name = name.replaceAll(RegExp(r'\s*\(.*?\)\s*'), ' ');
    name = name.replaceAll(RegExp(r'\s*\[.*?\]\s*'), ' ');
    name = name.replaceAll(RegExp(r'\s*\(.*$'), ' ');
    return name.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// 读取图片缩略图构建缓存键时使用的字节（小文件直接读取）。
  static Future<Uint8List?> readIfExists(String path) async {
    final file = File(path);
    if (!await file.exists()) return null;
    try {
      return await file.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  /// 将字节写入文本文件（用于调试/导出）。
  static Future<void> writeText(String path, String content) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(content, encoding: utf8);
  }
}
