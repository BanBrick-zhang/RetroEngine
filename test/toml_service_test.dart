import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:savedeck_toolkit/models/library.dart';
import 'package:savedeck_toolkit/services/toml_service.dart';

void main() {
  const officialSample = '''
format_version = 1
platform = "GBA"
sort = "002"

[[games]]
name = "示例游戏"
file = "示例游戏.gba"
sort = "001"
id = "7ca294ab-8018-45cd-9fc7-481d6b504bb3"
description = "这款游戏的简介，可以填写玩法、剧情或版本说明。"
cover = "media/示例游戏/cover.png"
video = "media/示例游戏/video.mp4"

[[games]]
name = "另一款游戏"
file = "另一款游戏.gba"
''';

  test('解析官方 SaveDeck.toml 示例', () {
    final doc = TomlService.parse(officialSample);
    expect(doc.formatVersion, 1);
    expect(doc.platform, 'GBA');
    expect(doc.sort, '002');
    expect(doc.games.length, 2);

    final first = doc.games.first;
    expect(first['name'], '示例游戏');
    expect(first['file'], '示例游戏.gba');
    expect(first['sort'], '001');
    expect(first['id'], '7ca294ab-8018-45cd-9fc7-481d6b504bb3');
    expect(first['cover'], 'media/示例游戏/cover.png');
    expect(first['video'], 'media/示例游戏/video.mp4');
    expect((first['description'] as String).contains('简介'), true);

    final second = doc.games[1];
    expect(second['name'], '另一款游戏');
    expect(second.containsKey('cover'), false);
  });

  test('序列化后再次解析保持一致', () {
    final doc = TomlService.parse(officialSample);
    final library = PlatformLibrary(
      directory: '/tmp/GBA',
      platform: doc.platform,
      formatVersion: doc.formatVersion,
      sort: doc.sort,
      games: doc.games.map(GameEntry.fromMap).toList(),
      extras: doc.extras,
    );
    final text = TomlService.serialize(library);
    final reparsed = TomlService.parse(text);

    expect(reparsed.platform, 'GBA');
    expect(reparsed.games.length, 2);
    expect(reparsed.games.first['cover'], 'media/示例游戏/cover.png');
    expect(reparsed.games.first['description'], doc.games.first['description']);
    expect(text.contains('format_version = 1'), true);
    expect(text.contains('[[games]]'), true);
  });

  test('空平台写为 games = []', () {
    final library = PlatformLibrary(directory: '/tmp/FC', platform: 'FC');
    final text = TomlService.serialize(library);
    expect(text.contains('games = []'), true);
    final reparsed = TomlService.parse(text);
    expect(reparsed.games.isEmpty, true);
  });

  test('支持多行简介字符串', () {
    const sample = '''
platform = "FC"
[[games]]
name = "重装机兵"
file = "重装机兵.zip"
description = """第一行
第二行 # 这里不应被当作注释"""
''';
    final doc = TomlService.parse(sample);
    expect(doc.games.first['name'], '重装机兵');
    final description = doc.games.first['description'] as String;
    expect(description.contains('第一行'), true);
    expect(description.contains('第二行 # 这里不应被当作注释'), true);

    final library = PlatformLibrary(
      directory: '/tmp/FC',
      platform: doc.platform,
      games: doc.games.map(GameEntry.fromMap).toList(),
    );
    final reparsed = TomlService.parse(TomlService.serialize(library));
    expect((reparsed.games.first['description'] as String).contains('第二行'), true);
  });

  test('容错读取 GBK 编码的 TOML', () async {
    final dir = await Directory.systemTemp.createTemp('gbk_toml_');
    try {
      final file = File('${dir.path}${Platform.pathSeparator}savedeck.toml');
      final bytes = <int>[];
      bytes.addAll(utf8.encode('platform = "GBA"\n[[games]]\nname = "'));
      bytes.addAll(<int>[0xD6, 0xD0, 0xCE, 0xC4]); // GBK "中文"
      bytes.addAll(utf8.encode('"\nfile = "a.gba"\n'));
      await file.writeAsBytes(bytes);

      final library = await TomlService.load(dir.path);
      expect(library.platform, 'GBA');
      expect(library.games.length, 1);
      expect(library.games.first.file, 'a.gba');
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('支持 games 内联表数组写法', () {
    const sample = '''
platform = "GBA"
games = [{ name = "游戏A", file = "a.gba" }, { name = "游戏B", file = "b.gba" }]
''';
    final doc = TomlService.parse(sample);
    expect(doc.games.length, 2);
    expect(doc.games.first['name'], '游戏A');
    expect(doc.games[1]['file'], 'b.gba');
  });

  test('开发商、日期与附加资源字段可写入并读回', () {
    final game = GameEntry(
      name: '最终幻想',
      file: 'ff.gba',
      developer: 'Square',
      releaseDate: '1994-04-02',
      wheel: 'media/最终幻想/wheel.png',
      boxTexture: 'media/最终幻想/box-texture.png',
      box3D: 'media/最终幻想/box-3D.png',
      support2D: 'media/最终幻想/support-2D.png',
      fanart: 'media/最终幻想/fanart.jpg',
      mixrbv: 'media/最终幻想/mixrbv.png',
    );
    final library = PlatformLibrary(
      directory: '/tmp/GBA',
      platform: 'GBA',
      games: <GameEntry>[game],
    );
    final text = TomlService.serialize(library);

    expect(text.contains('developpeur = "Square"'), true);
    expect(text.contains('dates = "1994-04-02"'), true);
    expect(text.contains('box-texture = "media/最终幻想/box-texture.png"'), true);
    expect(text.contains('support-2D = "media/最终幻想/support-2D.png"'), true);

    final reparsed = TomlService.parse(text).games.map(GameEntry.fromMap).single;
    expect(reparsed.developer, 'Square');
    expect(reparsed.releaseDate, '1994-04-02');
    expect(reparsed.wheel, 'media/最终幻想/wheel.png');
    expect(reparsed.boxTexture, 'media/最终幻想/box-texture.png');
    expect(reparsed.box3D, 'media/最终幻想/box-3D.png');
    expect(reparsed.support2D, 'media/最终幻想/support-2D.png');
    expect(reparsed.fanart, 'media/最终幻想/fanart.jpg');
    expect(reparsed.mixrbv, 'media/最终幻想/mixrbv.png');
    // 已识别字段不应重复进入 extras。
    expect(reparsed.extras.keys, isNot(contains('box-texture')));
  });

  test('保留未知字段', () {
    const sample = '''
platform = "GBA"
custom_field = "keep-me"
[[games]]
name = "测试"
file = "test.gba"
custom_game_field = "game-value"
''';
    final doc = TomlService.parse(sample);
    expect(doc.extras['custom_field'], 'keep-me');
    expect(doc.games.first['custom_game_field'], 'game-value');
    final library = PlatformLibrary(
      directory: '/tmp/GBA',
      platform: doc.platform,
      games: doc.games.map(GameEntry.fromMap).toList(),
      extras: doc.extras,
    );
    final text = TomlService.serialize(library);
    expect(text.contains('custom_field = "keep-me"'), true);
    expect(text.contains('custom_game_field = "game-value"'), true);
  });
}
