import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../providers/audio_provider.dart';
import 'home_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _userController = TextEditingController();
  final TextEditingController _passController = TextEditingController();
  final TextEditingController _confirmPassController = TextEditingController();

  bool _isRegisterMode = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;

  String _hashPassword(String password) {
    return sha256.convert(utf8.encode(password.trim())).toString();
  }

  Future<void> _submit() async {
    final username = _userController.text.trim();
    final password = _passController.text.trim();
    final confirmPass = _confirmPassController.text.trim();

    if (username.isEmpty) {
      _showSnack('Por favor ingresa un nombre de usuario', isError: true);
      return;
    }

    if (username.length < 3) {
      _showSnack('El usuario debe tener al menos 3 caracteres', isError: true);
      return;
    }

    if (password.isEmpty) {
      _showSnack('Por favor ingresa una contraseña', isError: true);
      return;
    }

    if (password.length < 4) {
      _showSnack('La contraseña debe tener al menos 4 caracteres', isError: true);
      return;
    }

    if (_isRegisterMode && password != confirmPass) {
      _showSnack('Las contraseñas no coinciden', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final supabase = Supabase.instance.client;
      final existing = await supabase
          .from('user_preferences')
          .select()
          .eq('username', username)
          .maybeSingle();

      if (_isRegisterMode) {
        // Modo Registro
        if (existing != null) {
          _showSnack('Este usuario ya existe. Cambia al modo Iniciar Sesión.', isError: true);
          setState(() => _isLoading = false);
          return;
        }

        final hashed = _hashPassword(password);
        await supabase.from('user_preferences').insert({
          'username': username,
          'password_hash': hashed,
          'hidden_songs': [],
          'favorite_songs': [],
          'library_songs': [],
          'playlists': [],
          'auto_delete': false,
          'last_active': DateTime.now().toIso8601String(),
        });

        _showSnack('¡Cuenta creada con éxito! Bienvenido, $username');
      } else {
        // Modo Iniciar Sesión
        if (existing == null) {
          _showSnack('El usuario no existe. Activa "Registrarse" para crearlo.', isError: true);
          setState(() => _isLoading = false);
          return;
        }

        final storedHash = existing['password_hash'] as String?;
        final enteredHash = _hashPassword(password);

        if (storedHash != null && storedHash.isNotEmpty) {
          if (storedHash != enteredHash) {
            _showSnack('Contraseña incorrecta. Inténtalo de nuevo.', isError: true);
            setState(() => _isLoading = false);
            return;
          }
        } else {
          // Usuario anterior sin contraseña: asignar la ingresada para proteger su cuenta
          await supabase.from('user_preferences').update({
            'password_hash': enteredHash,
          }).eq('username', username);
        }
      }

      // Guardar sesión local
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('current_username', username);

      if (mounted) {
        final audioProvider = Provider.of<AudioProvider>(context, listen: false);
        await audioProvider.loadPreferencesFromSupabase(username);

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const HomeScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        _showSnack('Error de conexión o autenticación: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent.shade700 : const Color(0xFF7C4DFF),
      ),
    );
  }

  Future<void> _loginAsGuest() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('current_username', '');
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const HomeScreen()),
      );
    }
  }

  @override
  void dispose() {
    _userController.dispose();
    _passController.dispose();
    _confirmPassController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.deepPurpleAccent.withOpacity(0.15),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.deepPurpleAccent.withOpacity(0.3),
                        blurRadius: 30,
                        spreadRadius: 4,
                      )
                    ],
                  ),
                  child: const Icon(Icons.library_music_rounded, size: 70, color: Color(0xFFB388FF)),
                ),
                const SizedBox(height: 20),
                const Text(
                  'NovaMusic',
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                ),
                const SizedBox(height: 6),
                Text(
                  _isRegisterMode
                      ? 'Crea tu cuenta con contraseña para sincronizar tus canciones en todos tus dispositivos'
                      : 'Inicia sesión para sincronizar tu música, listas y cambiar la salida de audio entre dispositivos',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 24),

                // Selector Modo: Iniciar Sesión / Registrarse
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.all(4),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _isRegisterMode = false),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: !_isRegisterMode ? const Color(0xFF7C4DFF) : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              'Iniciar Sesión',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: !_isRegisterMode ? Colors.white : Colors.white60,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _isRegisterMode = true),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: _isRegisterMode ? const Color(0xFF7C4DFF) : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              'Registrarse',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: _isRegisterMode ? Colors.white : Colors.white60,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Campo Usuario
                TextField(
                  controller: _userController,
                  decoration: InputDecoration(
                    labelText: 'Usuario',
                    hintText: 'Ej. Guevara',
                    prefixIcon: const Icon(Icons.person_outline, color: Color(0xFFB388FF)),
                    filled: true,
                    fillColor: const Color(0xFF1E1E1E),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 14),

                // Campo Contraseña
                TextField(
                  controller: _passController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Contraseña',
                    prefixIcon: const Icon(Icons.lock_outline, color: Color(0xFFB388FF)),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, color: Colors.white54),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                    filled: true,
                    fillColor: const Color(0xFF1E1E1E),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                ),

                // Campo Confirmar Contraseña (Solo en registro)
                if (_isRegisterMode) ...[
                  const SizedBox(height: 14),
                  TextField(
                    controller: _confirmPassController,
                    obscureText: _obscureConfirm,
                    decoration: InputDecoration(
                      labelText: 'Confirmar Contraseña',
                      prefixIcon: const Icon(Icons.lock_reset, color: Color(0xFFB388FF)),
                      suffixIcon: IconButton(
                        icon: Icon(_obscureConfirm ? Icons.visibility_off : Icons.visibility, color: Colors.white54),
                        onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                      ),
                      filled: true,
                      fillColor: const Color(0xFF1E1E1E),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                // Botón Acción Principal
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7C4DFF),
                      shape: RoundedRectangleUniform(14),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                          )
                        : Text(
                            _isRegisterMode ? 'Crear Cuenta y Entrar' : 'Entrar',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                  ),
                ),
                const SizedBox(height: 14),

                // Botón Invitado
                TextButton(
                  onPressed: _isLoading ? null : _loginAsGuest,
                  child: const Text('Entrar como Invitado (Sin Nube)', style: TextStyle(color: Colors.white60)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class RoundedRectangleUniform extends RoundedRectangleBorder {
  RoundedRectangleUniform(double radius) : super(borderRadius: BorderRadius.circular(radius));
}
