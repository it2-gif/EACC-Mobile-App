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
      }
    } catch (_) {
      if (mounted) setState(() => hasError = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (hasError) {
      return const Text(
        'Could not play this voice message.',
        style: TextStyle(color: AppColors.danger),
      );
    }

    final totalMs = duration.inMilliseconds;
    final progress = totalMs == 0
        ? 0.0
        : (position.inMilliseconds / totalMs).clamp(0.0, 1.0);

    return SizedBox(
      width: 280,
      child: Row(
        children: [
          IconButton.filled(
            onPressed: togglePlayback,
            icon: Icon(
              state == PlayerState.playing ? Icons.pause : Icons.play_arrow,
            ),
            tooltip: state == PlayerState.playing ? 'Pause' : 'Play',
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(
                  value: progress,
                  minHeight: 4,
                  borderRadius: BorderRadius.circular(2),
                ),
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
