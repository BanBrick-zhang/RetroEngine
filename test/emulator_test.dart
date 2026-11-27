import 'package:flutter_test/flutter_test.dart';
import 'package:savedeck_toolkit/data/emulator_catalog.dart';
import 'package:savedeck_toolkit/data/pinyin_initials.dart';
import 'package:savedeck_toolkit/models/emulator.dart';

void main() {
  group('拼音首字母', () {
    test('汉字取第一个字的拼音首字母', () {
      expect(PinyinInitials.of('最终幻想'), 'Z');
      expect(PinyinInitials.of('塞尔达传说'), 'S');
      expect(PinyinInitials.of('口袋妖怪'), 'K');
      expect(PinyinInitials.of('勇者斗恶龙'), 'Y');
    });

    test('拉丁字母大写、数字与符号归入 #', () {
      expect(PinyinInitials.of('mario'), 'M');
      expect(PinyinInitials.of('  Zelda'), 'Z');
      expect(PinyinInitials.of('123'), '#');
      expect(PinyinInitials.of(''), '#');
      expect(PinyinInitials.of('★'), '#');
    });

    test('混合文本跳过无法识别的字符', () {
      expect(PinyinInitials.of('★最终幻想'), 'Z');
      expect(PinyinInitials.of('3 马里奥'), '#');
    });
  });

  group('模拟器目录', () {
    test('平台别名归一到标准平台名', () {
      expect(emulatorPlatformKey('GBA'), 'GBA');
      expect(emulatorPlatformKey('gba'), 'GBA');
    });

    test('GBA/GB/GBC/FC/SFC 默认推荐 RetroArch', () {
      for (final platform in <String>['GBA', 'GB', 'GBC', 'FC', 'SFC']) {
        final candidates = emulatorCandidates(platform);
        expect(candidates.any((c) => c.mode == LaunchMode.retroArch), isTrue,
            reason: platform);
      }
      expect(coresFor('GBA').first, 'mgba_libretro_android.so');
    });

    test('PS1 同时提供 RetroArch 与 DuckStation', () {
      final packages = emulatorCandidates('PSX').map((c) => c.packageName);
      expect(packages.any((p) => p.startsWith('com.retroarch')), isTrue);
      expect(packages, contains('com.github.stenzek.duckstation'));
    });

    test('3DS/PS2/PSP 的推荐模拟器', () {
      final n3ds = emulatorCandidates('3DS').map((c) => c.packageName);
      expect(n3ds, contains('org.citra_emu.citra'));
      expect(n3ds, contains('org.azahar_emu.azahar'));

      final ps2 = emulatorCandidates('PS2');
      expect(ps2.map((c) => c.packageName), contains('org.pcsx2.pcsx2'));
      expect(ps2.map((c) => c.packageName), contains('xyz.aethersx2.android'));
      // PS2 模拟器只认 bootPath，不能退化成 ACTION_VIEW。
      for (final candidate in ps2) {
        if (candidate.packageName == 'org.pcsx2.pcsx2' ||
            candidate.packageName == 'xyz.aethersx2.android') {
          expect(candidate.mode, LaunchMode.aetherSx2);
        }
      }

      final psp = emulatorCandidates('PSP').map((c) => c.packageName);
      expect(psp, contains('org.ppsspp.ppsspp'));
    });

    test('ROM 扩展名映射 MIME', () {
      expect(mimeTypeForRom('/a/b/game.gba'), 'application/x-gba-rom');
      expect(mimeTypeForRom('/a/b/game.iso'), 'application/octet-stream');
      expect(mimeTypeForRom('/a/b/game.unknown'), '*/*');
    });
  });

  group('EmulatorConfig 序列化', () {
    test('JSON 往返保留核心与启动方式', () {
      const config = EmulatorConfig(
        label: 'RetroArch (64 位)',
        packageName: 'com.retroarch.aarch64',
        activity: retroArchActivity,
        mode: LaunchMode.retroArch,
        core: 'mgba_libretro_android.so',
      );
      final restored = EmulatorConfig.fromJson(config.toJson());
      expect(restored.label, config.label);
      expect(restored.packageName, config.packageName);
      expect(restored.activity, config.activity);
      expect(restored.mode, LaunchMode.retroArch);
      expect(restored.core, config.core);
    });

    test('未知启动方式退回直接打开应用', () {
      final config = EmulatorConfig.fromJson(<String, dynamic>{
        'label': 'PPSSPP',
        'package': 'org.ppsspp.ppsspp',
        'mode': 'unknown',
      });
      expect(config.mode, LaunchMode.app);
    });

    test('启动方式线上标识为全小写，且能双向解析', () {
      expect(LaunchMode.retroArch.wireName, 'retroarch');
      expect(LaunchMode.aetherSx2.wireName, 'aethersx2');
      expect(LaunchMode.view.wireName, 'view');
      expect(LaunchMode.app.wireName, 'app');

      for (final mode in LaunchMode.values) {
        expect(launchModeFromName(mode.wireName), mode);
        expect(launchModeFromName(mode.name), mode);
      }
    });

    test('旧配置中的 ACTION_VIEW 升级为 AetherSX2 启动方式', () {
      const legacy = EmulatorConfig(
        label: 'AetherSX2',
        packageName: 'xyz.aethersx2.android',
        mode: LaunchMode.view,
      );
      final upgraded = upgradeLegacyConfig(legacy);
      expect(upgraded, isNotNull);
      expect(upgraded!.mode, LaunchMode.aetherSx2);
      expect(upgraded.packageName, legacy.packageName);

      const ppsspp = EmulatorConfig(
        label: 'PPSSPP',
        packageName: 'org.ppsspp.ppsspp',
        mode: LaunchMode.view,
      );
      expect(upgradeLegacyConfig(ppsspp), isNull);
    });
  });
}