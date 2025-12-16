import 'package:audio_service/audio_service.dart';

// GLOBAL ACCESSOR
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
        // FIXED: Set to false to avoid conflict with androidStopForegroundOnPause
        androidNotificationOngoing: false,
        androidShowNotificationBadge: true,
        androidNotificationIcon: 'mipmap/launcher_icon',
        androidNotificationClickStartsActivity: true,
        // This ensures the notification stays visible when paused
        androidStopForegroundOnPause: false,
      ),
    );
  }

  void setMediaItem(String title, String contentInfo, Duration duration) {
    mediaItem.add(
      MediaItem(
        id: 'audire_tts',
        album: 'Audire Reader',
        title: title,
        artist: contentInfo,
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
          MediaControl.stop,
          MediaControl.fastForward,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 2],
        playing: isPlaying,
        processingState: isPlaying
            ? AudioProcessingState.ready
            : AudioProcessingState.idle,
      ),
    );
  }

  @override
  Future<void> play() async {
    playbackState.add(playbackState.value.copyWith(playing: true));
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
