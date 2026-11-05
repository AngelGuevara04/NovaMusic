import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/suggestion_service.dart';
import '../services/updater_service.dart';

void showSuggestionDialog(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF1E1E1E),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => const _SuggestionModalContent(),
  );
}

class _SuggestionModalContent extends StatefulWidget {
  const _SuggestionModalContent({Key? key}) : super(key: key);

  @override
  State<_SuggestionModalContent> createState() => _SuggestionModalContentState();
}

class _SuggestionModalContentState extends State<_SuggestionModalContent> {
  final TextEditingController _controller = TextEditingController();
  String _selectedType = 'idea';
  bool _isSending = false;
  String _username = 'Cargando...';
  bool _showList = false;
  List<Map<String, dynamic>> _existingSuggestions = [];
  bool _loadingList = false;

  final Map<String, Map<String, dynamic>> _types = {
    'idea': {
      'label': 'Idea / Mejora',
      'icon': Icons.lightbulb_outline,
      'color': Colors.amberAccent,
    },
    'bug': {
      'label': 'Reportar error',
      'icon': Icons.bug_report_outlined,
      'color': Colors.redAccent,
    },
    'music': {
      'label': 'Música / Letra',
      'icon': Icons.music_note_outlined,
      'color': Colors.cyanAccent,
    },
    'general': {
      'label': 'Comentario',
      'icon': Icons.chat_bubble_outline,
      'color': Colors.deepPurpleAccent,
    },
  };

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  void _loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _username = prefs.getString('current_username') ?? 'Melómano Anónimo';
    });
  }

  void _loadSuggestionsList() async {
    setState(() {
      _loadingList = true;
      _showList = true;
    });
    final list = await SuggestionService.fetchSuggestions();
    if (mounted) {
      setState(() {
        _existingSuggestions = list;
        _loadingList = false;
      });
    }
  }

  void _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor escribe tu sugerencia')),
      );
      return;
    }

    setState(() {
      _isSending = true;
    });

    final success = await SuggestionService.sendSuggestion(
      type: _selectedType,
      message: text,
    );

    if (mounted) {
      setState(() {
        _isSending = false;
      });

      if (success) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF2E7D32),
            content: Row(
              children: const [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '¡Gracias! Tu sugerencia fue enviada y será revisada.',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text('No se pudo enviar. Revisa tu conexión a internet.'),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amberAccent.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.lightbulb, color: Colors.amberAccent, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Buzón de Sugerencias',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Ayúdanos a mejorar NovaMusic (v${UpdaterService.currentVersion})',
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                  _showList ? Icons.edit_note : Icons.history,
                  color: Colors.white70,
                ),
                tooltip: _showList ? 'Escribir sugerencia' : 'Ver sugerencias de la comunidad',
                onPressed: () {
                  if (_showList) {
                    setState(() => _showList = false);
                  } else {
                    _loadSuggestionsList();
                  }
                },
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white54),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_showList) ...[
            const Text(
              'Sugerencias enviadas por la comunidad:',
              style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 280,
              child: _loadingList
                  ? const Center(child: CircularProgressIndicator())
                  : _existingSuggestions.isEmpty
                      ? const Center(
                          child: Text(
                            'Aún no hay sugerencias enviadas. ¡Sé el primero!',
                            style: TextStyle(color: Colors.white38),
                          ),
                        )
                      : ListView.separated(
                          itemCount: _existingSuggestions.length,
                          separatorBuilder: (_, __) => const Divider(color: Colors.white10),
                          itemBuilder: (context, idx) {
                            final item = _existingSuggestions[idx];
                            final typeKey = item['type'] ?? 'general';
                            final typeInfo = _types[typeKey] ?? _types['general']!;
                            final user = item['username'] ?? 'Anónimo';
                            final msg = item['message'] ?? '';
                            final date = item['created_at'] != null
                                ? item['created_at'].toString().split('T').first
                                : '';

                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(typeInfo['icon'], color: typeInfo['color'], size: 22),
                              title: Text(
                                msg,
                                style: const TextStyle(color: Colors.white, fontSize: 13),
                              ),
                              subtitle: Text(
                                '$user • $date',
                                style: const TextStyle(color: Colors.white38, fontSize: 11),
                              ),
                            );
                          },
                        ),
            ),
          ] else ...[
            const Text(
              'Tipo de sugerencia:',
              style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _types.entries.map((entry) {
                  final isSelected = _selectedType == entry.key;
                  final color = entry.value['color'] as Color;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: ChoiceChip(
                      selected: isSelected,
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            entry.value['icon'],
                            size: 16,
                            color: isSelected ? Colors.black : color,
                          ),
                          const SizedBox(width: 6),
                          Text(entry.value['label']),
                        ],
                      ),
                      selectedColor: color,
                      backgroundColor: const Color(0xFF2C2C2C),
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.black : Colors.white,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        fontSize: 12,
                      ),
                      onSelected: (selected) {
                        if (selected) {
                          setState(() {
                            _selectedType = entry.key;
                          });
                        }
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              maxLines: 4,
              maxLength: 500,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Describe tu idea, reporte o qué te gustaría ver en la siguiente actualización...',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                filled: true,
                fillColor: const Color(0xFF161616),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Colors.white12),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Colors.white12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Colors.amberAccent),
                ),
                contentPadding: const EdgeInsets.all(14),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.person_outline, size: 14, color: Colors.white38),
                const SizedBox(width: 6),
                Text(
                  'Enviando como: $_username',
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: _isSending ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amberAccent,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  ),
                  icon: _isSending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                        )
                      : const Icon(Icons.send, size: 16),
                  label: Text(
                    _isSending ? 'Enviando...' : 'Enviar sugerencia',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
