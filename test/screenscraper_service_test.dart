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

  group('发售日期优先 jp、us', () {
    test('同时存在多区域时优先 jp', () {
      expect(
        ScreenscraperService.pickReleaseDate(<dynamic>[
          <String, dynamic>{'region': 'eu', 'text': '1994-04-02'},
          <String, dynamic>{'region': 'us', 'text': '1994-10-01'},
          <String, dynamic>{'region': 'jp', 'text': '1994-04-02'},
        ]),
        '1994-04-02',
      );
    });

    test('没有 jp 时选 us', () {
      expect(
        ScreenscraperService.pickReleaseDate(<dynamic>[
          <String, dynamic>{'region': 'eu', 'text': '1994-04-02'},
          <String, dynamic>{'region': 'us', 'text': '1994-10-01'},
        ]),
        '1994-10-01',
      );
    });

    test('jp/us 都缺失时回退第一个非空日期', () {
      expect(
        ScreenscraperService.pickReleaseDate(<dynamic>[
          <String, dynamic>{'region': 'eu', 'text': ''},
          <String, dynamic>{'region': 'kr', 'text': '1995-01-01'},
        ]),
        '1995-01-01',
      );
    });
  });

  group('附加媒体类型映射', () {
    test('整体包装兼容 box-2D-texture 写法', () {
      final types = ScreenscraperService.resourceMediaTypes['box-texture']!;
      final picked = ScreenscraperService.pickMedia(
        <dynamic>[
          <String, dynamic>{
            'type': 'box-2D-texture',
            'region': 'wor',
            'url': 'https://example.com/box-texture.png',
          },
        ],
        types,
      );
      expect(picked?['url'], 'https://example.com/box-texture.png');
    });

    test('全家福按 mixrbv -> mixrbv2 -> mixrbv1 优先级选取', () {
      final types = ScreenscraperService.resourceMediaTypes['mixrbv']!;
      final picked = ScreenscraperService.pickMedia(
        <dynamic>[
          <String, dynamic>{
            'type': 'mixrbv1',
            'region': 'wor',
            'url': 'https://example.com/mix1.png',
          },
          <String, dynamic>{
            'type': 'mixrbv2',
            'region': 'wor',
            'url': 'https://example.com/mix2.png',
          },
        ],
        types,
      );
      expect(picked?['url'], 'https://example.com/mix2.png');
    });

    test('每个标签都有对应的 ScreenScraper 媒体类型', () {
      for (final tag in const <String>[
        'wheel',
        'box-texture',
        'box-3D',
        'support-2D',
        'fanart',
        'mixrbv',
      ]) {
        expect(ScreenscraperService.resourceMediaTypes[tag], isNotEmpty);
      }
    });
  });

  group('视频默认选用归一化版本', () {
    test('同时存在 video 与 video-normalized 时选 video-normalized', () {
      final picked = ScreenscraperService.pickMedia(
        <dynamic>[
          <String, dynamic>{
            'type': 'video',
            'region': 'wor',
            'url': 'https://example.com/video.mp4',
          },
          <String, dynamic>{
            'type': 'video-normalized',
            'region': 'wor',
            'url': 'https://example.com/video-normalized.mp4',
          },
        ],
        ScreenscraperService.preferredVideoTypes,
      );
      expect(picked?['url'], 'https://example.com/video-normalized.mp4');
    });

    test('没有归一化视频时回退到 video', () {
      final picked = ScreenscraperService.pickMedia(
        <dynamic>[
          <String, dynamic>{
            'type': 'video',
            'region': 'wor',
            'url': 'https://example.com/video.mp4',
          },
        ],
        ScreenscraperService.preferredVideoTypes,
      );
      expect(picked?['url'], 'https://example.com/video.mp4');
    });

    test('类型大小写/下划线写法归一化后仍优先命中', () {
      final picked = ScreenscraperService.pickMedia(
        <dynamic>[
          <String, dynamic>{
            'type': 'video',
            'region': 'wor',
            'url': 'https://example.com/video.mp4',
          },
          <String, dynamic>{
            'type': 'VIDEO_NORMALIZED',
            'region': 'wor',
            'url': 'https://example.com/video-normalized.mp4',
          },
        ],
        ScreenscraperService.preferredVideoTypes,
      );
      expect(picked?['url'], 'https://example.com/video-normalized.mp4');
    });
  });
}
