import '../widgets/suggestion_dialog.dart';
import '../widgets/password_dialogs.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/audio_provider.dart';
import '../services/updater_service.dart';
import 'cloud_backup_screen.dart';
import 'hidden_songs_screen.dart';
import 'equalizer_screen.dart';
import 'stats_screen.dart';
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
    setState(() {
      _autoDelete = value;
    });
    if (mounted) {
      await Provider.of<AudioProvider>(context, listen: false).setAutoDeleteFromDevice(value);
    }
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
      _downloadProgress = kIsWeb ? -1.0 : 0.0;
      _downloadStatus = kIsWeb
          ? 'Descargando e instalando actualización en tu PC...'
          : 'Iniciando descarga...';
    });

    if (kIsWeb) {
      final ok = await UpdaterService.updatePcApp(_availableRelease!.apkDownloadUrl);
      if (!mounted) return;
      setState(() {
        _isDownloadingUpdate = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'Actualización lista. Reiniciando NovaMusic...'
                : 'No se pudo actualizar la versión de PC automáticamente.',
          ),
        ),
      );
      return;
    }

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
        const SnackBar(content: Text('Instalando actualización automáticamente...')),
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
    final audioProvider = Provider.of<AudioProvider>(context);

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
                              child: Icon(Icons.system_update_alt, color: primaryColor, size: 26),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Actualización Automática',
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                  Text(
                                    'Versión actual: v${UpdaterService.currentVersion}',
                                    style: const TextStyle(color: Color(0xFFE0E0E0), fontSize: 13),
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
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(color: primaryColor),
                                  padding: const EdgeInsets.symmetric(vertical: 11),
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
                                  _isCheckingUpdate ? 'Revisando...' : 'Revisar si hay actualización',
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
                                    padding: const EdgeInsets.symmetric(vertical: 11),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  onPressed: _startDownloadAndInstall,
                                  icon: const Icon(Icons.download),
                                  label: const Text('Instalar ahora'),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                _buildSectionHeader('TU MÚSICA Y ALMACENAMIENTO'),
                Card(
                  color: const Color(0xFF1E1E1E),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.cloud_done_outlined, color: Colors.cyanAccent),
                        title: const Text(
                          'Copia de Seguridad en la Nube',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                        subtitle: const Text(
                          'Descarga tus canciones respaldadas o administra tu nube',
                          style: TextStyle(color: Color(0xFFDDDDDD), fontSize: 13),
                        ),
                        trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const CloudBackupScreen()),
                          );
                        },
                      ),
                      const Divider(color: Colors.white12, height: 1),
                      SwitchListTile(
                        activeColor: primaryColor,
                        title: const Text(
                          'Borrar también del dispositivo al quitar',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                        subtitle: const Text(
                          'Si está activo, al deslizar una canción para quitarla se borra el archivo directamente de la memoria (sin guardarla en ocultas).',
                          style: TextStyle(color: Color(0xFFDDDDDD), fontSize: 12.5, height: 1.3),
                        ),
                        value: _autoDelete,
                        onChanged: _toggleAutoDelete,
                      ),
                      if (!_autoDelete) ...[
                        const Divider(color: Colors.white12, height: 1),
                        ListTile(
                          leading: const Icon(Icons.visibility_off_outlined, color: Colors.amberAccent),
                          title: const Text('Canciones Ocultas', style: TextStyle(color: Colors.white)),
                          subtitle: Text(
                            audioProvider.hiddenSongs.isEmpty
                                ? 'No tienes canciones ocultas actualmente'
                                : 'Buscar y restaurar (${audioProvider.hiddenSongs.length} ocultas)',
                            style: const TextStyle(color: Color(0xFFDDDDDD), fontSize: 13),
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
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                _buildSectionHeader('SONIDO Y COMUNIDAD'),
                Card(
                  color: const Color(0xFF1E1E1E),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.equalizer, color: Colors.deepPurpleAccent),
                        title: const Text('Ecualizador y Refuerzo de Graves', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                        subtitle: const Text(
                          'Personaliza el sonido a tu gusto',
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
                      const Divider(color: Colors.white12, height: 1),
                      SwitchListTile(
                        activeColor: primaryColor,
                        secondary: const Icon(Icons.power_settings_new_rounded, color: Colors.orangeAccent),
                        title: const Text(
                          'Detener música al cerrar la app',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                        subtitle: const Text(
                          'Si está activo, al cerrar la ventana de la app se para la música (al salir sin cerrarla sigue sonando).',
                          style: TextStyle(color: Color(0xFFDDDDDD), fontSize: 12.5, height: 1.3),
                        ),
                        value: audioProvider.stopMusicOnAppClose,
                        onChanged: (val) => audioProvider.setStopMusicOnAppClose(val),
                      ),
                      const Divider(color: Colors.white12, height: 1),
                      ListTile(
                        leading: const Icon(Icons.waves_rounded, color: Colors.tealAccent),
                        title: const Text('Transición suave (Crossfade)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          audioProvider.crossfadeSeconds == 0
                              ? 'Desactivado (cambio normal)'
                              : 'Suavizado de ${audioProvider.crossfadeSeconds} segundos entre canciones',
                          style: const TextStyle(color: Color(0xFFDDDDDD), fontSize: 13),
                        ),
                        trailing: DropdownButton<int>(
                          value: audioProvider.crossfadeSeconds,
                          dropdownColor: const Color(0xFF262626),
                          underline: const SizedBox.shrink(),
                          style: const TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold),
                          items: const [
                            DropdownMenuItem(value: 0, child: Text('Off')),
                            DropdownMenuItem(value: 2, child: Text('2s')),
                            DropdownMenuItem(value: 4, child: Text('4s')),
                            DropdownMenuItem(value: 6, child: Text('6s')),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              audioProvider.setCrossfadeSeconds(val);
                            }
                          },
                        ),
                      ),
                      const Divider(color: Colors.white12, height: 1),
                      ListTile(
                        leading: const Icon(Icons.bar_chart_rounded, color: Colors.cyanAccent),
                        title: const Text('Estadísticas y Lo más escuchado', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          audioProvider.totalPlayCount == 0
                              ? 'Mira tus canciones y artistas favoritos'
                              : '${audioProvider.totalPlayCount} reproducciones registradas',
                          style: const TextStyle(color: Color(0xFFDDDDDD), fontSize: 13),
                        ),
                        trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const StatsScreen()),
                          );
                        },
                      ),
                      const Divider(color: Colors.white12, height: 1),
                      ListTile(
                        leading: const Icon(Icons.lightbulb_outline, color: Colors.amberAccent),
                        title: const Text('Enviar Sugerencia o Reportar Fallo', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                        subtitle: const Text(
                          'Tus sugerencias se revisan y aplican automáticamente',
                          style: TextStyle(color: Color(0xFFDDDDDD), fontSize: 13),
                        ),
                        trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                        onTap: () => showSuggestionDialog(context),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                _buildSectionHeader('CUENTA Y SEGURIDAD'),
                Card(
                  color: const Color(0xFF1E1E1E),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: ListTile(
                    leading: const Icon(Icons.lock_reset_rounded, color: Color(0xFFB388FF)),
                    title: Text(
                      _currentUsername.isNotEmpty
                          ? 'Cambiar Contraseña (@$_currentUsername)'
                          : 'Iniciar Sesión / Crear Cuenta',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      _currentUsername.isNotEmpty
                          ? 'Actualiza tu contraseña o tu PIN de recuperación'
                          : 'Inicia sesión para respaldar tus canciones en la nube',
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
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}
