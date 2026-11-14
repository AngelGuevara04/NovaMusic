import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/audio_provider.dart';

void showDeviceOutputSwitcherDialog(BuildContext context) {
  final provider = Provider.of<AudioProvider>(context, listen: false);
  provider.refreshConnectedDevices();

  showDialog(
    context: context,
    builder: (ctx) {
      return Consumer<AudioProvider>(
        builder: (context, audioProvider, _) {
          final otherDevices = audioProvider.connectedDevices
              .where((d) => d['id'] != audioProvider.deviceId)
              .toList();

          final activeDev = audioProvider.activeCloudDevice;
          final activeDevId = activeDev?['device_id']?.toString();
          final activeDevName = activeDev?['device_name']?.toString() ?? '';
          final activeSongTitle = activeDev?['song_title']?.toString() ?? '';
          final isRemotePlaying = activeDev != null &&
              activeDev['is_playing'] == true &&
              activeDevId != null &&
              activeDevId != audioProvider.deviceId;

          return AlertDialog(
            backgroundColor: const Color(0xFF222222),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: Row(
              children: [
                const Icon(Icons.speaker_group_rounded, color: Colors.greenAccent),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Conectar y Cambiar Salida',
                    style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  tooltip: 'Actualizar dispositivos',
                  icon: const Icon(Icons.refresh, color: Colors.white70, size: 20),
                  onPressed: () => audioProvider.refreshConnectedDevices(),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isRemotePlaying) ...[
                      Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.deepPurpleAccent.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFB388FF).withOpacity(0.5)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.volume_up_rounded, color: Color(0xFFB388FF), size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Sonando en: $activeDevName',
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                            if (activeSongTitle.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                '🎵 $activeSongTitle',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                            ],
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.greenAccent.shade700,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                ),
                                icon: const Icon(Icons.call_received_rounded, size: 16),
                                label: const Text(
                                  'Traer el audio a este dispositivo',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                                onPressed: () {
                                  if (audioProvider.deviceId != null) {
                                    audioProvider.switchAudioOutput(audioProvider.deviceId!);
                                    Navigator.pop(ctx);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('🔊 Reproduciendo ahora en ${audioProvider.currentDeviceName}'),
                                        backgroundColor: const Color(0xFF7C4DFF),
                                      ),
                                    );
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const Text(
                      'ESTE DISPOSITIVO:',
                      style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF181818),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: audioProvider.isPlaying ? Colors.greenAccent.withOpacity(0.6) : Colors.white24,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            audioProvider.currentDeviceIcon,
                            color: audioProvider.isPlaying ? Colors.greenAccent : Colors.white70,
                            size: 24,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  audioProvider.currentDeviceName,
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                                Text(
                                  audioProvider.isPlaying
                                      ? '🔊 Salida de audio activa aquí'
                                      : 'En espera (conectado)',
                                  style: TextStyle(
                                    color: audioProvider.isPlaying ? Colors.greenAccent : Colors.white54,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (audioProvider.isPlaying)
                            const Icon(Icons.graphic_eq, color: Colors.greenAccent, size: 20)
                          else
                            TextButton(
                              onPressed: () {
                                if (audioProvider.deviceId != null) {
                                  audioProvider.switchAudioOutput(audioProvider.deviceId!);
                                  Navigator.pop(ctx);
                                }
                              },
                              child: const Text('Sonar aquí', style: TextStyle(color: Colors.greenAccent, fontSize: 12)),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'OTROS DISPOSITIVOS CON TU CUENTA:',
                      style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                    ),
                    const SizedBox(height: 6),
                    if (otherDevices.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF181818),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'No se detectaron otros dispositivos abiertos en este momento.\n\nAbre NovaMusic en tu PC o celular con el mismo usuario para intercalar la salida de audio en tiempo real.',
                          style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.4),
                        ),
                      )
                    else
                      ...otherDevices.map((dev) {
                        final devId = dev['id']?.toString() ?? '';
                        final devName = dev['name']?.toString() ?? 'Dispositivo';
                        final platform = dev['platform']?.toString() ?? 'device';
                        final isComputer = platform == 'web' || platform == 'windows' || platform == 'desktop';
                        final isThisDevActive = activeDevId == devId && activeDev?['is_playing'] == true;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF181818),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isThisDevActive ? Colors.greenAccent.withOpacity(0.5) : Colors.white12,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isComputer ? Icons.computer : Icons.smartphone,
                                color: isThisDevActive ? Colors.greenAccent : const Color(0xFFB388FF),
                                size: 22,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      devName,
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                                    ),
                                    Text(
                                      isThisDevActive ? '🔊 Reproduciendo ahora' : '🟢 En línea',
                                      style: TextStyle(
                                        color: isThisDevActive ? Colors.greenAccent : Colors.white54,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              ElevatedButton.icon(
                                onPressed: () {
                                  audioProvider.switchAudioOutput(devId);
                                  Navigator.pop(ctx);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('🔊 Salida de audio enviada a $devName'),
                                      backgroundColor: const Color(0xFF7C4DFF),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.speaker_phone_rounded, size: 15, color: Colors.white),
                                label: const Text('Pasar aquí', style: TextStyle(fontSize: 12, color: Colors.white)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF7C4DFF),
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cerrar', style: TextStyle(color: Color(0xFFB388FF))),
              ),
            ],
          );
        },
      );
    },
  );
}
