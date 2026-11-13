import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PasswordValidator {
  static String hash(String input) {
    return sha256.convert(utf8.encode(input.trim())).toString();
  }

  static bool hasMinLength(String pass) => pass.length >= 6;
  static bool hasLetter(String pass) => RegExp(r'[A-Za-z]').hasMatch(pass);
  static bool hasNumber(String pass) => RegExp(r'[0-9]').hasMatch(pass);
  static bool hasNoSpaces(String pass) => pass.isNotEmpty && !pass.contains(' ');

  static bool isValid(String pass) {
    return hasMinLength(pass) &&
        hasLetter(pass) &&
        hasNumber(pass) &&
        hasNoSpaces(pass);
  }

  static String? getErrorMessage(String pass) {
    if (pass.isEmpty) return 'Por favor ingresa una contraseña';
    if (!hasNoSpaces(pass)) return 'La contraseña no debe contener espacios';
    if (!hasMinLength(pass)) return 'La contraseña debe tener al menos 6 caracteres';
    if (!hasLetter(pass)) return 'La contraseña debe incluir al menos una letra';
    if (!hasNumber(pass)) return 'La contraseña debe incluir al menos un número';
    return null;
  }
}

class PasswordRequirementsChecklist extends StatelessWidget {
  final String password;
  const PasswordRequirementsChecklist({Key? key, required this.password}) : super(key: key);

  Widget _buildItem(String text, bool met) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        children: [
          Icon(
            met ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
            size: 15,
            color: met ? const Color(0xFF69F0AE) : Colors.white38,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: met ? const Color(0xFF69F0AE) : Colors.white60,
                fontSize: 12,
                fontWeight: met ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF181818),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Formato requerido de contraseña:',
            style: TextStyle(color: Color(0xFFB388FF), fontSize: 12, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          _buildItem('Mínimo 6 caracteres', PasswordValidator.hasMinLength(password)),
          _buildItem('Al menos una letra (A-Z / a-z)', PasswordValidator.hasLetter(password)),
          _buildItem('Al menos un número (0-9)', PasswordValidator.hasNumber(password)),
          _buildItem('Sin espacios en blanco', PasswordValidator.hasNoSpaces(password)),
        ],
      ),
    );
  }
}

