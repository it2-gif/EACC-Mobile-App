import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class VoiceMessagePlayer extends StatefulWidget {
  final String url;
  final int? durationMs;

  const VoiceMessagePlayer({super.key, required this.url, this.durationMs});

  @override
  State<VoiceMessagePlayer> createState() => _VoiceMessagePlayerState();
}

class _VoiceMessagePlayerState extends State<VoiceMessagePlayer> {
  late final AudioPlayer player;
  final subscriptions = <StreamSubscription<dynamic>>[];
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  PlayerState state = PlayerState.stopped;
  bool hasError = false;
  double playbackRate = 1.0;

  @override
  void initState() {
    super.initState();
    duration = Duration(milliseconds: widget.durationMs ?? 0);
    player = AudioPlayer();
    subscriptions.add(
      player.onDurationChanged.listen((value) {
        if (mounted) setState(() => duration = value);
      }),
    );
    subscriptions.add(
      player.onPositionChanged.listen((value) {
        if (mounted) setState(() => position = value);
      }),
    );
    subscriptions.add(
      player.onPlayerStateChanged.listen((value) {
        if (mounted) setState(() => state = value);
      }),
    );
    subscriptions.add(
      player.onPlayerComplete.listen((_) {
        if (mounted) setState(() => position = Duration.zero);
      }),
    );
  }

  @override
  void dispose() {
    for (final subscription in subscriptions) {
      subscription.cancel();
    }
    player.dispose();
    super.dispose();
  }

  Future<void> togglePlayback() async {
    try {
      if (state == PlayerState.playing) {
        await player.pause();
      } else if (state == PlayerState.paused) {
        await player.resume();
      } else {
        await player.play(UrlSource(widget.url));
        await player.setPlaybackRate(playbackRate);
      }
    } catch (_) {
      if (mounted) setState(() => hasError = true);
    }
  }

  Future<void> cyclePlaybackRate() async {
    final nextRate = switch (playbackRate) {
      1.0 => 1.5,
      1.5 => 2.0,
      _ => 1.0,
    };

    try {
      await player.setPlaybackRate(nextRate);
      if (mounted) setState(() => playbackRate = nextRate);
    } catch (_) {
      if (mounted) setState(() => hasError = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (hasError) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 2),
        child: Text(
          'Could not play this voice message.',
          style: TextStyle(color: AppColors.danger),
        ),
      );
    }

    final totalMs = duration.inMilliseconds;
    final progress = totalMs == 0
        ? 0.0
        : (position.inMilliseconds / totalMs).clamp(0.0, 1.0);

    return SizedBox(
      width: double.infinity,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          IconButton.filledTonal(
            onPressed: togglePlayback,
            style: IconButton.styleFrom(foregroundColor: AppColors.primary),
            icon: Icon(
              state == PlayerState.playing
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
            ),
            tooltip: state == PlayerState.playing ? 'Pause' : 'Play',
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _VoiceProgressWave(progress: progress),
                const SizedBox(height: 6),
                Text(
                  '${_formatDuration(position)} / ${_formatDuration(duration)}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: cyclePlaybackRate,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              foregroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            child: Text(
              '${playbackRate.toStringAsFixed(playbackRate == 1.0 ? 0 : 1)}x',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration value) {
    final minutes = value.inMinutes;
    final seconds = value.inSeconds.remainder(60);
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

class _VoiceProgressWave extends StatelessWidget {
  final double progress;

  const _VoiceProgressWave({required this.progress});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const barCount = 28;
        final activeBars = (barCount * progress).round();

        return Row(
          children: List.generate(barCount, (index) {
            final height = 4.0 + ((index % 5) * 2.4);
            final isActive = index <= activeBars;

            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  height: height,
                  decoration: BoxDecoration(
                    color: isActive
                        ? AppColors.primary
                        : AppColors.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
