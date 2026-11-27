import 'resource_fields.dart';

/// 一次搜刮任务中需要获取/写入的字段集合。
///
/// 默认只包含开发商、发行日期、box2D 封面、简介与视频；
/// 其余附加资源（wheel、box-texture 等）只有显式勾选才会搜刮。
class ScrapeOptions {
  final Set<String> fields;

  const ScrapeOptions({this.fields = ResourceFields.defaults});

  /// 仅勾选指定字段（用于手动搜索弹窗）。
  ScrapeOptions.of(Iterable<String> selected)
      : fields = Set<String>.unmodifiable(selected.where(ResourceFields.all.contains));

  bool includes(String field) => fields.contains(field);

  bool get downloadCover => includes(ResourceFields.cover);
  bool get downloadVideo => includes(ResourceFields.video);
  bool get overwriteDescription => includes(ResourceFields.description);
  bool get includeDeveloper => includes(ResourceFields.developer);
  bool get includeReleaseDate => includes(ResourceFields.releaseDate);

  /// 勾选的附加媒体资源标签。
  List<String> get resourceTags =>
      GameResourceTags.tags.where(fields.contains).toList();

  bool get nothingSelected => fields.isEmpty;
}