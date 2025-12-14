import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';

// Global accessor
TtsAudioHandler? globalAudioHandler;

class TtsAudioHandler extends BaseAudioHandler {
  static Future<TtsAudioHandler> init() async {
    final handler = TtsAudioHandler();
    globalAudioHandler = handler;

    return await AudioService.init(
      builder: () => handler,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.audire.app.channel.audio',
        androidNotificationChannelName: 'Audire Playback',
        androidNotificationOngoing: true,
        androidShowNotificationBadge: true,
        androidNotificationIcon: 'mipmap/launcher_icon',
        androidNotificationClickStartsActivity: true,
        // Ensure the notification can be dismissed when stopped
        androidStopForegroundOnPause: true,
      ),
    );
  }

  void setMediaItem(String title, String contentInfo, Duration duration) {
    mediaItem.add(
      MediaItem(
        id: 'audire_tts',
        album: 'Audire Reader',
        title: title,
        artist: contentInfo, // Display "Page 1 of 5" here
        duration: duration,
        artUri: Uri.parse(
          'https://via.placeholder.com/150/512DA8/FFFFFF?text=Audire',
        ),
      ),
    );
  }

  void setPlaybackState({required bool isPlaying}) {
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.rewind,
          if (isPlaying) MediaControl.pause else MediaControl.play,
          MediaControl.stop, // Added Stop button
          MediaControl.fastForward,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 2],
        playing: isPlaying,
        // If stopped, we are 'idle', otherwise 'ready'
        processingState: isPlaying
            ? AudioProcessingState.ready
            : AudioProcessingState.idle,
      ),
    );
  }

  @override
  Future<void> play() async {
    playbackState.add(playbackState.value.copyWith(playing: true));
    // We don't trigger TTS here directly; the UI listens to this state change
  }

  @override
  Future<void> pause() async {
    playbackState.add(playbackState.value.copyWith(playing: false));
  }

  @override
  Future<void> stop() async {
    playbackState.add(
      playbackState.value.copyWith(
        playing: false,
        processingState: AudioProcessingState.idle,
      ),
    );
    // Clear notification
    await super.stop();
  }

  @override
  Future<void> fastForward() async {
    customEvent.add('fastForward');
  }

  @override
  Future<void> rewind() async {
    customEvent.add('rewind');
  }
}
