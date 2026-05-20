// lib/core/services/sound_service.dart
// To'g'ri/noto'g'ri javob uchun ovoz effektlari
// Windows da AudioPlayers ishlaydi (BASS dll bilan)

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

class SoundService {
  SoundService._();
  static final SoundService instance = SoundService._();

  final _player = AudioPlayer();
  bool _enabled = true;

  bool get enabled => _enabled;
  set enabled(bool v) { _enabled = v; }

  /// To'g'ri javob — qisqa, xushchaqchaq
  Future<void> correct() async {
    if (!_enabled) return;
    try {
      await _player.stop();
      // Oddiy beep — asset yo'q bo'lsa, skip qilamiz
      await _player.play(AssetSource('sounds/correct.mp3'),
          volume: 0.6, mode: PlayerMode.lowLatency);
    } catch (e) {
      debugPrint('[Sound] correct: $e');
    }
  }

  /// Noto'g'ri javob — past, qisqa
  Future<void> wrong() async {
    if (!_enabled) return;
    try {
      await _player.stop();
      await _player.play(AssetSource('sounds/wrong.mp3'),
          volume: 0.5, mode: PlayerMode.lowLatency);
    } catch (e) {
      debugPrint('[Sound] wrong: $e');
    }
  }

  /// Barakalla — to'liq natija
  Future<void> celebrate() async {
    if (!_enabled) return;
    try {
      await _player.play(AssetSource('sounds/celebrate.mp3'),
          volume: 0.7, mode: PlayerMode.lowLatency);
    } catch (e) {
      debugPrint('[Sound] celebrate: $e');
    }
  }

  void dispose() => _player.dispose();
}
