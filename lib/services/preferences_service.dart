import 'package:shared_preferences/shared_preferences.dart';

import '../models/cloud_save.dart';
import '../models/resource_fields.dart';

/// 应用设置持久化。
class PreferencesService {
  static const _libraryPath = 'library_path';
  static const _ssUsername = 'ss_username';
  static const _ssPassword = 'ss_password';
  static const _language = 'preferred_language';
  static const _downloadCover = 'download_cover';
  static const _downloadVideo = 'download_video';
  static const _overwriteDescription = 'overwrite_description';
  static const _scrapeFields = 'scrape_fields';
  static const _detailFields = 'detail_fields';
  static const _autoId = 'auto_id';
  static const _renameRomOnSave = 'rename_rom_on_save';
  static const _renameMediaOnSave = 'rename_media_on_save';
  static const _translateKey = 'translate_key';
  static const _videoAutoPlayDelay = 'video_auto_play_delay';
  static const _libraryViewMode = 'library_view_mode';
  static const _detailViewMode = 'detail_view_mode';
  static const _webdavUrl = 'cloud_webdav_url';
  static const _webdavUser = 'cloud_webdav_user';
  static const _webdavPassword = 'cloud_webdav_password';
  static const _webdavRoot = 'cloud_webdav_root';
  static const _cloudSaveFolders = 'cloud_save_folders';
  static const _cloudSaveAutoSync = 'cloud_save_auto_sync';
  static const _cloudSaveConflictPolicy = 'cloud_save_conflict_policy';
  static const _cloudSaveMaxBackups = 'cloud_save_max_backups';
  static const _cloudSaveSnapshots = 'cloud_save_snapshots';
  static const _emulatorConfigs = 'emulator_configs';

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

  /// 搜刮时需要获取并写入 TOML 的字段集合。
  ///
  /// 未保存过时按默认值（开发商、发行日期、box2D、简介、视频）返回，
  /// 并兼容旧版本单独保存的封面/视频/简介开关。
  static Future<Set<String>> get scrapeFields async {
    final prefs = await _prefs;
    final stored = prefs.getStringList(_scrapeFields);
    if (stored != null) {
      return stored.where(ResourceFields.all.contains).toSet();
    }
    final fields = <String>{
      ...ResourceFields.defaults,
    };
    if (!(prefs.getBool(_downloadCover) ?? true)) {
      fields.remove(ResourceFields.cover);
    }
    if (!(prefs.getBool(_downloadVideo) ?? true)) {
      fields.remove(ResourceFields.video);
    }
    if (!(prefs.getBool(_overwriteDescription) ?? true)) {
      fields.remove(ResourceFields.description);
    }
    return fields;
  }

  static Future<void> setScrapeFields(Set<String> fields) async =>
      (await _prefs).setStringList(_scrapeFields, fields.toList());

  /// 游戏详情页展示的资源字段集合。
  ///
  /// 未保存过时默认展示开发商、发行日期、box2D、简介、视频。
  static Future<Set<String>> get detailFields async {
    final stored = (await _prefs).getStringList(_detailFields);
    if (stored == null) return <String>{...ResourceFields.defaults};
    return stored.where(ResourceFields.all.contains).toSet();
  }

  static Future<void> setDetailFields(Set<String> fields) async =>
      (await _prefs).setStringList(_detailFields, fields.toList());

  static Future<bool> get autoId async => (await _prefs).getBool(_autoId) ?? true;
  static Future<void> setAutoId(bool value) async =>
      (await _prefs).setBool(_autoId, value);

  /// 保存时是否把 ROM 文件重命名为游戏名（保留扩展名）。
  ///
  /// 默认开启：改名后 ROM 与 `media/游戏名/` 目录保持一致，
  /// 避免 TOML 中的 `file`/`cover` 与磁盘实际文件名脱节。
  static Future<bool> get renameRomOnSave async =>
      (await _prefs).getBool(_renameRomOnSave) ?? true;
  static Future<void> setRenameRomOnSave(bool value) async =>
      (await _prefs).setBool(_renameRomOnSave, value);

  /// 保存时是否把 media 媒体目录重命名为游戏名。
  static Future<bool> get renameMediaOnSave async =>
      (await _prefs).getBool(_renameMediaOnSave) ?? true;
  static Future<void> setRenameMediaOnSave(bool value) async =>
      (await _prefs).setBool(_renameMediaOnSave, value);

