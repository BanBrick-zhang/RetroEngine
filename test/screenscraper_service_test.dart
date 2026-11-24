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

  test('内置开发者凭据与 softname、默认语言为 en', () {
    final service = ScreenscraperService();
    expect(ScreenscraperConfig.devId, '');
    expect(ScreenscraperConfig.devPassword, '');
    expect(service.devIdOverride, '');
    expect(service.devPasswordOverride, '');
    expect(service.softNameOverride, 'RetrEnging');
    expect(service.preferredLanguage, 'en');
  });

  test('未配置账号时匿名访问，不携带 ssid/sspassword', () {
    final service = ScreenscraperService();
    expect(service.username, '');
    expect(service.password, '');
    expect(service.hasUserAccount, false);

    final auth = service.authForTesting;
    expect(auth['devid'], '');
    expect(auth['devpassword'], '');
    expect(auth['softname'], 'RetrEnging');
    expect(auth['output'], 'json');
    expect(auth.containsKey('ssid'), false);
    expect(auth.containsKey('sspassword'), false);
  });

  test('配置账号后携带 ssid/sspassword', () {
    final service = ScreenscraperService(username: 'testuser', password: 'testpass');
    expect(service.hasUserAccount, true);

    final auth = service.authForTesting;
    expect(auth['ssid'], 'testuser');
    expect(auth['sspassword'], 'testpass');
  });

  test('构造参数可覆盖开发者凭据与 softname', () {
    final service = ScreenscraperService(
      devId: '1234',
      devPassword: 'custom-pass',
      softname: 'myapp',
    );
    expect(service.devIdOverride, '1234');
    expect(service.devPasswordOverride, 'custom-pass');
    expect(service.softNameOverride, 'myapp');
  });
}
