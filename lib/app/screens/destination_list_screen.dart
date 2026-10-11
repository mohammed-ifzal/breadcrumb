import 'map_screen.dart';
import 'package:flutter/material.dart';
import 'package:breadcrumb/ai/speech_input.dart';
import 'package:breadcrumb/core/contracts.dart';
import 'package:breadcrumb/app/theme.dart';
import 'package:breadcrumb/app/widgets/ui/ui.dart';
import 'package:breadcrumb/app/wiring.dart';
import 'package:breadcrumb/ai/device_tier.dart' show basicMatchingLabel;
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
    // D22: pick up a map saved since app start (Home loads it only once).
    _reloadMap();
    // Warm Gemma AI if not already warmed
    Wiring.instance.warmAi();
  }

  Future<void> _reloadMap() async {
    final loaded = await Wiring.instance.reloadActiveMap();
    if (loaded && mounted) setState(() {});
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
        final String errorText;
        if (err != null) {
          if (err == 'error_language_unavailable') {
            errorText = 'Speech pack missing on this phone. '
                'Type the place or pick from the list.';
          } else {
            errorText = '${describeSpeechError(err)}. '
                'Type the place or pick from the list.';
          }
        } else {
          errorText = 'No speech detected. Type the place or pick from the list.';
        }
        setState(() {
          _feedbackMessage = errorText;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isListening = false;
          _feedbackMessage = '$e. Type the place or pick from the list.';
        });
      }
    }
  }

  Future<void> _submit() async {
    final utterance = _controller.text.trim();
    if (utterance.isEmpty || _isThinking) return;

    final wiring = Wiring.instance;
    final map = wiring.map;
    final currentPlace = wiring.effectiveCurrentPlaceId;

    // 1. Always try fuzzy PlaceMatcher first (exact place name or alias works with no AI)
    final fuzzyMatch = wiring.placeMatcher.match(utterance, map);
    if (fuzzyMatch != null) {
      final targetId = fuzzyMatch.placeId;
      final isValid = map.places.any(
        (p) =>
            p.id == targetId &&
            p.kind != PlaceKind.junction &&
            p.id != currentPlace,
      );
      if (isValid) {
        setState(() {
          _isThinking = false;
          _feedbackMessage = null;
        });
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => NavigateScreen(destinationId: targetId),
          ),
        );
        return;
      }
    }

    // 2. No match and AI not ready/unavailable: immediately show message with no spinner
    if (!wiring.aiStatus.value.isReady) {
      setState(() {
        _isThinking = false;
        _feedbackMessage = wiring.aiStatus.value.isUnavailable
            ? 'No match. Pick from the list'
            : "AI isn't ready. Pick from the list";
      });
      return;
    }

    // 3. AI ready: call resolver with timeout, keeping existing stale-answer protection
    final requestId = ++_latestRequestId;
    setState(() {
      _isThinking = true;
      _feedbackMessage = null;
    });

    PlaceMatch? match;
    try {
      match = await wiring.destinationResolver
          .resolve(utterance, map)
          .timeout(wiring.destinationResolveTimeout);
    } catch (_) {
      match = null;
    }

    if (!mounted || requestId != _latestRequestId) return;

    final targetId = match?.placeId;
    final isValid = targetId != null &&
        map.places.any(
          (p) =>
              p.id == targetId &&
              p.kind != PlaceKind.junction &&
              p.id != currentPlace,
        );

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
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.75,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 12, 8),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Change Start Location',
                          style: BreadcrumbTheme.title,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        tooltip: 'Close',
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                    itemCount: validPlaces.length,
                    itemBuilder: (context, index) {
                      final p = validPlaces[index];
                      final isSelected = p.id == wiring.effectiveCurrentPlaceId;
                      return ListTile(
                        minTileHeight: BreadcrumbTheme.minTouch,
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.all(Radius.circular(16)),
                        ),
                        selected: isSelected,
                        selectedColor: BreadcrumbTheme.accent,
                        selectedTileColor: BreadcrumbTheme.accent.withValues(alpha: 0.08),
                        leading: Icon(
                          isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                          color: isSelected ? BreadcrumbTheme.accent : BreadcrumbTheme.textSecondary,
                        ),
                        title: Text(
                          p.name,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                            color: BreadcrumbTheme.textPrimary,
                          ),
                        ),
                        subtitle: p.aliases.isNotEmpty
                            ? Text(
                                p.aliases.join(', '),
                                style: const TextStyle(fontSize: 15, color: BreadcrumbTheme.textSecondary),
                              )
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
    final feedback = _feedbackMessage;

    return Scaffold(
      appBar: AppBar(
        actions: [
          // AI Ready indicator
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: ValueListenableBuilder<AiStatus>(
              valueListenable: wiring.aiStatus,
              builder: (context, status, _) {
                if (status.isReady) {
                  return const StatusPill(
                    label: 'AI ready',
                    icon: Icons.memory_rounded,
                    tone: StatusTone.accent,
                  );
                } else if (status.isLoading) {
                  return const StatusPill(
                    label: 'AI warming...',
                    icon: Icons.hourglass_top_rounded,
                    tone: StatusTone.neutral,
                  );
                } else {
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const StatusPill(
                        // D30: unavailable is the basic tier (matcher + aliases).
                        label: basicMatchingLabel,
                        icon: Icons.manage_search_rounded,
                        tone: StatusTone.neutral,
                      ),
                      if (status.reason != null && status.reason!.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Text(
                          status.reason!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: BreadcrumbTheme.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  );
                }
              },
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          children: [
            // D23: "You are at" selector
            _StartPlaceButton(
              placeName: currentPlace?.name ?? currentPlaceId,
              onTap: () => _showStartPlaceSelector(context),
            ),
            const SizedBox(height: 28),
            const Text('Where do you want to go?', style: BreadcrumbTheme.heading),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              onChanged: _onTextChanged,
              onSubmitted: (_) => _submit(),
              textInputAction: TextInputAction.go,
              style: BreadcrumbTheme.body.copyWith(fontSize: 19),
              decoration: InputDecoration(
                hintText: 'Where do you want to go?',
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
                prefixIcon: const Padding(
                  padding: EdgeInsets.only(left: 16, right: 8),
                  child: Icon(Icons.search_rounded, color: BreadcrumbTheme.textSecondary),
                ),
                suffixIcon: Padding(
                  padding: const EdgeInsets.all(6),
                  child: _MicButton(
                    listening: _isListening,
                    onPressed: _onMicPressed,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            PrimaryButton(
              label: 'Submit',
              icon: Icons.near_me_rounded,
              busy: _isThinking,
              onPressed: _submit,
            ),
            if (_isThinking) ...[
              const SizedBox(height: 14),
              const _NoteCard(
                icon: Icons.memory_rounded,
                color: BreadcrumbTheme.accent,
                text: 'On-device AI is matching your words to a marked place.',
              ),
            ],
            if (feedback != null) ...[
              const SizedBox(height: 14),
              _NoteCard(
                icon: _isListening ? Icons.graphic_eq_rounded : Icons.info_outline_rounded,
                color: _isListening ? BreadcrumbTheme.accent : BreadcrumbTheme.warning,
                text: feedback,
              ),
            ],
            const SizedBox(height: 14),
            PrimaryButton(
              label: 'View floor map',
              icon: Icons.map_rounded,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const MapScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 36),
            SectionHeader(
              'Marked places',
              trailing: places.length == 1 ? '1 place' : '${places.length} places',
            ),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final place in places)
                  _PlaceChip(
                    place: place,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => NavigateScreen(destinationId: place.id),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StartPlaceButton extends StatelessWidget {
  const _StartPlaceButton({required this.placeName, required this.onTap});

  final String placeName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: BreadcrumbTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BreadcrumbTheme.borderRadius,
        side: BorderSide(color: BreadcrumbTheme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: BreadcrumbTheme.minTouch),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                const Icon(Icons.my_location_rounded, color: BreadcrumbTheme.accent, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      text: 'You are at: ',
                      style: const TextStyle(color: BreadcrumbTheme.textSecondary),
                      children: [
                        TextSpan(
                          text: placeName,
                          style: const TextStyle(
                            color: BreadcrumbTheme.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    style: BreadcrumbTheme.body,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Change',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: BreadcrumbTheme.accent,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MicButton extends StatelessWidget {
  const _MicButton({required this.listening, required this.onPressed});

  final bool listening;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: listening ? 'Listening...' : 'Voice Search',
      style: IconButton.styleFrom(
        backgroundColor: listening
            ? BreadcrumbTheme.accent
            : BreadcrumbTheme.accent.withValues(alpha: 0.14),
        foregroundColor: listening ? BreadcrumbTheme.onAccent : BreadcrumbTheme.accent,
        minimumSize: const Size(BreadcrumbTheme.minTouch, BreadcrumbTheme.minTouch),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
      icon: Icon(listening ? Icons.mic_rounded : Icons.mic_none_rounded, size: 28),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BreadcrumbTheme.borderRadius,
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 16, height: 1.35, fontWeight: FontWeight.w600, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaceChip extends StatelessWidget {
  const _PlaceChip({required this.place, required this.onTap});

  final Place place;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: BreadcrumbTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BreadcrumbTheme.borderRadius,
        side: BorderSide(color: BreadcrumbTheme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: BreadcrumbTheme.minTouch),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 18, 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.place_rounded, color: BreadcrumbTheme.accent, size: 22),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        place.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: BreadcrumbTheme.textPrimary,
                        ),
                      ),
                      if (place.aliases.isNotEmpty)
                        Text(
                          place.aliases.join(' · '),
                          style: const TextStyle(fontSize: 14, color: BreadcrumbTheme.textSecondary),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
