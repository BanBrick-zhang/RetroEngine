import 'package:flutter_test/flutter_test.dart';
import 'package:savedeck_toolkit/services/screenscraper_service.dart';

void main() {
  test('buildApiUrl 使用 %20 编码空格而非 +', () {
    final uri = ScreenscraperService.buildApiUrl('jeuRecherche.php', <String, String>{
      'recherche': 'Super Mario Bros.',
      'sspassword': 'a b+c',
    });

    expect(uri.toString(), contains('jeuRecherche.php'));
    expect(uri.toString(), contains('recherche=Super%20Mario%20Bros.'));
    expect(uri.toString(), contains('sspassword=a%20b%2Bc'));
    expect(uri.toString(), isNot(contains('+')));
  });

  test('源码不内置开发者凭据', () {
    // 未通过 --dart-define 或构造参数提供凭据时，应直接报错而不是使用硬编码值。
    expect(
      () => ScreenscraperService(),
      throwsA(isA<SsException>()),
    );
  });

  test('开发者凭据由构造参数提供，默认语言为 en', () {
    final service = ScreenscraperService(
      devId: 'test-dev-id',
      devPassword: 'test-dev-pass',
    );
    expect(service.devIdOverride, 'test-dev-id');
    expect(service.devPasswordOverride, 'test-dev-pass');
    expect(service.preferredLanguage, 'en');
  });

  test('未配置账号时匿名访问，不携带 ssid/sspassword', () {
    final service = ScreenscraperService(
      devId: 'test-dev-id',
      devPassword: 'test-dev-pass',
    );
    expect(service.username, '');
    expect(service.password, '');
    expect(service.hasUserAccount, false);

    final auth = service.authForTesting;
    expect(auth['devid'], 'test-dev-id');
    expect(auth['devpassword'], 'test-dev-pass');
    expect(auth.containsKey('softname'), false);
    expect(auth['output'], 'json');
    expect(auth.containsKey('ssid'), false);
    expect(auth.containsKey('sspassword'), false);
  });

  test('配置账号后携带 ssid/sspassword', () {
    final service = ScreenscraperService(
      username: 'testuser',
      password: 'testpass',
      devId: 'test-dev-id',
      devPassword: 'test-dev-pass',
    );
    expect(service.hasUserAccount, true);

    final auth = service.authForTesting;
    expect(auth['ssid'], 'testuser');
    expect(auth['sspassword'], 'testpass');
  });

  group('封面媒体选择只取正面大图', () {
    test('即使侧边图区域优先级更高，也只选 box-2D 正面', () {
      final picked = ScreenscraperService.pickMedia(
        <dynamic>[
          <String, dynamic>{
            'type': 'box-2D-side',
            'region': 'wor',
            'url': 'https://example.com/side.png',
          },
          <String, dynamic>{
            'type': 'box-2D',
            'region': 'eu',
            'url': 'https://example.com/front.png',
          },
        ],
        const <String>['box-2D', 'box-3D'],
      );
      expect(picked?['url'], 'https://example.com/front.png');
    });

    test('背面 box-2D-back 同样被排除', () {
      final picked = ScreenscraperService.pickMedia(
        <dynamic>[
          <String, dynamic>{
            'type': 'box-2D-back',
            'region': 'wor',
            'url': 'https://example.com/back.png',
          },
          <String, dynamic>{
            'type': 'box-2D-side',
            'region': 'us',
            'url': 'https://example.com/spine.png',
          },
        ],
        const <String>['box-2D', 'box-3D'],
      );
      expect(picked, isNull);
    });

    test('没有 box-2D 时回退到 box-3D 正面盒绘', () {
      final picked = ScreenscraperService.pickMedia(
        <dynamic>[
          <String, dynamic>{
            'type': 'box-2D-side',
            'region': 'wor',
            'url': 'https://example.com/side.png',
          },
          <String, dynamic>{
            'type': 'box-3D',
            'region': 'us',
            'url': 'https://example.com/front3d.png',
          },
        ],
        const <String>['box-2D', 'box-3D'],
      );
      expect(picked?['url'], 'https://example.com/front3d.png');
    });

    test('类型大小写、下划线写法归一化后仍精确命中正面', () {
      final picked = ScreenscraperService.pickMedia(
        <dynamic>[
          <String, dynamic>{
            'type': 'BOX_2D',
            'region': 'wor',
            'url': 'https://example.com/front.png',
          },
        ],
        const <String>['box-2D'],
      );
      expect(picked?['url'], 'https://example.com/front.png');
    });

    test('忽略没有 url 的媒体项', () {
      final picked = ScreenscraperService.pickMedia(
        <dynamic>[
          <String, dynamic>{'type': 'box-2D', 'region': 'wor'},
          <String, dynamic>{
            'type': 'box-2D',
            'region': 'eu',
            'url': 'https://example.com/front.png',
          },
        ],
        const <String>['box-2D'],
      );
      expect(picked?['url'], 'https://example.com/front.png');
    });
  });
}
