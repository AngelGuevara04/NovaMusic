import 'playlists_screen.dart';
import 'cloud_backup_screen.dart';
import '../widgets/suggestion_dialog.dart';
import '../widgets/password_dialogs.dart';
import '../widgets/device_output_dialog.dart';
import '../services/updater_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/audio_provider.dart';
import '../providers/downloader_provider.dart';
import '../widgets/song_tile.dart';
import 'player_screen.dart';
import 'hidden_songs_screen.dart';
import 'downloader_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'login_screen.dart';
import 'equalizer_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      UpdaterService.checkAndShowDailyUpdateDialog(context);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showSleepTimerDialog(BuildContext context, AudioProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Row(
            children: [
              Icon(Icons.bedtime_outlined, color: Colors.deepPurpleAccent),
              SizedBox(width: 10),
              Expanded(
                child: Text('Apagado Automático', style: TextStyle(color: Colors.white, fontSize: 18)),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Elige en cuánto tiempo quieres que la música se detenga sola:',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 8),
              ...[15, 30, 45, 60].map((minutes) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('$minutes minutos', style: const TextStyle(color: Colors.white)),
                    leading: const Icon(Icons.timer_outlined, color: Colors.deepPurpleAccent),
                    onTap: () {
                      provider.setSleepTimer(minutes);
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('La música se detendrá en $minutes minutos 🌙')),
                      );
                    },
                  )),
              if (provider.sleepTimerEndTime != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Desactivar temporizador', style: TextStyle(color: Colors.redAccent)),
                  leading: const Icon(Icons.cancel_outlined, color: Colors.redAccent),
                  onTap: () {
                    provider.cancelSleepTimer();
                    Navigator.pop(ctx);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  void _showUserProfileDialog(BuildContext context, AudioProvider provider) {
    final username = provider.currentUsername;
    final isGuest = provider.isGuest;
    final initial = (!isGuest && username != null && username.isNotEmpty)
        ? username[0].toUpperCase()
        : '?';

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: isGuest
                            ? [Colors.grey.shade700, Colors.grey.shade600]
                            : [Colors.deepPurpleAccent, Colors.purpleAccent],
                      ),
                    ),
                    alignment: Alignment.center,
                    child: isGuest
                        ? const Icon(Icons.person, color: Colors.white, size: 28)
                        : Text(
                            initial,
                            style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                          ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isGuest ? 'Modo Invitado' : '@$username',
                          style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isGuest
                              ? 'Inicia sesión para respaldar tu música en la nube'
                              : '${provider.totalSongsCount} canciones en tu lista • ${provider.uniqueCloudLibrarySongs.length} en la nube',
                          style: TextStyle(
                            color: isGuest ? Colors.orangeAccent : Colors.white70,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (!isGuest) ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.cloud_done_outlined, color: Colors.cyanAccent),
                  title: const Text('Ver mi Copia de Seguridad en la Nube', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  subtitle: const Text('Descarga tus canciones o administra tu respaldo', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const CloudBackupScreen()),
                    );
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.lock_reset_rounded, color: Color(0xFFB388FF)),
                  title: const Text('Cambiar mi Contraseña', style: TextStyle(color: Colors.white)),
                  subtitle: const Text('Actualiza tu contraseña o PIN de acceso', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                  onTap: () {
                    Navigator.pop(ctx);
                    if (username != null && username.isNotEmpty) {
                      showChangePasswordDialog(context, username);
                    }
                  },
                ),
              ],
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(isGuest ? Icons.login : Icons.swap_horiz, color: Colors.orangeAccent),
                title: Text(
                  isGuest ? 'Iniciar Sesión / Crear Cuenta' : 'Cambiar de Cuenta',
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  isGuest ? 'Guarda tus canciones para recuperarlas en cualquier celular o PC' : 'Entrar con otro usuario',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                onTap: () async {
                  Navigator.pop(ctx);
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.remove('current_username');
                  if (context.mounted) {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (context) => const LoginScreen()),
                    );
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showSortDialog(BuildContext context, AudioProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.sort, color: Colors.deepPurpleAccent),
            SizedBox(width: 8),
            Text('Ordenar mis canciones', style: TextStyle(color: Colors.white, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.sort_by_alpha, color: provider.currentSort == 'title' ? Colors.deepPurpleAccent : Colors.white70),
              title: Text('Por Nombre (A - Z)', style: TextStyle(color: provider.currentSort == 'title' ? Colors.deepPurpleAccent : Colors.white, fontWeight: provider.currentSort == 'title' ? FontWeight.bold : FontWeight.normal)),
              trailing: provider.currentSort == 'title' ? const Icon(Icons.check, color: Colors.deepPurpleAccent) : null,
              onTap: () {
                provider.sortSongsBy('title');
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: Icon(Icons.person_outline, color: provider.currentSort == 'artist' ? Colors.deepPurpleAccent : Colors.white70),
              title: Text('Por Artista', style: TextStyle(color: provider.currentSort == 'artist' ? Colors.deepPurpleAccent : Colors.white, fontWeight: provider.currentSort == 'artist' ? FontWeight.bold : FontWeight.normal)),
              trailing: provider.currentSort == 'artist' ? const Icon(Icons.check, color: Colors.deepPurpleAccent) : null,
              onTap: () {
                provider.sortSongsBy('artist');
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: Icon(Icons.access_time, color: provider.currentSort == 'date' ? Colors.deepPurpleAccent : Colors.white70),
              title: Text('Más recientes primero', style: TextStyle(color: provider.currentSort == 'date' ? Colors.deepPurpleAccent : Colors.white, fontWeight: provider.currentSort == 'date' ? FontWeight.bold : FontWeight.normal)),
              trailing: provider.currentSort == 'date' ? const Icon(Icons.check, color: Colors.deepPurpleAccent) : null,
              onTap: () {
                provider.sortSongsBy('date');
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaybackModeButton(BuildContext context, AudioProvider audioProvider) {
    final mode = audioProvider.playbackMode;
    IconData icon;
    String label;
    Color bgColor;
    Color fgColor;
    Color borderColor;

    if (mode == 'smart_shuffle') {
      icon = Icons.auto_awesome;
      label = 'Inteligente ✨';
      bgColor = const Color(0xFF2B2312);
      fgColor = Colors.amberAccent;
      borderColor = Colors.amberAccent.withOpacity(0.6);
    } else if (mode == 'shuffle_local') {
      icon = Icons.shuffle_rounded;
      label = 'Aleatorio';
      bgColor = Colors.deepPurpleAccent.withOpacity(0.22);
      fgColor = const Color(0xFFB388FF);
      borderColor = Colors.deepPurpleAccent.withOpacity(0.6);
    } else {
      icon = Icons.repeat_rounded;
      label = 'En orden';
      bgColor = const Color(0xFF242424);
      fgColor = Colors.white70;
      borderColor = Colors.white12;
    }

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () async {
        await audioProvider.cyclePlaybackMode();
        if (!context.mounted) return;
        String msg;
        if (audioProvider.playbackMode == 'smart_shuffle') {
          msg = '✨ Modo Inteligente: Mezcla tu lista con canciones nuevas similares';
        } else if (audioProvider.playbackMode == 'shuffle_local') {
          msg = '🔀 Modo Aleatorio: Reproduciendo solo tu lista al azar';
        } else {
          msg = '▶️ Reproducción en orden normal';
        }
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: fgColor),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(color: fgColor, fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Buscar por canción o artista...',
                  hintStyle: TextStyle(color: Colors.white70),
                  border: InputBorder.none,
                ),
                onChanged: (value) {
                  Provider.of<AudioProvider>(context, listen: false).searchSongs(value);
                },
              )
            : Consumer<AudioProvider>(
                builder: (context, provider, child) {
                  final username = provider.currentUsername;
                  final isGuest = provider.isGuest;
                  final initial = (!isGuest && username != null && username.isNotEmpty)
                      ? username[0].toUpperCase()
                      : '?';

                  return InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => _showUserProfileDialog(context, provider),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: isGuest
                                    ? [Colors.grey.shade700, Colors.grey.shade600]
                                    : [Colors.deepPurpleAccent, Colors.purpleAccent],
                              ),
                            ),
                            alignment: Alignment.center,
                            child: isGuest
                                ? const Icon(Icons.person_outline, color: Colors.white, size: 18)
                                : Text(
                                    initial,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                isGuest ? 'Invitado' : 'Hola, $username',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                isGuest ? 'Toca para iniciar sesión' : 'Cuenta sincronizada ☁️',
                                style: TextStyle(
                                  color: isGuest ? Colors.orangeAccent : const Color(0xFF69F0AE),
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search, color: Colors.white),
            tooltip: _isSearching ? 'Cerrar búsqueda' : 'Buscar en mis canciones',
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) {
                  _searchController.clear();
                  Provider.of<AudioProvider>(context, listen: false).searchSongs('');
                }
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.download_rounded, color: Colors.cyanAccent),
            tooltip: 'Descargar música nueva',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const DownloaderScreen()),
              );
            },
          ),
          Consumer<AudioProvider>(
            builder: (context, provider, child) {
              final hasTimer = provider.sleepTimerEndTime != null;

              return PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: Colors.white),
                tooltip: 'Menú y Configuración',
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                color: const Color(0xFF242424),
                onSelected: (String result) async {
                  if (result == 'sort') {
                    _showSortDialog(context, provider);
                  } else if (result == 'sleep_timer') {
                    _showSleepTimerDialog(context, provider);
                  } else if (result == 'audio_output') {
                    showDeviceOutputSwitcherDialog(context);
                  } else if (result == 'cloud_backup') {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const CloudBackupScreen()),
                    );
                  } else if (result == 'settings') {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const SettingsScreen()),
                    );
                  }
                },
                itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                  const PopupMenuItem<String>(
                    value: 'sort',
                    child: Row(
                      children: [
                        Icon(Icons.sort_rounded, color: Colors.cyanAccent, size: 20),
                        SizedBox(width: 12),
                        Text('Ordenar canciones', style: TextStyle(color: Colors.white, fontSize: 14)),
                      ],
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'sleep_timer',
                    child: Row(
                      children: [
                        Icon(
                          Icons.bedtime_outlined,
                          color: hasTimer ? Colors.amberAccent : Colors.deepPurpleAccent,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            hasTimer ? 'Apagado automático (Activo)' : 'Apagado automático',
                            style: TextStyle(
                              color: hasTimer ? Colors.amberAccent : Colors.white,
                              fontWeight: hasTimer ? FontWeight.bold : FontWeight.normal,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'audio_output',
                    child: Row(
                      children: [
                        Icon(Icons.speaker_group_outlined, color: Colors.greenAccent, size: 20),
                        SizedBox(width: 12),
                        Text('Cambiar dispositivo de audio', style: TextStyle(color: Colors.white, fontSize: 14)),
                      ],
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'cloud_backup',
                    child: Row(
                      children: [
                        Icon(Icons.cloud_done_outlined, color: Color(0xFFB388FF), size: 20),
                        SizedBox(width: 12),
                        Text('Mi música en la Nube', style: TextStyle(color: Colors.white, fontSize: 14)),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem<String>(
                    value: 'settings',
                    child: Row(
                      children: [
                        Icon(Icons.settings_outlined, color: Colors.white, size: 20),
                        SizedBox(width: 12),
                        Text(
                          'Configuración y más opciones',
                          style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
      body: Consumer<AudioProvider>(
        builder: (context, audioProvider, child) {
          if (audioProvider.songs.isEmpty && audioProvider.showOnlyFavorites) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.favorite_border, size: 75, color: Colors.redAccent),
                    const SizedBox(height: 16),
                    const Text(
                      'Sin canciones favoritas',
                      style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Toca el corazón ❤️ en cualquier canción para guardarla aquí.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFFCCCCCC), fontSize: 14),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurpleAccent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                      icon: const Icon(Icons.music_note),
                      label: const Text('Ver todas mis canciones'),
                      onPressed: () => audioProvider.setShowOnlyFavorites(false),
                    ),
                  ],
                ),
              ),
            );
          }

          if (audioProvider.songs.isEmpty) {
            final missingCloud = audioProvider.missingCloudSongs;
            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (!audioProvider.isGuest && missingCloud.isNotEmpty) ...[
                      Consumer<DownloaderProvider>(
                        builder: (context, downloader, _) {
                          return Container(
                            padding: const EdgeInsets.all(18),
                            margin: const EdgeInsets.only(bottom: 24),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.deepPurpleAccent.withOpacity(0.35),
                                  const Color(0xFF1E1E1E),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.deepPurpleAccent.withOpacity(0.5)),
                            ),
                            child: Column(
                              children: [
                                const Icon(Icons.cloud_download_rounded, size: 48, color: Colors.cyanAccent),
                                const SizedBox(height: 10),
                                Text(
                                  '¡Tienes ${missingCloud.length} canciones en tu Nube!',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'Detectamos que iniciaste sesión en un dispositivo nuevo. Puedes descargar toda tu música respaldada con un solo toque.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.white70, fontSize: 13),
                                ),
                                const SizedBox(height: 14),
                                if (downloader.isBatchDownloadingCloud) ...[
                                  Text(
                                    'Descargando (${downloader.batchCompletedCount}/${downloader.batchTotalCount}): ${downloader.batchCurrentSongTitle}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.cyanAccent, fontSize: 12, fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 8),
                                  LinearProgressIndicator(
                                    value: downloader.batchTotalCount > 0
                                        ? downloader.batchCompletedCount / downloader.batchTotalCount
                                        : null,
                                    backgroundColor: Colors.white12,
                                    color: Colors.cyanAccent,
                                  ),
                                ] else
                                  SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.deepPurpleAccent,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                      ),
                                      icon: const Icon(Icons.download_for_offline),
                                      label: Text('Descargar mis ${missingCloud.length} canciones de la nube'),
                                      onPressed: () {
                                        downloader.downloadAllCloudSongs(
                                          missingCloud,
                                          onProgressUpdate: () => audioProvider.fetchSongs(),
                                        );
                                      },
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                    const Icon(Icons.music_off, size: 80, color: Colors.white30),
                    const SizedBox(height: 16),
                    const Text(
                      'Aún no tienes canciones aquí',
                      style: TextStyle(color: Color(0xFFE0E0E0), fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).primaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      ),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const DownloaderScreen()),
                        );
                      },
                      icon: const Icon(Icons.download),
                      label: const Text('Buscar y descargar canciones'),
                    ),
                  ],
                ),
              ),
            );
          }

          return Column(
            children: [
              // Barra simplificada: Filtros a la izquierda + Botón de Modo de Reproducción a la derecha
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
                child: Row(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            FilterChip(
                              selected: !audioProvider.showOnlyFavorites,
                              label: Text('Todas (${audioProvider.totalSongsCount})'),
                              labelStyle: TextStyle(
                                color: !audioProvider.showOnlyFavorites ? Colors.white : Colors.white70,
                                fontWeight: !audioProvider.showOnlyFavorites ? FontWeight.bold : FontWeight.normal,
                                fontSize: 12,
                              ),
                              selectedColor: Colors.deepPurpleAccent,
                              backgroundColor: const Color(0xFF242424),
                              side: BorderSide.none,
                              onSelected: (_) => audioProvider.setShowOnlyFavorites(false),
                            ),
                            const SizedBox(width: 8),
                            FilterChip(
                              selected: audioProvider.showOnlyFavorites,
                              avatar: Icon(
                                Icons.favorite,
                                color: audioProvider.showOnlyFavorites ? Colors.white : Colors.redAccent,
                                size: 15,
                              ),
                              label: Text('Favoritas (${audioProvider.totalFavoritesCount})'),
                              labelStyle: TextStyle(
                                color: audioProvider.showOnlyFavorites ? Colors.white : Colors.white70,
                                fontWeight: audioProvider.showOnlyFavorites ? FontWeight.bold : FontWeight.normal,
                                fontSize: 12,
                              ),
                              selectedColor: Colors.redAccent,
                              backgroundColor: const Color(0xFF242424),
                              side: BorderSide.none,
                              onSelected: (_) => audioProvider.setShowOnlyFavorites(true),
                            ),
                            const SizedBox(width: 8),
                            ActionChip(
                              avatar: const Icon(Icons.queue_music, color: Colors.deepPurpleAccent, size: 16),
                              label: Text('Listas (${audioProvider.playlists.length})'),
                              backgroundColor: const Color(0xFF242424),
                              side: BorderSide.none,
                              labelStyle: const TextStyle(color: Colors.white, fontSize: 12),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (context) => const PlaylistsScreen()),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildPlaybackModeButton(context, audioProvider),
                  ],
                ),
              ),
              if (!audioProvider.isGuest && audioProvider.missingCloudSongs.isNotEmpty)
                Consumer<DownloaderProvider>(
                  builder: (context, downloader, _) {
                    final missing = audioProvider.missingCloudSongs;
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1F1934),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.deepPurpleAccent.withOpacity(0.45)),
                      ),
                      child: downloader.isBatchDownloadingCloud
                          ? Row(
                              children: [
                                const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.cyanAccent),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Descargando nube (${downloader.batchCompletedCount}/${downloader.batchTotalCount}): ${downloader.batchCurrentSongTitle}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.white, fontSize: 12),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => downloader.cancelBatchCloudDownload(),
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.redAccent,
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: const Text('Detener', style: TextStyle(fontSize: 11)),
                                ),
                              ],
                            )
                          : Row(
                              children: [
                                const Icon(Icons.cloud_download_outlined, color: Colors.cyanAccent, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '${missing.length} canciones de tu nube listas para descargar',
                                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.deepPurpleAccent,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  onPressed: () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Descargando ${missing.length} canciones de tu nube...'),
                                        backgroundColor: const Color(0xFF7C4DFF),
                                      ),
                                    );
                                    downloader.downloadAllCloudSongs(
                                      missing,
                                      onProgressUpdate: () => audioProvider.fetchSongs(),
                                    );
                                  },
                                  child: const Text('Descargar todas', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                    );
                  },
                ),
              // Tarjeta de Modo Aleatorio Inteligente (solo cuando está activo)
              if (audioProvider.isSmartShuffle)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.amber.withOpacity(0.16),
                        Colors.deepPurpleAccent.withOpacity(0.20),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.amberAccent.withOpacity(0.45)),
                  ),
                  child: audioProvider.isLoadingDiscovery
                      ? Row(
                          children: [
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amberAccent),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                audioProvider.discoveryStatusText.isNotEmpty
                                    ? audioProvider.discoveryStatusText
                                    : 'Buscando canción nueva similar a tu lista...',
                                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        )
                      : audioProvider.isPlayingDiscoverySong && audioProvider.currentDiscoverySong != null
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.auto_awesome, color: Colors.amberAccent, size: 15),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        '✨ RECOMENDACIÓN INTELIGENTE • ${audioProvider.currentDiscoverySeedInfo}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.amberAccent,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${audioProvider.currentDiscoverySong!.title} — ${audioProvider.currentDiscoverySong!.artist ?? ""}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: audioProvider.isCurrentDiscoverySaved
                                              ? Colors.green.shade700
                                              : Colors.pinkAccent,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(vertical: 6),
                                          minimumSize: Size.zero,
                                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                        ),
                                        icon: Icon(
                                          audioProvider.isCurrentDiscoverySaved ? Icons.check_circle : Icons.favorite,
                                          size: 15,
                                        ),
                                        label: Text(
                                          audioProvider.isCurrentDiscoverySaved
                                              ? 'Guardada en tu lista'
                                              : 'Guardar en mi lista',
                                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                                        ),
                                        onPressed: audioProvider.isCurrentDiscoverySaved
                                            ? null
                                            : () async {
                                                final ok = await audioProvider.likeCurrentDiscoverySong();
                                                if (ok && context.mounted) {
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    const SnackBar(
                                                      backgroundColor: Colors.green,
                                                      content: Text('✅ Canción guardada en tu Lista de Canciones'),
                                                    ),
                                                  );
                                                }
                                              },
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.white,
                                        side: const BorderSide(color: Colors.white38),
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        minimumSize: Size.zero,
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                      icon: const Icon(Icons.skip_next, color: Colors.amberAccent, size: 16),
                                      label: const Text('Otra nueva', style: TextStyle(fontSize: 11.5)),
                                      onPressed: () => audioProvider.playNextDiscoverySong(),
                                    ),
                                    const SizedBox(width: 6),
                                    IconButton(
                                      constraints: const BoxConstraints(),
                                      padding: const EdgeInsets.all(4),
                                      tooltip: 'No me gusta esta sugerencia',
                                      icon: const Icon(Icons.close, color: Colors.redAccent, size: 18),
                                      onPressed: () => audioProvider.dislikeCurrentDiscoverySong(),
                                    ),
                                  ],
                                ),
                              ],
                            )
                          : Row(
                              children: [
                                const Icon(Icons.auto_awesome, color: Colors.amberAccent, size: 16),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text(
                                    'Aleatorio Inteligente: Mezclando tu música con canciones nuevas similares',
                                    style: TextStyle(color: Colors.white70, fontSize: 11.5),
                                  ),
                                ),
                                TextButton(
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.amberAccent,
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  onPressed: () => audioProvider.playNextDiscoverySong(),
                                  child: const Text('Descubrir ahora ✨', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                ),
              Expanded(
                child: RefreshIndicator(
                  color: Theme.of(context).primaryColor,
                  backgroundColor: const Color(0xFF2C2C2C),
                  onRefresh: () async {
                    await audioProvider.fetchSongs();
                  },
                  child: ListView.builder(
                    physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                    padding: const EdgeInsets.only(bottom: 100),
                    itemCount: audioProvider.songs.length,
                    itemBuilder: (context, index) {
                      final song = audioProvider.songs[index];
                      return SongTile(
                        song: song,
                        index: index,
                        onTap: () {
                          if (audioProvider.currentSong?.id == song.id) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => const PlayerScreen()),
                            );
                          } else {
                            audioProvider.playSong(index);
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => const PlayerScreen()),
                            );
                          }
                        },
                      );
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: const MiniPlayer(),
    );
  }
}

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<AudioProvider>(
      builder: (context, audioProvider, child) {
        if (audioProvider.currentSong == null) {
          return const SizedBox.shrink();
        }

        final song = audioProvider.currentSong!;
        final isDiscovery = audioProvider.isPlayingDiscoverySong;

        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const PlayerScreen()),
            );
          },
          child: Container(
            height: 68,
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF262626),
              borderRadius: BorderRadius.circular(34),
              border: isDiscovery
                  ? Border.all(color: Colors.amberAccent.withOpacity(0.5), width: 1)
                  : null,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                const SizedBox(width: 10),
                Hero(
                  tag: 'artwork_${song.id}',
                  child: CircleAvatar(
                    radius: 23,
                    backgroundColor: isDiscovery
                        ? Colors.amberAccent.withOpacity(0.18)
                        : Colors.white10,
                    child: Icon(
                      isDiscovery ? Icons.auto_awesome : Icons.music_note,
                      color: isDiscovery ? Colors.amberAccent : Colors.deepPurpleAccent,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isDiscovery
                            ? '✨ ${song.artist ?? "Recomendación"} • ${audioProvider.currentDiscoverySeedInfo}'
                            : (song.artist ?? 'Artista desconocido'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isDiscovery ? Colors.amberAccent : const Color(0xFFCCCCCC),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isDiscovery && !audioProvider.isCurrentDiscoverySaved)
                  IconButton(
                    tooltip: 'Guardar en mi lista',
                    icon: const Icon(Icons.favorite_border, color: Colors.pinkAccent, size: 24),
                    onPressed: () async {
                      final ok = await audioProvider.likeCurrentDiscoverySong();
                      if (ok && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            backgroundColor: Colors.green,
                            content: Text('✅ Canción guardada en tu Lista de Canciones'),
                          ),
                        );
                      }
                    },
                  ),
                IconButton(
                  icon: Icon(
                    audioProvider.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                    color: Theme.of(context).primaryColor,
                    size: 40,
                  ),
                  onPressed: () => audioProvider.playPause(),
                ),
                IconButton(
                  icon: const Icon(Icons.skip_next, color: Colors.white, size: 28),
                  onPressed: () => audioProvider.nextSong(),
                ),
                const SizedBox(width: 6),
              ],
            ),
          ),
        );
      },
    );
  }
}
