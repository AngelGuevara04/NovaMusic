import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EqualizerService {
  static const MethodChannel _channel = MethodChannel('com.ajgm1.music/equalizer');

  static int bands = 0;
  static int minLevel = -1500;
  static int maxLevel = 1500;
  static List<int> centerFreqs = [];
  static bool bassBoostSupported = false;
  static List<int> currentBandLevels = [];
  static int currentBassBoost = 0;
  static bool isInitialized = false;

  static Future<void> init(int sessionId) async {
    try {
      final res = await _channel.invokeMethod<Map>('initEqualizer', {'sessionId': sessionId});
      if (res != null) {
        bands = res['bands'] ?? 0;
        minLevel = res['minLevel'] ?? -1500;
        maxLevel = res['maxLevel'] ?? 1500;
        centerFreqs = List<int>.from(res['centerFreqs'] ?? []);
        bassBoostSupported = res['bassBoostSupported'] ?? false;

        final prefs = await SharedPreferences.getInstance();
        currentBassBoost = prefs.getInt('eq_bass_boost') ?? 0;
        await setBassBoost(currentBassBoost);

        currentBandLevels = [];
        for (int i = 0; i < bands; i++) {
          int saved = prefs.getInt('eq_band_$i') ?? 0;
          currentBandLevels.add(saved);
          await setBandLevel(i, saved);
        }
        isInitialized = true;
      }
    } catch (e) {
      print('EqualizerService init error: $e');
    }
  }

  static Future<void> setBandLevel(int band, int level) async {
    try {
      await _channel.invokeMethod('setBandLevel', {'band': band, 'level': level});
      if (band < currentBandLevels.length) {
        currentBandLevels[band] = level;
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('eq_band_$band', level);
    } catch (e) {
      print('EqualizerService setBandLevel error: $e');
    }
  }

  static Future<void> setBassBoost(int strength) async {
    try {
      await _channel.invokeMethod('setBassBoost', {'strength': strength});
      currentBassBoost = strength;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('eq_bass_boost', strength);
    } catch (e) {
      print('EqualizerService setBassBoost error: $e');
    }
  }

  static Future<void> applyPreset(String preset) async {
    if (bands == 0) return;
    List<int> levels = List.filled(bands, 0);
    int bass = 0;

    switch (preset) {
      case 'Bass Boost':
        bass = 700;
        if (bands >= 5) {
          levels[0] = 600;
          levels[1] = 400;
          levels[2] = 0;
          levels[3] = -100;
          levels[4] = -200;
        }
        break;
      case 'Rock':
        bass = 300;
        if (bands >= 5) {
          levels[0] = 500;
          levels[1] = 200;
          levels[2] = -100;
          levels[3] = 300;
          levels[4] = 600;
        }
        break;
      case 'Pop':
        bass = 200;
        if (bands >= 5) {
          levels[0] = -100;
          levels[1] = 200;
          levels[2] = 500;
          levels[3] = 200;
          levels[4] = -100;
        }
        break;
      case 'Voz / Vocal':
        bass = 0;
        if (bands >= 5) {
          levels[0] = -300;
          levels[1] = 0;
          levels[2] = 600;
          levels[3] = 400;
          levels[4] = 100;
        }
        break;
      case 'Plano':
      default:
        bass = 0;
        levels = List.filled(bands, 0);
        break;
    }

    await setBassBoost(bass);
    for (int i = 0; i < bands; i++) {
      await setBandLevel(i, levels[i]);
    }
  }
}
