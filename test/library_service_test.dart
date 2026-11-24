import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:savedeck_toolkit/services/library_service.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('sd_library_test_');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('无 savedeck.toml 的平台目录按扩展名识别 ROM', () async {
    final gba = Directory(p.join(root.path, 'GBA'))..createSync(recursive: true);
    File(p.join(gba.path, 'Mario Advance.gba')).writeAsStringSync('rom');
    File(p.join(gba.path, 'Pokemon Emerald.gba')).writeAsStringSync('rom');
    File(p.join(gba.path, 'readme.txt')).writeAsStringSync('note');

    final libraries = await LibraryService.loadLibrary(root.path);

    expect(libraries.length, 1);
    expect(libraries.first.platform, 'GBA');
    expect(libraries.first.hasToml, false);
    expect(
      libraries.first.games.map((game) => game.name).toList(),
      containsAll(<String>['Mario Advance', 'Pokemon Emerald']),
    );
    expect(
      libraries.first.games.every((game) => game.file.endsWith('.gba')),
      true,
    );
  });

  test('目录名无法识别时按 ROM 扩展名推断平台', () async {
    final dir = Directory(p.join(root.path, 'My Handhelds'))
      ..createSync(recursive: true);
    File(p.join(dir.path, 'Metroid.gba')).writeAsStringSync('rom');
    File(p.join(dir.path, 'Zelda.gba')).writeAsStringSync('rom');

    final libraries = await LibraryService.loadLibrary(root.path);

    expect(libraries.length, 1);
    expect(libraries.first.platform, 'GBA');
    expect(libraries.first.hasToml, false);
  });

  test('有 savedeck.toml 时读取配置并保留媒体资源路径', () async {
    final dir = Directory(p.join(root.path, 'GBA'))..createSync(recursive: true);
    File(p.join(dir.path, 'savedeck.toml')).writeAsStringSync('''
format_version = 1
platform = "GBA"

[[games]]
name = "示例游戏"
file = "示例游戏.gba"
cover = "media/示例游戏/cover.png"
video = "media/示例游戏/video.mp4"
''');
    File(p.join(dir.path, '示例游戏.gba')).writeAsStringSync('rom');
    File(p.join(dir.path, '未登记.gba')).writeAsStringSync('rom');
    final media = Directory(p.join(dir.path, 'media', '示例游戏'))
      ..createSync(recursive: true);
    File(p.join(media.path, 'cover.png')).writeAsBytesSync(<int>[1, 2, 3]);

    final libraries = await LibraryService.loadLibrary(root.path);

    expect(libraries.length, 1);
    expect(libraries.first.hasToml, true);
    expect(libraries.first.games.length, 2);
    expect(libraries.first.games.first.cover, 'media/示例游戏/cover.png');
    expect(
      File(p.join(dir.path, libraries.first.games.first.cover!)).existsSync(),
      true,
    );
  });

  test('同名 bin 与 cue 只保留 cue 条目', () async {
    final dir = Directory(p.join(root.path, 'PSX'))..createSync(recursive: true);
    File(p.join(dir.path, 'Game.bin')).writeAsStringSync('data');
    File(p.join(dir.path, 'Game.cue')).writeAsStringSync('cue');

    final roms = await LibraryService.scanRomFiles(dir.path);

    expect(roms, <String>['Game.cue']);
  });

  test('识别 ES-DE 平台扩展名与压缩格式', () async {
    final dir = Directory(p.join(root.path, 'NES'))..createSync(recursive: true);
    File(p.join(dir.path, 'Game1.unif')).writeAsStringSync('rom');
    File(p.join(dir.path, 'Game2.fig')).writeAsStringSync('rom');
    File(p.join(dir.path, 'Game3.zip')).writeAsStringSync('rom');
    File(p.join(dir.path, 'Game4.7z')).writeAsStringSync('rom');

    final libraries = await LibraryService.loadLibrary(root.path);

    expect(libraries.length, 1);
    expect(libraries.first.platform, 'FC');
    expect(libraries.first.games.length, 4);
  });

  test('识别罕见扩展名（兜底）但忽略文档与媒体文件', () async {
    final dir = Directory(p.join(root.path, 'MyRoms'))..createSync(recursive: true);
    File(p.join(dir.path, 'Game.unknownFormat')).writeAsStringSync('rom');
    File(p.join(dir.path, 'readme.txt')).writeAsStringSync('doc');
    File(p.join(dir.path, 'cover.png')).writeAsBytesSync(<int>[1, 2, 3]);

    final roms = await LibraryService.scanRomFiles(dir.path, platformName: 'MyRoms');

    expect(roms, <String>['Game.unknownFormat']);
  });

  test('诊断方法返回 ROM 与忽略的扩展名统计', () async {
    final dir = Directory(p.join(root.path, 'GBA'))..createSync(recursive: true);
    File(p.join(dir.path, 'Game.gba')).writeAsStringSync('rom');
    File(p.join(dir.path, 'note.txt')).writeAsStringSync('doc');

    final info = await LibraryService.inspectPlatform(dir.path);

    expect(info['total'], 2);
    expect(info['romExtensions'], contains('gba'));
    expect(info['ignoredExtensions'], contains('txt'));
  });

  test('跳过 media 目录与隐藏 ROM 文件', () async {
    final dir = Directory(p.join(root.path, 'GBA'))..createSync(recursive: true);
    final media = Directory(p.join(dir.path, 'media'))..createSync(recursive: true);
    File(p.join(media.path, 'cover.gba')).writeAsStringSync('fake');
    File(p.join(dir.path, '.hidden.gba')).writeAsStringSync('hidden');
    File(p.join(dir.path, 'Real Game.gba')).writeAsStringSync('rom');

    final roms = await LibraryService.scanRomFiles(dir.path);

    expect(roms, <String>['Real Game.gba']);
  });
}