  /// 视频小窗自动播放延迟（秒）：0 表示不自动播放。
  static Future<int> get videoAutoPlayDelay async =>
      (await _prefs).getInt(_videoAutoPlayDelay) ?? 2;
  static Future<void> setVideoAutoPlayDelay(int seconds) async =>
      (await _prefs).setInt(_videoAutoPlayDelay, seconds);

  /// 游戏库首页的展示模式：`list` / `grid` / `carousel`。
  static Future<String> get libraryViewMode async =>
      (await _prefs).getString(_libraryViewMode) ?? 'grid';
  static Future<void> setLibraryViewMode(String value) async =>
      (await _prefs).setString(_libraryViewMode, value);

  /// 游戏详情页的展示模式：`list` / `carousel`。
  static Future<String> get detailViewMode async =>
      (await _prefs).getString(_detailViewMode) ?? 'list';
  static Future<void> setDetailViewMode(String value) async =>
      (await _prefs).setString(_detailViewMode, value);

  static Future<String?> get translateKey async =>
      (await _prefs).getString(_translateKey);
  static Future<void> setTranslateKey(String value) async =>
      (await _prefs).setString(_translateKey, value);

  // ---------------------------------------------------------------------------
  // 云存档 / WebDAV
  // ---------------------------------------------------------------------------

  static Future<String> get webdavUrl async =>
      (await _prefs).getString(_webdavUrl) ?? '';
  static Future<void> setWebdavUrl(String value) async =>
      (await _prefs).setString(_webdavUrl, value);

  static Future<String> get webdavUsername async =>
      (await _prefs).getString(_webdavUser) ?? '';
  static Future<void> setWebdavUsername(String value) async =>
      (await _prefs).setString(_webdavUser, value);

  static Future<String> get webdavPassword async =>
      (await _prefs).getString(_webdavPassword) ?? '';
  static Future<void> setWebdavPassword(String value) async =>
      (await _prefs).setString(_webdavPassword, value);

  static Future<String> get webdavRoot async =>
      (await _prefs).getString(_webdavRoot) ?? 'RetroEngine';
  static Future<void> setWebdavRoot(String value) async =>
      (await _prefs).setString(_webdavRoot, value);

  static Future<List<CloudSaveFolder>> get cloudSaveFolders async =>
      decodeFolders((await _prefs).getString(_cloudSaveFolders));

  static Future<void> setCloudSaveFolders(List<CloudSaveFolder> folders) async =>
      (await _prefs).setString(_cloudSaveFolders, encodeFolders(folders));

  /// 启动应用时自动执行一次双向同步。
  static Future<bool> get cloudSaveAutoSync async =>
      (await _prefs).getBool(_cloudSaveAutoSync) ?? false;
  static Future<void> setCloudSaveAutoSync(bool value) async =>
      (await _prefs).setBool(_cloudSaveAutoSync, value);

  static Future<String> get cloudSaveConflictPolicy async =>
      (await _prefs).getString(_cloudSaveConflictPolicy) ??
      ConflictPolicy.keepBoth.name;
  static Future<void> setCloudSaveConflictPolicy(String value) async =>
      (await _prefs).setString(_cloudSaveConflictPolicy, value);

  /// 每个目录保留的本地备份份数（按时间倒序）。
  static Future<int> get cloudSaveMaxBackups async =>
      (await _prefs).getInt(_cloudSaveMaxBackups) ?? 5;
  static Future<void> setCloudSaveMaxBackups(int value) async =>
      (await _prefs).setInt(_cloudSaveMaxBackups, value);

  /// 同步时间戳快照（JSON），用于判断哪一端发生了修改。
  static Future<String?> get cloudSaveSnapshots async =>
      (await _prefs).getString(_cloudSaveSnapshots);
  static Future<void> setCloudSaveSnapshots(String value) async =>
      (await _prefs).setString(_cloudSaveSnapshots, value);

  /// 各平台默认模拟器配置（JSON）：平台名 -> 配置对象。
  static Future<String?> get emulatorConfigs async =>
      (await _prefs).getString(_emulatorConfigs);
  static Future<void> setEmulatorConfigs(String value) async =>
      (await _prefs).setString(_emulatorConfigs, value);

  static Future<void> clearAccount() async {
    final prefs = await _prefs;
    await prefs.remove(_ssUsername);
    await prefs.remove(_ssPassword);
  }
}
