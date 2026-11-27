import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../services/preferences_service.dart';
import '../theme.dart';

/// 内嵌视频小窗：自动播本地视频，无视频时显示占位。
class VideoPreview extends StatefulWidget {
  final String? path;

  /// 占位提示高度，详情页列表视图与轮播视图使用不同尺寸。
  final double placeholderHeight;

  const VideoPreview({super.key, required this.path, this.placeholderHeight = 120});

  @override
  State<VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<VideoPreview> {
  VideoPlayerController? _controller;
  Timer? _autoPlayTimer;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void didUpdateWidget(covariant VideoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _autoPlayTimer?.cancel();
      _autoPlayTimer = null;
      _controller?.dispose();
      _controller = null;
      _failed = false;
      _initialize();
    }
  }

  Future<void> _initialize() async {
    final path = widget.path;
    if (path == null || path.isEmpty) return;
    final file = File(path);
    if (!file.existsSync()) return;
    final controller = VideoPlayerController.file(file);
    _controller = controller;
    try {
      await controller.initialize();
    } catch (_) {
      controller.dispose();
      if (!mounted) return;
      setState(() {
        _failed = true;
        _controller = null;
      });
      return;
    }
    if (!mounted) {
      controller.dispose();
      return;
    }
    setState(() {});

    final delay = await PreferencesService.videoAutoPlayDelay;
    if (delay <= 0 || !mounted) return;
    _autoPlayTimer = Timer(Duration(seconds: delay), () {
      if (mounted &&
          controller.value.isInitialized &&
          !controller.value.isPlaying) {
        controller.play();
      }
    });
  }

  @override
  void dispose() {
    _autoPlayTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  Widget _placeholder(String text) => Container(
        width: double.infinity,
        height: widget.placeholderHeight,
        decoration: BoxDecoration(
          color: AppTheme.subtleFill,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(Icons.movie_outlined,
                size: 26, color: AppTheme.textSecondary),
            const SizedBox(height: 6),
            Text(text,
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 12)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return _placeholder(
          _failed ? '视频无法播放' : '暂无视频（搜刮后自动显示）');
    }
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        if (!value.isInitialized) return _placeholder('视频加载中…');
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              AspectRatio(
                aspectRatio: value.aspectRatio == 0 ? 16 / 9 : value.aspectRatio,
                child: VideoPlayer(controller),
              ),
              Positioned(
                left: 8,
                bottom: 12,
                child: GestureDetector(
                  onTap: () {
                    if (value.isPlaying) {
                      controller.pause();
                    } else {
                      controller.play();
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.45),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      value.isPlaying ? Icons.pause : Icons.play_arrow,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: VideoProgressIndicator(
                  controller,
                  allowScrubbing: true,
                  colors: const VideoProgressColors(
                    playedColor: AppTheme.accent,
                    bufferedColor: AppTheme.border,
                    backgroundColor: Color(0x33FFFFFF),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}