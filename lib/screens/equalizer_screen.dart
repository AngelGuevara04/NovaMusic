import 'package:flutter/material.dart';
import '../services/equalizer_service.dart';

class EqualizerScreen extends StatefulWidget {
  const EqualizerScreen({Key? key}) : super(key: key);

  @override
  State<EqualizerScreen> createState() => _EqualizerScreenState();
}

class _EqualizerScreenState extends State<EqualizerScreen> {
  String _selectedPreset = 'Personalizado';
  final List<String> _presets = ['Plano', 'Bass Boost', 'Rock', 'Pop', 'Voz / Vocal'];

  String _formatFreq(int mHz) {
    int hz = mHz ~/ 1000;
    if (hz >= 1000) {
      return '${(hz / 1000).toStringAsFixed(1)} kHz';
    }
    return '$hz Hz';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text('Ecualizador y Audio', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Presets
            const Text(
              'Perfiles Predefinidos',
              style: TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _presets.map((preset) {
                  final isSelected = _selectedPreset == preset;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: ChoiceChip(
                      label: Text(preset),
                      selected: isSelected,
                      selectedColor: Theme.of(context).primaryColor,
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : Colors.white70,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                      backgroundColor: const Color(0xFF2C2C2C),
                      onSelected: (selected) async {
                        if (selected) {
                          setState(() => _selectedPreset = preset);
                          await EqualizerService.applyPreset(preset);
                          setState(() {});
                        }
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 28),

            // Bass Boost
            if (EqualizerService.bassBoostSupported) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.speaker_group, color: Colors.deepPurpleAccent),
                            SizedBox(width: 8),
                            Text(
                              'Amplificador de Graves (Bass Boost)',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        Text(
                          '${(EqualizerService.currentBassBoost / 10).round()}%',
                          style: const TextStyle(color: Colors.deepPurpleAccent, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    Slider(
                      value: EqualizerService.currentBassBoost.toDouble(),
                      min: 0,
                      max: 1000,
                      activeColor: Colors.deepPurpleAccent,
                      inactiveColor: Colors.white24,
                      onChanged: (val) {
                        setState(() {
                          _selectedPreset = 'Personalizado';
                        });
                        EqualizerService.setBassBoost(val.toInt());
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],

            // Equalizer Bands
            const Text(
              'Bandas de Frecuencia',
              style: TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(16),
              ),
              child: EqualizerService.bands == 0
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20.0),
                        child: Text(
                          'Inicia una canción para calibrar el ecualizador',
                          style: TextStyle(color: Colors.white54),
                        ),
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: List.generate(EqualizerService.bands, (index) {
                        int level = index < EqualizerService.currentBandLevels.length
                            ? EqualizerService.currentBandLevels[index]
                            : 0;
                        int freq = index < EqualizerService.centerFreqs.length
                            ? EqualizerService.centerFreqs[index]
                            : 0;

                        return Column(
                          children: [
                            Text(
                              '${(level / 100).toStringAsFixed(0)} dB',
                              style: const TextStyle(color: Colors.white54, fontSize: 11),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              height: 180,
                              child: RotatedBox(
                                quarterTurns: 3,
                                child: Slider(
                                  value: level.clamp(EqualizerService.minLevel, EqualizerService.maxLevel).toDouble(),
                                  min: EqualizerService.minLevel.toDouble(),
                                  max: EqualizerService.maxLevel.toDouble(),
                                  activeColor: Theme.of(context).primaryColor,
                                  inactiveColor: Colors.white24,
                                  onChanged: (val) {
                                    setState(() {
                                      _selectedPreset = 'Personalizado';
                                    });
                                    EqualizerService.setBandLevel(index, val.toInt());
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _formatFreq(freq),
                              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          ],
                        );
                      }),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
