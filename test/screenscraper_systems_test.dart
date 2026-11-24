import 'package:flutter_test/flutter_test.dart';
import 'package:savedeck_toolkit/data/screenscraper_systems.dart';
import 'package:savedeck_toolkit/models/library.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await ScreenscraperSystems.load();
  });

  test('平台表可从 assets 加载', () {
    expect(ScreenscraperSystems.isLoaded, true);
    expect(ScreenscraperSystems.systems.length, greaterThan(100));
  });

  test('按平台代码/目录名/别名解析 systemeid', () {
    expect(ScreenscraperSystems.resolveId('GBA'), 12);
    expect(ScreenscraperSystems.resolveId('PSX'), 57);
    expect(ScreenscraperSystems.resolveId('nes'), 3);
    expect(ScreenscraperSystems.resolveId('game boy advance'), 12);
  });

  test('新表未收录的别名回退到内置平台表', () {
    expect(PlatformCatalog.ssIdFor('FC'), 3);
  });

  test('按扩展名解析 systemeid，歧义时返回 null', () {
    expect(ScreenscraperSystems.resolveByExtensions(<String>['gba']), 12);
    // bin 同时属于大量平台，不应武断猜测。
    expect(ScreenscraperSystems.resolveByExtensions(<String>['bin']), null);
  });
}
