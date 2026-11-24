import 'package:flutter_test/flutter_test.dart';
import 'package:savedeck_toolkit/services/translation_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('解析成功响应取 words 字段', () {
    expect(
      TranslationService.parseResponse(
          '{"code":200,"words":"how are you","msg":"ok"}'),
      'how are you',
    );
  });

  test('解析失败响应抛出 msg', () {
    expect(
      () => TranslationService.parseResponse('{"code":400,"msg":"通讯秘钥不正确！"}'),
      throwsA(isA<TranslationException>()
          .having((e) => e.message, 'message', contains('秘钥'))),
    );
  });

  test('返回格式异常时抛出异常', () {
    expect(() => TranslationService.parseResponse('not json'),
        throwsA(isA<TranslationException>()));
  });

  test('识别文本是否包含中文', () {
    expect(TranslationService.containsChinese('你好吗'), true);
    expect(TranslationService.containsChinese('Castlevania'), false);
  });

  test('长文本按上限切分且内容不丢失', () {
    final text = List<String>.generate(50, (i) => '这是第$i句话。').join();
    final chunks = TranslationService.splitText(text, 100);

    expect(chunks.length, greaterThan(1));
    expect(chunks.every((chunk) => chunk.length <= 100), true);
    expect(chunks.join(''), text);
  });

  test('短文本不切分', () {
    expect(TranslationService.splitText('hello', 100), <String>['hello']);
  });

  test('未配置 KEY 时提示去设置填写', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await expectLater(
      TranslationService.toChinese('hello'),
      throwsA(isA<TranslationException>()
          .having((e) => e.message, 'message', contains('设置'))),
    );
  });
}