Future<void> showForgotPasswordDialog(BuildContext context, {String initialUsername = ''}) async {
  final userCtrl = TextEditingController(text: initialUsername);
  final pinOrSongCtrl = TextEditingController();
  final newPassCtrl = TextEditingController();
  final confirmPassCtrl = TextEditingController();
  final newPinCtrl = TextEditingController();

  bool step2VerifiedUser = false;
  bool requiresPin = false;
  bool hasCloudSongs = false;
  List<dynamic> cloudSongs = [];
  String? storedPinHash;

  bool obscureNew = true;
  bool obscureConfirm = true;
  bool isLoading = false;
  String? errorText;

  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (context, setState) {
          Future<void> checkUser() async {
            final username = userCtrl.text.trim();
            if (username.isEmpty) {
              setState(() => errorText = 'Ingresa tu nombre de usuario');
              return;
            }
            setState(() {
              isLoading = true;
              errorText = null;
            });
            try {
              final supabase = Supabase.instance.client;
              final row = await supabase
                  .from('user_preferences')
                  .select('username, recovery_pin_hash, library_songs')
                  .eq('username', username)
                  .maybeSingle();

              if (row == null) {
                setState(() {
                  isLoading = false;
                  errorText = 'No se encontró ningún usuario con ese nombre.';
                });
                return;
              }

              storedPinHash = row['recovery_pin_hash'] as String?;
              cloudSongs = (row['library_songs'] as List<dynamic>?) ?? [];
              requiresPin = storedPinHash != null && storedPinHash!.isNotEmpty;
              hasCloudSongs = cloudSongs.isNotEmpty;

              setState(() {
                step2VerifiedUser = true;
                isLoading = false;
              });
            } catch (e) {
              setState(() {
                isLoading = false;
                errorText = 'Error al conectar con el servidor.';
              });
            }
          }

          Future<void> resetPassword() async {
            final username = userCtrl.text.trim();
            final verificationInput = pinOrSongCtrl.text.trim();
            final newPass = newPassCtrl.text.trim();
            final confirmPass = confirmPassCtrl.text.trim();
            final newPin = newPinCtrl.text.trim();

            if (requiresPin) {
              if (verificationInput.isEmpty) {
                setState(() => errorText = 'Ingresa tu PIN de recuperación de 4 dígitos o el nombre de una canción de tu nube');
                return;
              }
              final pinMatch = PasswordValidator.hash(verificationInput) == storedPinHash;
              final songMatch = hasCloudSongs &&
                  verificationInput.length >= 3 &&
                  cloudSongs.any((s) =>
                      (s['title']?.toString().toLowerCase() ?? '').contains(verificationInput.toLowerCase()));

              if (!pinMatch && !songMatch) {
                setState(() => errorText = 'El PIN de recuperación o canción de respaldo no coincide.');
                return;
              }
            }

            final validationErr = PasswordValidator.getErrorMessage(newPass);
            if (validationErr != null) {
              setState(() => errorText = validationErr);
              return;
            }

            if (newPass != confirmPass) {
              setState(() => errorText = 'Las contraseñas no coinciden');
              return;
            }

            if (newPin.isNotEmpty && !RegExp(r'^\d{4}$').hasMatch(newPin)) {
              setState(() => errorText = 'El PIN de recuperación debe ser de 4 números');
              return;
            }

            setState(() {
              isLoading = true;
              errorText = null;
            });

            try {
              final supabase = Supabase.instance.client;
              final updateData = <String, dynamic>{
                'password_hash': PasswordValidator.hash(newPass),
                'last_active': DateTime.now().toIso8601String(),
              };
              if (newPin.isNotEmpty) {
                updateData['recovery_pin_hash'] = PasswordValidator.hash(newPin);
              }

              await supabase.from('user_preferences').update(updateData).eq('username', username);

              if (ctx.mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('✅ ¡Contraseña restablecida con éxito! Ya puedes iniciar sesión.'),
                    backgroundColor: Color(0xFF7C4DFF),
                  ),
                );
              }
            } catch (e) {
              setState(() {
                isLoading = false;
                errorText = 'Error al restablecer la contraseña: $e';
              });
            }
          }

          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: const Row(
              children: [
                Icon(Icons.lock_reset_rounded, color: Color(0xFFB388FF), size: 26),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Recuperar Contraseña',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!step2VerifiedUser) ...[
                    const Text(
                      'Ingresa tu nombre de usuario para buscar tu cuenta y restablecer tu contraseña:',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: userCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Usuario',
                        hintText: 'Ingresa tu usuario',
                        prefixIcon: const Icon(Icons.person_outline, color: Color(0xFFB388FF)),
                        filled: true,
                        fillColor: const Color(0xFF282828),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                    ),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.deepPurpleAccent.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.verified_user_outlined, color: Color(0xFFB388FF), size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Cuenta: @${userCtrl.text.trim()}',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (requiresPin) ...[
                      TextField(
                        controller: pinOrSongCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'PIN de 4 dígitos o Canción de tu Nube',
                          hintText: 'Ej. 1234 o título de canción',
                          prefixIcon: const Icon(Icons.key_rounded, color: Colors.amberAccent),
                          filled: true,
                          fillColor: const Color(0xFF282828),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: newPassCtrl,
                      obscureText: obscureNew,
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Nueva Contraseña',
                        prefixIcon: const Icon(Icons.lock_outline, color: Color(0xFFB388FF)),
                        suffixIcon: IconButton(
                          icon: Icon(obscureNew ? Icons.visibility_off : Icons.visibility, color: Colors.white54),
                          onPressed: () => setState(() => obscureNew = !obscureNew),
                        ),
                        filled: true,
                        fillColor: const Color(0xFF282828),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 10),
                    PasswordRequirementsChecklist(password: newPassCtrl.text),
                    const SizedBox(height: 12),
                    TextField(
                      controller: confirmPassCtrl,
                      obscureText: obscureConfirm,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Confirmar Nueva Contraseña',
                        prefixIcon: const Icon(Icons.check_circle_outline, color: Color(0xFFB388FF)),
                        suffixIcon: IconButton(
                          icon: Icon(obscureConfirm ? Icons.visibility_off : Icons.visibility, color: Colors.white54),
                          onPressed: () => setState(() => obscureConfirm = !obscureConfirm),
                        ),
                        filled: true,
                        fillColor: const Color(0xFF282828),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                    ),
                    if (!requiresPin) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: newPinCtrl,
                        keyboardType: TextInputType.number,
                        maxLength: 4,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          counterText: '',
                          labelText: 'PIN de Recuperación (4 dígitos - Opcional)',
                          hintText: 'Ej. 4821',
                          prefixIcon: const Icon(Icons.pin_outlined, color: Colors.cyanAccent),
                          filled: true,
                          fillColor: const Color(0xFF282828),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        ),
                      ),
                    ],
                  ],
                  if (errorText != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      errorText!,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isLoading ? null : () => Navigator.pop(ctx),
                child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C4DFF),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: isLoading
                    ? null
                    : () {
                        if (!step2VerifiedUser) {
                          checkUser();
                        } else {
                          resetPassword();
                        }
                      },
                child: isLoading
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(
                        !step2VerifiedUser ? 'Continuar' : 'Guardar Contraseña',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
              ),
            ],
          );
        },
      );
    },
  );
}

