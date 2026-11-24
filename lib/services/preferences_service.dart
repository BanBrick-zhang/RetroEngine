import 'package:shared_preferences/shared_preferences.dart';

/// 应用设置持久化。
class PreferencesService {
  static const _libraryPath = 'library_path';
  static const _ssUsername = 'ss_username';
  static const _ssPassword = 'ss_password';
  static const _ssDevId = 'ss_devid';
  static const _ssDevPassword = 'ss_devpassword';
  static const _language = 'preferred_language';
  static const _downloadCover = 'download_cover';
  static const _downloadVideo = 'download_video';
  static const _overwriteDescription = 'overwrite_description';
  static const _autoId = 'auto_id';

  static Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  static Future<String?> get libraryPath async => (await _prefs).getString(_libraryPath);
  static Future<void> setLibraryPath(String path) async =>
      (await _prefs).setString(_libraryPath, path);

  static Future<String?> get ssUsername async => (await _prefs).getString(_ssUsername);
  static Future<void> setSsUsername(String value) async =>
      (await _prefs).setString(_ssUsername, value);

  static Future<String?> get ssPassword async => (await _prefs).getString(_ssPassword);
  static Future<void> setSsPassword(String value) async =>
      (await _prefs).setString(_ssPassword, value);

  static Future<String?> get ssDevId async => (await _prefs).getString(_ssDevId);
  static Future<void> setSsDevId(String value) async =>
      (await _prefs).setString(_ssDevId, value);

  static Future<String?> get ssDevPassword async => (await _prefs).getString(_ssDevPassword);
  static Future<void> setSsDevPassword(String value) async =>
      (await _prefs).setString(_ssDevPassword, value);

  static Future<String> get language async =>
      (await _prefs).getString(_language) ?? 'en';
  static Future<void> setLanguage(String value) async =>
      (await _prefs).setString(_language, value);

  static Future<bool> get downloadCover async =>
      (await _prefs).getBool(_downloadCover) ?? true;
  static Future<void> setDownloadCover(bool value) async =>
      (await _prefs).setBool(_downloadCover, value);

  static Future<bool> get downloadVideo async =>
      (await _prefs).getBool(_downloadVideo) ?? true;
  static Future<void> setDownloadVideo(bool value) async =>
      (await _prefs).setBool(_downloadVideo, value);

  static Future<bool> get overwriteDescription async =>
      (await _prefs).getBool(_overwriteDescription) ?? true;
  static Future<void> setOverwriteDescription(bool value) async =>
      (await _prefs).setBool(_overwriteDescription, value);

  static Future<bool> get autoId async => (await _prefs).getBool(_autoId) ?? true;
  static Future<void> setAutoId(bool value) async =>
      (await _prefs).setBool(_autoId, value);

  static Future<void> clearAccount() async {
    final prefs = await _prefs;
    await prefs.remove(_ssUsername);
    await prefs.remove(_ssPassword);
  }
}
