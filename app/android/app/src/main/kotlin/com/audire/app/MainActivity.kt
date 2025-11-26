package com.audire.app

import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.android.FlutterActivity

// CHANGE: Inherit from AudioServiceActivity instead of FlutterActivity
class MainActivity: AudioServiceActivity() {
}