Future<void> showChangePasswordDialog(BuildContext context, String username) async {
  final currentPassCtrl = TextEditingController();
  final newPassCtrl = TextEditingController();
  final confirmPassCtrl = TextEditingController();
  final recoveryPinCtrl = TextEditingController();

  bool obscureCurrent = true;
  bool obscureNew = true;
  bool obscureConfirm = true;
  bool isLoading = false;
  String? errorText;

  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (context, setState) {
          Future<void> updatePassword() async {
            final currentPass = currentPassCtrl.text.trim();
            final newPass = newPassCtrl.text.trim();
            final confirmPass = confirmPassCtrl.text.trim();
            final pin = recoveryPinCtrl.text.trim();

            if (currentPass.isEmpty) {
              setState(() => errorText = 'Ingresa tu contraseña actual');
              return;
            }

            final validationErr = PasswordValidator.getErrorMessage(newPass);
            if (validationErr != null) {
              setState(() => errorText = validationErr);
              return;
            }

            if (newPass != confirmPass) {
              setState(() => errorText = 'La nueva contraseña y su confirmación no coinciden');
              return;
            }

            if (currentPass == newPass) {
              setState(() => errorText = 'La nueva contraseña debe ser distinta a la actual');
              return;
            }

            if (pin.isNotEmpty && !RegExp(r'^\d{4}$').hasMatch(pin)) {
              setState(() => errorText = 'El PIN de recuperación debe tener exactamente 4 dígitos numéricos');
              return;
            }

            setState(() {
              isLoading = true;
              errorText = null;
            });

            try {
              final supabase = Supabase.instance.client;
              final existing = await supabase
                  .from('user_preferences')
                  .select('password_hash')
                  .eq('username', username)
                  .maybeSingle();

              if (existing == null) {
                setState(() {
                  isLoading = false;
                  errorText = 'No se encontró tu perfil en la nube.';
                });
                return;
              }

              final storedHash = existing['password_hash'] as String?;
              if (storedHash != null && storedHash.isNotEmpty) {
                if (storedHash != PasswordValidator.hash(currentPass)) {
                  setState(() {
                    isLoading = false;
                    errorText = 'Tu contraseña actual es incorrecta.';
                  });
                  return;
                }
              }

              final updateMap = <String, dynamic>{
                'password_hash': PasswordValidator.hash(newPass),
                'last_active': DateTime.now().toIso8601String(),
              };
              if (pin.isNotEmpty) {
                updateMap['recovery_pin_hash'] = PasswordValidator.hash(pin);
              }

              await supabase.from('user_preferences').update(updateMap).eq('username', username);

              if (ctx.mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('🔒 ¡Contraseña actualizada con éxito!'),
                    backgroundColor: Color(0xFF7C4DFF),
                  ),
                );
              }
            } catch (e) {
              setState(() {
                isLoading = false;
                errorText = 'Error al actualizar contraseña: $e';
              });
            }
          }

          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: const Row(
              children: [
                Icon(Icons.security_rounded, color: Color(0xFFB388FF), size: 24),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Actualizar Contraseña',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: currentPassCtrl,
                    obscureText: obscureCurrent,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Contraseña Actual',
                      prefixIcon: const Icon(Icons.lock_clock_outlined, color: Colors.white70),
                      suffixIcon: IconButton(
                        icon: Icon(obscureCurrent ? Icons.visibility_off : Icons.visibility, color: Colors.white54),
                        onPressed: () => setState(() => obscureCurrent = !obscureCurrent),
                      ),
                      filled: true,
                      fillColor: const Color(0xFF282828),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: newPassCtrl,
                    obscureText: obscureNew,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Nueva Contraseña',
                      prefixIcon: const Icon(Icons.lock_outline, color: Color(0xFFB388FF)),
                      suffixIcon: IconButton(
                        icon: Icon(obscureNew ? Icons.visibility_off : Icons.visibility, color: Colors.white54),
                        onPressed: () => setState(() => obscureNew = !obscureNew),
                      ),
                      filled: true,
                      fillColor: const Color(0xFF282828),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 10),
                  PasswordRequirementsChecklist(password: newPassCtrl.text),
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirmPassCtrl,
                    obscureText: obscureConfirm,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Confirmar Nueva Contraseña',
                      prefixIcon: const Icon(Icons.check_circle_outline, color: Color(0xFFB388FF)),
                      suffixIcon: IconButton(
                        icon: Icon(obscureConfirm ? Icons.visibility_off : Icons.visibility, color: Colors.white54),
                        onPressed: () => setState(() => obscureConfirm = !obscureConfirm),
                      ),
                      filled: true,
                      fillColor: const Color(0xFF282828),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: recoveryPinCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      counterText: '',
                      labelText: 'PIN de Recuperación de 4 dígitos (Opcional)',
                      hintText: 'Para recuperar tu cuenta si olvidas la clave',
                      prefixIcon: const Icon(Icons.pin_outlined, color: Colors.cyanAccent),
                      filled: true,
                      fillColor: const Color(0xFF282828),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      errorText!,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isLoading ? null : () => Navigator.pop(ctx),
                child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C4DFF),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: isLoading ? null : updatePassword,
                child: isLoading
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Actualizar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      );
    },
  );
}
