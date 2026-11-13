import '../widgets/suggestion_dialog.dart';
import '../widgets/password_dialogs.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/updater_service.dart';
import 'hidden_songs_screen.dart';
import 'equalizer_screen.dart';
import 'login_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _autoDelete = false;
  bool _isLoading = true;
  String _currentUsername = '';

  // Updater state
  bool _isCheckingUpdate = false;
  bool _isDownloadingUpdate = false;
  double _downloadProgress = 0.0;
  String _downloadStatus = '';
  ReleaseInfo? _availableRelease;
  String? _updateMessage;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _autoDelete = prefs.getBool('auto_delete_from_device') ?? false;
      _currentUsername = prefs.getString('current_username') ?? '';
      _isLoading = false;
    });
  }

  Future<void> _toggleAutoDelete(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_delete_from_device', value);
    setState(() {
      _autoDelete = value;
    });
  }

  Future<void> _checkForUpdate() async {
    setState(() {
      _isCheckingUpdate = true;
      _updateMessage = null;
      _availableRelease = null;
    });

    try {
      final release = await UpdaterService.checkForUpdate();
      if (!mounted) return;

      setState(() {
        _isCheckingUpdate = false;
        if (release != null) {
          _availableRelease = release;
          _updateMessage = '¡Nueva versión disponible: ${release.tagName}!';
        } else {
          _updateMessage = 'Tienes instalada la versión más reciente (v${UpdaterService.currentVersion}).';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isCheckingUpdate = false;
        _updateMessage = 'Error al comprobar actualizaciones: $e';
      });
    }
  }

  Future<void> _startDownloadAndInstall() async {
    if (_availableRelease == null) return;

    setState(() {
      _isDownloadingUpdate = true;
      _downloadProgress = 0.0;
      _downloadStatus = 'Iniciando descarga...';
    });

    final apkFile = await UpdaterService.downloadApk(
      _availableRelease!.apkDownloadUrl,
      onProgress: (progress, status) {
        if (mounted) {
          setState(() {
            _downloadProgress = progress;
            _downloadStatus = status;
          });
        }
      },
    );

    if (!mounted) return;

    setState(() {
      _isDownloadingUpdate = false;
    });

    if (apkFile != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Instalando actualización...')),
      );
      final success = await UpdaterService.installApk(apkFile);
      if (!success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo iniciar el instalador.')),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error al descargar la actualización.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Configuración',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: [
                _buildSectionHeader('GESTIÓN DE CANCIONES'),
                Card(
                  color: const Color(0xFF1E1E1E),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    children: [
                      SwitchListTile(
                        activeColor: primaryColor,
                        title: const Text(
                          'Borrado directo de memoria',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                        subtitle: const Text(
                          'Al deslizar una canción, borrar el archivo directamente del almacenamiento del celular sin preguntar.',
                          style: TextStyle(color: Color(0xFFDDDDDD), fontSize: 13, height: 1.3),
                        ),
                        value: _autoDelete,
                        onChanged: _toggleAutoDelete,
                      ),
                      const Divider(color: Colors.white12, height: 1),
                      ListTile(
                        leading: const Icon(Icons.visibility_off_outlined, color: Colors.redAccent),
                        title: const Text('Canciones Ocultas', style: TextStyle(color: Colors.white)),
                        subtitle: const Text(
                          'Revisa y restaura canciones quitadas de la lista',
                          style: TextStyle(color: Color(0xFFDDDDDD), fontSize: 13),
                        ),
                        trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const HiddenSongsScreen()),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _buildSectionHeader('AUDIO Y EFECTOS'),
                Card(
                  color: const Color(0xFF1E1E1E),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: ListTile(
                    leading: const Icon(Icons.equalizer, color: Colors.deepPurpleAccent),
                    title: const Text('Ecualizador y Audio', style: TextStyle(color: Colors.white)),
                    subtitle: const Text(
                      'Ajustes de frecuencias y refuerzo de graves',
                      style: TextStyle(color: Color(0xFFDDDDDD), fontSize: 13),
                    ),
                    trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const EqualizerScreen()),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 24),
                _buildSectionHeader('COMUNIDAD Y SUGERENCIAS'),
                Card(
                  color: const Color(0xFF1E1E1E),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: ListTile(
                    leading: const Icon(Icons.lightbulb_outline, color: Colors.amberAccent),
                    title: const Text('Buzón de sugerencias y reportes', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    subtitle: const Text(
                      'Envía tus ideas o reporta fallos para las próximas versiones',
                      style: TextStyle(color: Color(0xFFDDDDDD), fontSize: 13),
                    ),
                    trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                    onTap: () => showSuggestionDialog(context),
                  ),
                ),
                const SizedBox(height: 24),
                _buildSectionHeader('SEGURIDAD Y CUENTA'),
                Card(
                  color: const Color(0xFF1E1E1E),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: ListTile(
                    leading: const Icon(Icons.lock_reset_rounded, color: Color(0xFFB388FF)),
                    title: Text(
                      _currentUsername.isNotEmpty
                          ? 'Actualizar Contraseña (@$_currentUsername)'
                          : 'Iniciar Sesión / Crear Cuenta',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      _currentUsername.isNotEmpty
                          ? 'Cambia tu contraseña actual o actualiza tu PIN de recuperación'
                          : 'Actualmente estás en modo invitado. Inicia sesión para proteger tu cuenta.',
                      style: const TextStyle(color: Color(0xFFDDDDDD), fontSize: 13),
                    ),
                    trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                    onTap: () {
                      if (_currentUsername.isNotEmpty) {
                        showChangePasswordDialog(context, _currentUsername);
                      } else {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (context) => const LoginScreen()),
                        );
                      }
                    },
                  ),
                ),
                const SizedBox(height: 24),
                _buildSectionHeader('ACTUALIZACIONES DE LA APLICACIÓN'),
                Card(
                  color: const Color(0xFF1E1E1E),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: primaryColor.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(Icons.system_update_alt, color: primaryColor, size: 28),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'NovaMusic OTA',
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                  Text(
                                    'Versión instalada: v${UpdaterService.currentVersion}',
                                    style: const TextStyle(color: Color(0xFFE0E0E0), fontSize: 13, fontWeight: FontWeight.w500),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (_updateMessage != null) ...[
                          const SizedBox(height: 14),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: _availableRelease != null
                                  ? Colors.green.withOpacity(0.15)
                                  : Colors.white.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: _availableRelease != null ? Colors.greenAccent : Colors.white24,
                              ),
                            ),
                            child: Text(
                              _updateMessage!,
                              style: TextStyle(
                                color: _availableRelease != null ? Colors.greenAccent : Colors.white,
                                fontWeight: FontWeight.w500,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                        if (_isDownloadingUpdate) ...[
                          const SizedBox(height: 16),
                          LinearProgressIndicator(
                            value: _downloadProgress >= 0 ? _downloadProgress : null,
                            backgroundColor: Colors.white10,
                            valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _downloadStatus,
                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ],
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(color: primaryColor),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                onPressed: _isCheckingUpdate || _isDownloadingUpdate ? null : _checkForUpdate,
                                icon: _isCheckingUpdate
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                      )
                                    : const Icon(Icons.refresh, color: Colors.white),
                                label: Text(
                                  _isCheckingUpdate ? 'Buscando...' : 'Buscar actualización',
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                            ),
                            if (_availableRelease != null && !_isDownloadingUpdate) ...[
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: primaryColor,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  onPressed: _startDownloadAndInstall,
                                  icon: const Icon(Icons.download),
                                  label: const Text('Actualizar'),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: Color(0xFFCE93D8),
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
