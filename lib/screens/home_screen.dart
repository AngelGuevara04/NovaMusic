import 'cloud_backup_screen.dart';
import '../widgets/suggestion_dialog.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../providers/audio_provider.dart';
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
          title: const Text('Temporizador de Apagado', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (provider.sleepTimerEndTime != null)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Temporizador activo',
                    style: TextStyle(color: Colors.deepPurpleAccent),
                  ),
                ),
              ...[15, 30, 45, 60].map((minutes) => ListTile(
                title: Text('$minutes minutos', style: const TextStyle(color: Colors.white)),
                leading: const Icon(Icons.bedtime_outlined, color: Colors.deepPurpleAccent),
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
                  title: const Text('Cancelar temporizador', style: TextStyle(color: Colors.redAccent)),
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
                    width: 58,
                    height: 58,
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
                        ? const Icon(Icons.person, color: Colors.white, size: 30)
                        : Text(
                            initial,
                            style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
                          ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isGuest ? 'Modo Invitado' : '@$username',
                          style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              isGuest ? Icons.cloud_off : Icons.cloud_done,
                              color: isGuest ? Colors.orangeAccent : const Color(0xFF69F0AE),
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              isGuest ? 'Sin respaldo en la nube' : 'Perfil sincronizado en Supabase',
                              style: TextStyle(
                                color: isGuest ? Colors.orangeAccent : const Color(0xFF69F0AE),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      icon: Icons.library_music,
                      color: Colors.deepPurpleAccent,
                      title: 'Total',
                      value: '${provider.totalSongsCount}',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildStatCard(
                      icon: Icons.phone_android,
                      color: Colors.greenAccent,
                      title: 'Locales',
                      value: '${provider.localSongsCount}',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildStatCard(
                      icon: Icons.cloud_outlined,
                      color: Colors.lightBlueAccent,
                      title: 'En Nube',
                      value: '${provider.cloudLibrarySongs.length}',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildStatCard(
                      icon: Icons.favorite,
                      color: Colors.redAccent,
                      title: 'Favoritas',
                      value: '${provider.totalFavoritesCount}',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (!isGuest) ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.cloud_upload_outlined, color: Colors.lightBlueAccent),
                  title: const Text('Subir canciones locales a mi Nube', style: TextStyle(color: Colors.white)),
                  subtitle: const Text('Respalda la música de este celular para escucharla en otros dispositivos', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await provider.syncLocalSongsToCloud();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('☁️ Canciones respaldadas en tu Nube de @$username'),
                          backgroundColor: const Color(0xFF262626),
                        ),
                      );
                    }
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.sync, color: Colors.deepPurpleAccent),
                  title: const Text('Sincronizar ahora con la Nube', style: TextStyle(color: Colors.white)),
                  subtitle: const Text('Respalda tus favoritas y configuración', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await provider.syncPreferencesToCloud();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('☁️ Perfil y favoritas sincronizados con éxito en la nube'),
                          backgroundColor: Color(0xFF262626),
                        ),
                      );
                    }
                  },
                ),
              ],
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(isGuest ? Icons.login : Icons.swap_horiz, color: Colors.orangeAccent),
                title: Text(isGuest ? 'Iniciar Sesión / Crear Usuario' : 'Cambiar de Usuario', style: const TextStyle(color: Colors.white)),
                subtitle: Text(
                  isGuest ? 'Guarda tus canciones y favoritas en tu propia cuenta' : 'Accede con otro perfil musical',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
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
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required Color color,
    required String title,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF282828),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: const TextStyle(color: Color(0xFFCCCCCC), fontSize: 11),
          ),
        ],
      ),
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
            Text('Ordenar canciones', style: TextStyle(color: Colors.white, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.sort_by_alpha, color: provider.currentSort == 'title' ? Colors.deepPurpleAccent : Colors.white70),
              title: Text('Por Título', style: TextStyle(color: provider.currentSort == 'title' ? Colors.deepPurpleAccent : Colors.white, fontWeight: provider.currentSort == 'title' ? FontWeight.bold : FontWeight.normal)),
              trailing: provider.currentSort == 'title' ? const Icon(Icons.check, color: Colors.deepPurpleAccent) : null,
              onTap: () {
                provider.sortSongsBy('title');
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: Icon(Icons.person, color: provider.currentSort == 'artist' ? Colors.deepPurpleAccent : Colors.white70),
              title: Text('Por Artista', style: TextStyle(color: provider.currentSort == 'artist' ? Colors.deepPurpleAccent : Colors.white, fontWeight: provider.currentSort == 'artist' ? FontWeight.bold : FontWeight.normal)),
              trailing: provider.currentSort == 'artist' ? const Icon(Icons.check, color: Colors.deepPurpleAccent) : null,
              onTap: () {
                provider.sortSongsBy('artist');
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: Icon(Icons.access_time, color: provider.currentSort == 'date' ? Colors.deepPurpleAccent : Colors.white70),
              title: Text('Por Fecha (Recientes)', style: TextStyle(color: provider.currentSort == 'date' ? Colors.deepPurpleAccent : Colors.white, fontWeight: provider.currentSort == 'date' ? FontWeight.bold : FontWeight.normal)),
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
                  hintText: 'Buscar canción...',
                  hintStyle: const TextStyle(color: Colors.white70),
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
                              boxShadow: [
                                BoxShadow(
                                  color: (isGuest ? Colors.grey : Colors.deepPurpleAccent).withValues(alpha: 0.4),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
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
                              Row(
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: isGuest ? Colors.orangeAccent : Colors.greenAccent,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    isGuest ? 'Sin cuenta' : 'Sincronizado ☁️',
                                    style: TextStyle(
                                      color: isGuest ? Colors.orangeAccent : const Color(0xFF69F0AE),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
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
            tooltip: _isSearching ? 'Cerrar búsqueda' : 'Buscar canción',
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
            icon: const Icon(Icons.cloud_download_outlined, color: Colors.white),
            tooltip: 'Descargar música',
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
                tooltip: 'Opciones de la aplicación',
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                color: const Color(0xFF262626),
                onSelected: (String result) async {
                  if (result == 'sleep_timer') {
                    _showSleepTimerDialog(context, provider);
                  } else if (result == 'equalizer') {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const EqualizerScreen()),
                    );
                  } else if (result == 'sort') {
                    _showSortDialog(context, provider);
                  } else if (result == 'suggestions') {
                    showSuggestionDialog(context);
                  } else if (result == 'cloud_backup') {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const CloudBackupScreen()),
                    );
                  } else if (result == 'profile') {
                    _showUserProfileDialog(context, provider);
                  } else if (result == 'restore_hidden') {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const HiddenSongsScreen()),
                    );
                  } else if (result == 'settings') {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const SettingsScreen()),
                    );
                  }
                },
                itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(
                    value: 'sleep_timer',
                    child: Row(
                      children: [
                        Icon(
                          Icons.bedtime_outlined,
                          color: hasTimer ? Colors.deepPurpleAccent : Colors.white70,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            hasTimer ? 'Temporizador (Activo)' : 'Temporizador de apagado',
                            style: TextStyle(
                              color: hasTimer ? Colors.deepPurpleAccent : Colors.white,
                              fontWeight: hasTimer ? FontWeight.bold : FontWeight.normal,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'equalizer',
                    child: Row(
                      children: [
                        Icon(Icons.equalizer, color: Colors.deepPurpleAccent, size: 20),
                        SizedBox(width: 12),
                        Text('Ecualizador y Audio', style: TextStyle(color: Colors.white, fontSize: 14)),
                      ],
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'sort',
                    child: Row(
                      children: [
                        Icon(Icons.sort, color: Colors.cyanAccent, size: 20),
                        SizedBox(width: 12),
                        Text('Ordenar lista...', style: TextStyle(color: Colors.white, fontSize: 14)),
                      ],
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'restore_hidden',
                    child: Row(
                      children: [
                        Icon(Icons.visibility_off_outlined, color: Colors.amberAccent, size: 20),
                        SizedBox(width: 12),
                        Text('Canciones descartadas', style: TextStyle(color: Colors.white, fontSize: 14)),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem<String>(
                    value: 'suggestions',
                    child: Row(
                      children: [
                        Icon(Icons.lightbulb_outline, color: Colors.amberAccent, size: 20),
                        SizedBox(width: 12),
                        Text('Buzón de sugerencias', style: TextStyle(color: Colors.white, fontSize: 14)),
                      ],
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'cloud_backup',
                    child: Row(
                      children: [
                        Icon(Icons.cloud_done_outlined, color: Colors.cyanAccent, size: 20),
                        SizedBox(width: 12),
                        Text('Respaldo en la Nube', style: TextStyle(color: Colors.white, fontSize: 14)),
                      ],
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'profile',
                    child: Row(
                      children: [
                        Icon(Icons.account_circle_outlined, color: Colors.orangeAccent, size: 20),
                        SizedBox(width: 12),
                        Text('Mi Perfil / Nube', style: TextStyle(color: Colors.white, fontSize: 14)),
                      ],
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'settings',
                    child: Row(
                      children: [
                        Icon(Icons.settings_outlined, color: Colors.white70, size: 20),
                        SizedBox(width: 12),
                        Text('Configuración', style: TextStyle(color: Colors.white, fontSize: 14)),
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
                    Text(
                      'Toca el corazón ❤️ en cualquier canción para guardarla en tu perfil de ${audioProvider.isGuest ? "usuario" : audioProvider.currentUsername}.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFFCCCCCC), fontSize: 14),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurpleAccent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                      icon: const Icon(Icons.music_note),
                      label: const Text('Ver todas las canciones'),
                      onPressed: () => audioProvider.setShowOnlyFavorites(false),
                    ),
                  ],
                ),
              ),
            );
          }

          if (audioProvider.songs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.music_off, size: 80, color: Colors.white30),
                  const SizedBox(height: 16),
                  const Text(
                    '¿No encuentras lo que buscas?',
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
                    label: const Text('Descargar canciones gratis'),
                  ),
                ],
              ),
            );
          }

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
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
                        size: 16,
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
                    const Spacer(),
                    IconButton(
                      icon: Icon(
                        audioProvider.isShuffle ? Icons.shuffle_on_outlined : Icons.shuffle,
                        color: audioProvider.isShuffle ? Theme.of(context).primaryColor : Colors.white70,
                      ),
                      tooltip: 'Modo aleatorio',
                      onPressed: () {
                        audioProvider.toggleShuffle();
                        ScaffoldMessenger.of(context).hideCurrentSnackBar();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              audioProvider.isShuffle ? 'Modo aleatorio activado' : 'Modo aleatorio desactivado',
                            ),
                            duration: const Duration(seconds: 1),
                          ),
                        );
                      },
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
                          // Si ya se está reproduciendo, expandir el reproductor en lugar de reiniciar/pausar
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

        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const PlayerScreen()),
            );
          },
          child: Container(
            height: 70,
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF2C2C2C),
              borderRadius: BorderRadius.circular(35),
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
                const SizedBox(width: 8),
                Hero(
                  tag: 'artwork_${song.id}',
                  child: const CircleAvatar(
                    radius: 25,
                    backgroundColor: Colors.white10,
                    child: Icon(Icons.music_note, color: Colors.deepPurpleAccent),
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
                      Text(
                        song.artist ?? "Artista desconocido",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFCCCCCC),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
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
                  icon: const Icon(Icons.skip_next, color: Colors.white, size: 30),
                  onPressed: () => audioProvider.nextSong(),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        );
      },
    );
  }
}
