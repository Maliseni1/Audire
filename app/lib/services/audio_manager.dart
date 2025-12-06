import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';

// 1. GLOBAL ACCESSOR
TtsAudioHandler? globalAudioHandler;

class TtsAudioHandler extends BaseAudioHandler {
  static Future<TtsAudioHandler> init() async {
    // 2. Initialize and assign to global variable
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
      ),
    );
  }

  void setMediaItem(String title, Duration duration) {
    mediaItem.add(MediaItem(
      id: 'audire_tts',
      album: 'Audire Reader',
      title: title,
      artist: 'Reading Now',
      duration: duration,
      artUri: Uri.parse('https://via.placeholder.com/150/512DA8/FFFFFF?text=Audire'),
    ));
  }

  void setPlaybackState({required bool isPlaying}) {
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.rewind,
        if (isPlaying) MediaControl.pause else MediaControl.play,
        MediaControl.fastForward,
        MediaControl.stop,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 2], 
      playing: isPlaying,
      processingState: AudioProcessingState.ready,
    ));
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
    playbackState.add(playbackState.value.copyWith(playing: false));
    super.stop();
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