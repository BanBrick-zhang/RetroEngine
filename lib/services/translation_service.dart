import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'preferences_service.dart';

/// 翻译失败时抛出，[message] 可直接展示给用户。
class TranslationException implements Exception {
  final String message;
  const TranslationException(this.message);

  @override
  String toString() => message;
}

/// 接口盒子（apihz.cn）聚合翻译服务。
///
/// 请求：`fanyi.php?id=10021309&key=..&words=..&type=..`
/// - `type=1` 译为中文，`type=2` 译为英文
/// - 成功返回 `{"code":200,"words":"...","msg":"ok"}`
/// - 失败返回 `{"code":400,"msg":"..."}`，无 `words` 字段
///
/// KEY 由用户在设置页填写，开发者 ID 固定为 10021309。
class TranslationService {
  static const String endpoint = 'https://cn.apihz.cn/api/zici/fanyi.php';
  static const String developerId = '10021309';

  /// 目标语种：1=中文，2=英文。
  static const int chinese = 1;
  static const int english = 2;

  /// 单次请求字符上限。接口限制 5000 字节（中文约 1666 字），取 1200 留余量。
  static const int chunkSize = 1200;

  static bool containsChinese(String text) =>
      RegExp(r'[\u4e00-\u9fff]').hasMatch(text);

  /// 译为中文。
  static Future<String> toChinese(String text) =>
      translate(text, target: chinese);

  /// 译为英文。
  static Future<String> toEnglish(String text) =>
      translate(text, target: english);

  /// 自动判断方向：含中文则译英，否则译中（用于游戏名）。
  static Future<String> autoTranslate(String text) =>
      translate(text, target: containsChinese(text) ? english : chinese);

  static Future<String> translate(String text, {required int target}) async {
    final key = (await PreferencesService.translateKey)?.trim() ?? '';
    if (key.isEmpty) {
      throw const TranslationException('请先在「设置 → 翻译」中填写接口 KEY');
    }

    final source = text.trim();
    if (source.isEmpty) return '';

    final chunks = splitText(source, chunkSize);
    final parts = <String>[];
    for (var i = 0; i < chunks.length; i++) {
      parts.add(await _requestChunk(chunks[i], key, target));
      // 免费账号约 10 次/分钟，分段之间稍作间隔。
      if (i < chunks.length - 1) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
    }
    // 中文直接拼接；英文用空格分隔，保持可读性。
    return parts.join(target == chinese ? '' : ' ').trim();
  }

  static Future<String> _requestChunk(
    String text,
    String key,
    int target,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse(endpoint),
            headers: const <String, String>{
              'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8',
            },
            body: <String, String>{
              'id': developerId,
              'key': key,
              'words': text,
              'type': target.toString(),
            },
          )
          .timeout(const Duration(seconds: 30));
      return parseResponse(response.body);
    } on TranslationException {
      rethrow;
    } on TimeoutException {
      throw const TranslationException('翻译请求超时，请稍后重试');
    } catch (e) {
      throw TranslationException('翻译请求失败：$e');
    }
  }

  /// 解析接口返回。成功取 `words`，失败取 `msg`。
  static String parseResponse(String body) {
    dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      throw const TranslationException('翻译接口返回格式异常');
    }
    if (decoded is! Map) {
      throw const TranslationException('翻译接口返回格式异常');
    }

    final code = int.tryParse(decoded['code']?.toString() ?? '');
    if (code != 200) {
      final msg = decoded['msg']?.toString().trim() ?? '';
      throw TranslationException(
        msg.isNotEmpty ? msg : '翻译失败（code=${code ?? '未知'}）',
      );
    }

    final words = decoded['words']?.toString().trim() ?? '';
    if (words.isEmpty) {
      throw const TranslationException('翻译结果为空');
    }
    return words;
  }

  /// 按句末标点把长文本切成不超过 [maxLength] 字符的片段。
  ///
  /// 优先在句号/问号/感叹号/换行处分段；单句过长时按长度硬切，
  /// 保证每次请求不超过接口的字节限制。
  static List<String> splitText(String text, int maxLength) {
    final source = text.trim();
    if (source.isEmpty) return const <String>[];
    if (source.length <= maxLength) return <String>[source];

    final chunks = <String>[];
    final buffer = StringBuffer();

    void flush() {
      final value = buffer.toString().trim();
      buffer.clear();
      if (value.isNotEmpty) chunks.add(value);
    }

    for (var i = 0; i < source.length; i++) {
      final char = source[i];
      buffer.write(char);

      final isSentenceEnd = char == '。' ||
          char == '！' ||
          char == '？' ||
          char == '!' ||
          char == '?' ||
          char == '\n' ||
          (char == '.' &&
              (i + 1 >= source.length || source[i + 1] == ' '));

      if (buffer.length >= maxLength) {
        flush();
      } else if (isSentenceEnd && buffer.length >= maxLength ~/ 2) {
        flush();
      }
    }
    flush();
    return chunks;
  }
}
