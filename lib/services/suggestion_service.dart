import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'updater_service.dart';

class SuggestionService {
  /// Enviar una sugerencia a la base de datos de Supabase
  static Future<bool> sendSuggestion({
    required String type,
    required String message,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString('current_username') ?? 'Melómano Anónimo';
      final platform = Platform.isAndroid ? 'Android' : (Platform.isWindows ? 'Windows' : 'Otro');
      final version = UpdaterService.currentVersion;

      final supabase = Supabase.instance.client;
      await supabase.from('app_suggestions').insert({
        'username': username,
        'type': type,
        'message': message.trim(),
        'app_version': version,
        'device_info': platform,
        'status': 'pending',
      });
      return true;
    } catch (e) {
      print('Error enviando sugerencia a Supabase: $e');
      return false;
    }
  }

  /// Leer sugerencias para que el administrador / asistente las revise
  static Future<List<Map<String, dynamic>>> fetchSuggestions() async {
    try {
      final supabase = Supabase.instance.client;
      final res = await supabase
          .from('app_suggestions')
          .select()
          .order('created_at', ascending: false)
          .limit(100);
      return List<Map<String, dynamic>>.from(res);
    } catch (e) {
      print('Error cargando sugerencias: $e');
      return [];
    }
  }
}
