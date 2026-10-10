import 'package:flutter/material.dart';
import 'package:breadcrumb/ai/speech_input.dart';
import 'package:breadcrumb/core/contracts.dart';
import 'package:breadcrumb/app/theme.dart';
import 'package:breadcrumb/app/wiring.dart';
import 'navigate_screen.dart';

class DestinationListScreen extends StatefulWidget {
  const DestinationListScreen({super.key});

  @override
  State<DestinationListScreen> createState() => _DestinationListScreenState();
}

class _DestinationListScreenState extends State<DestinationListScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _isThinking = false;
  bool _isListening = false;
  String? _feedbackMessage;
  int _latestRequestId = 0;

  @override
  void initState() {
    super.initState();
    // Warm Gemma AI if not already warmed
    Wiring.instance.warmAi();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged(String _) {
    _latestRequestId++;
    if (_isThinking || _feedbackMessage != null) {
      setState(() {
        _isThinking = false;
        _feedbackMessage = null;
      });
    }
  }

  Future<void> _onMicPressed() async {
    if (_isThinking || _isListening) return;

    setState(() {
      _isListening = true;
      _feedbackMessage = 'Listening... Speak your destination';
    });

    try {
      final heard = await Wiring.instance.speechInput.listen(
        localeId: speechLocaleEnglish,
      );

      if (!mounted) return;

      setState(() {
        _isListening = false;
      });

      if (heard != null && heard.isNotEmpty) {
        _controller.text = heard;
        _submit();
      } else {
        final err = Wiring.instance.speechInput.lastError;
        setState(() {
          _feedbackMessage = err != null
              ? describeSpeechError(err)
              : 'No speech detected. Try speaking again or type.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isListening = false;
          _feedbackMessage = 'Speech error: $e';
        });
      }
    }
  }

  Future<void> _submit() async {
    final utterance = _controller.text.trim();
    if (utterance.isEmpty || _isThinking) return;

    final requestId = ++_latestRequestId;
    setState(() {
      _isThinking = true;
      _feedbackMessage = null;
    });

    final wiring = Wiring.instance;
    final map = wiring.map;
    final currentPlace = wiring.effectiveCurrentPlaceId;

    PlaceMatch? match;
    try {
      match = await wiring.destinationResolver.resolve(utterance, map);
    } catch (_) {
      match = null;
    }

    if (!mounted || requestId != _latestRequestId) return;

    final targetId = match?.placeId;
    final isValid = targetId != null &&
        map.places.any((p) =>
            p.id == targetId &&
            p.kind != PlaceKind.junction &&
            p.id != currentPlace);

    if (isValid) {
      setState(() {
        _isThinking = false;
      });
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => NavigateScreen(destinationId: targetId),
        ),
      );
    } else {
      setState(() {
        _isThinking = false;
        _feedbackMessage = "Didn't catch that, pick from the list";
      });
    }
  }

  void _showStartPlaceSelector(BuildContext context) {
    final wiring = Wiring.instance;
    final map = wiring.map;
    final validPlaces = map.places
        .where((p) => p.kind != PlaceKind.junction)
        .toList();

    showModalBottomSheet(
      context: context,
      backgroundColor: BreadcrumbTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Change Start Location',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: BreadcrumbTheme.textLight,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: validPlaces.length,
                    itemBuilder: (context, index) {
                      final p = validPlaces[index];
                      final isSelected = p.id == wiring.effectiveCurrentPlaceId;
                      return ListTile(
                        leading: Icon(
                          isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                          color: isSelected ? BreadcrumbTheme.accent : BreadcrumbTheme.textMuted,
                        ),
                        title: Text(
                          p.name,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: BreadcrumbTheme.textLight,
                          ),
                        ),
                        subtitle: p.aliases.isNotEmpty
                            ? Text(p.aliases.join(', '), style: const TextStyle(color: BreadcrumbTheme.textMuted))
                            : null,
                        onTap: () {
                          setState(() {
                            wiring.currentPlaceId = p.id;
                          });
                          Navigator.pop(context);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final wiring = Wiring.instance;
    final map = wiring.map;
    final currentPlaceId = wiring.effectiveCurrentPlaceId;
    final currentPlace = map.places.cast<Place?>().firstWhere(
      (p) => p?.id == currentPlaceId,
      orElse: () => null,
    );
    final places = map.places
        .where((p) => p.kind != PlaceKind.junction && p.id != currentPlaceId)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Destination'),
        actions: [
          // AI Ready indicator
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: ValueListenableBuilder<bool>(
              valueListenable: wiring.isAiReady,
              builder: (context, ready, _) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: ready ? const Color(0xFF064E3B) : const Color(0xFF334155),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: ready ? const Color(0xFF059669) : const Color(0xFF475569),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        ready ? Icons.check_circle : Icons.hourglass_top,
                        size: 14,
                        color: ready ? const Color(0xFF6EE7B7) : const Color(0xFF94A3B8),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        ready ? 'AI ready' : 'AI warming...',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: ready ? const Color(0xFF6EE7B7) : const Color(0xFFCBD5E1),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // D23: "You are at" selector
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: BreadcrumbTheme.surface,
              border: Border(
                bottom: BorderSide(color: BreadcrumbTheme.surfaceBorder),
              ),
            ),
            child: InkWell(
              onTap: () => _showStartPlaceSelector(context),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    const Icon(Icons.my_location, color: BreadcrumbTheme.accent, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'You are at: ${currentPlace?.name ?? currentPlaceId}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: BreadcrumbTheme.textLight,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(Icons.arrow_drop_down, color: BreadcrumbTheme.textMuted),
                  ],
                ),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        onChanged: _onTextChanged,
                        onSubmitted: (_) => _submit(),
                        decoration: const InputDecoration(
                          hintText: 'Where do you want to go?',
                          labelText: 'Where do you want to go?',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Active Mic Button
                    IconButton(
                      icon: Icon(
                        _isListening ? Icons.mic : Icons.mic_none,
                        color: _isListening ? Colors.redAccent : Colors.white,
                        size: 28,
                      ),
                      tooltip: _isListening ? 'Listening...' : 'Voice Search',
                      onPressed: _onMicPressed,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  style: BreadcrumbTheme.primaryButton.copyWith(
                    minimumSize: const WidgetStatePropertyAll(Size(double.infinity, 52)),
                    textStyle: const WidgetStatePropertyAll(
                      TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  onPressed: _isThinking ? null : _submit,
                  child: _isThinking
                      ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(width: 10),
                            Text('Thinking...'),
                          ],
                        )
                      : const Text('Submit'),
                ),
                if (_feedbackMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _feedbackMessage!,
                    style: TextStyle(
                      color: _isListening ? const Color(0xFF93C5FD) : Colors.amber.shade400,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: places.length,
              itemBuilder: (context, index) {
                final place = places[index];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                  title: Text(
                    place.name,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                  ),
                  subtitle: place.aliases.isNotEmpty
                      ? Text(
                          'Aliases: ${place.aliases.join(", ")}',
                          style: const TextStyle(color: BreadcrumbTheme.textMuted),
                        )
                      : null,
                  trailing: const Icon(Icons.chevron_right, color: BreadcrumbTheme.textMuted),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => NavigateScreen(destinationId: place.id),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
