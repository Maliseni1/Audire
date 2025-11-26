import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';

/// The background audio handler that interfaces with the System UI
class TtsAudioHandler extends BaseAudioHandler {
  
  // 1. Initial Setup
  static Future<TtsAudioHandler> init() async {
    return await AudioService.init(
      builder: () => TtsAudioHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.audire.app.channel.audio',
        androidNotificationChannelName: 'Audire Playback',
        androidNotificationOngoing: true,
        androidShowNotificationBadge: true,
      ),
    );
  }

  // 2. Update the Notification (Title, Play/Pause Icon)
  void setMediaItem(String title, Duration duration) {
    mediaItem.add(MediaItem(
      id: 'audire_tts',
      album: 'Audire Reader',
      title: title,
      artist: 'Reading Now',
      duration: duration,
      artUri: Uri.parse('https://via.placeholder.com/150/512DA8/FFFFFF?text=Audire'), // Placeholder or App Icon
    ));
  }

  void setPlaybackState({required bool isPlaying}) {
    playbackState.add(playbackState.value.copyWith(
      controls: [
        if (isPlaying) MediaControl.pause else MediaControl.play,
        MediaControl.stop,
      ],
      systemActions: const {
        MediaAction.seek,
      },
      playing: isPlaying,
      processingState: AudioProcessingState.ready,
    ));
  }

  // 3. Handle Buttons Pressed from Lock Screen
  // These functions are called by the OS when user taps the notification
  @override
  Future<void> play() async {
    // We will listen to this stream in the UI to trigger actual TTS
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
}