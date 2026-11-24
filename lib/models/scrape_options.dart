/// 一次搜刮任务中需要获取的字段，用于手动/批量搜刮时按项选择。
class ScrapeOptions {
  final bool downloadCover;
  final bool downloadVideo;
  final bool overwriteDescription;

  const ScrapeOptions({
    this.downloadCover = true,
    this.downloadVideo = true,
    this.overwriteDescription = true,
  });

  bool get nothingSelected =>
      !downloadCover && !downloadVideo && !overwriteDescription;
}
