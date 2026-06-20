import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../theme/app_theme.dart';

class VideoMessagePlayer extends StatefulWidget {
  final String url;

  const VideoMessagePlayer({super.key, required this.url});

  @override
  State<VideoMessagePlayer> createState() => _VideoMessagePlayerState();
}

class _VideoMessagePlayerState extends State<VideoMessagePlayer> {
  late final VideoPlayerController controller;
  bool hasError = false;

  @override
  void initState() {
    super.initState();
    controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize()
          .then((_) {
            if (mounted) setState(() {});
          })
          .catchError((_) {
            if (mounted) setState(() => hasError = true);
          });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void togglePlayback() {
    if (!controller.value.isInitialized) return;
    setState(() {
      controller.value.isPlaying ? controller.pause() : controller.play();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (hasError) {
      return const SizedBox(
        height: 140,
        child: Center(
          child: Text(
            'Could not load video',
            style: TextStyle(color: AppColors.danger),
          ),
        ),
      );
    }

    if (!controller.value.isInitialized) {
      return const SizedBox(
        height: 190,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    final aspectRatio = controller.value.aspectRatio > 0
        ? controller.value.aspectRatio
        : 16 / 9;

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Stack(
        alignment: Alignment.center,
        children: [
          AspectRatio(aspectRatio: aspectRatio, child: VideoPlayer(controller)),
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: togglePlayback,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.05),
                        Colors.black.withValues(alpha: 0.18),
                      ],
                    ),
                  ),
                  child: Center(
                    child: CircleAvatar(
                      radius: 24,
                      backgroundColor: Colors.black.withValues(alpha: 0.62),
                      child: Icon(
                        controller.value.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 10,
            top: 10,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                child: Text(
                  'Video',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
