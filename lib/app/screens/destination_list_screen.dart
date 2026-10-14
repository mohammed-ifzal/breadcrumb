import 'map_screen.dart';
import 'package:flutter/material.dart';
import 'package:breadcrumb/ai/speech_input.dart';
import 'package:breadcrumb/core/contracts.dart';
import 'package:breadcrumb/app/theme.dart';
import 'package:breadcrumb/app/widgets/ui/ui.dart';
import 'package:breadcrumb/app/wiring.dart';
import 'package:breadcrumb/ai/device_tier.dart' show basicMatchingLabel;
import 'navigate_screen.dart';
import 'scan_screen.dart';
import 'package:breadcrumb/core/start_places.dart';

class DestinationListScreen extends StatefulWidget {
  const DestinationListScreen({super.key, this.askStart = false});

  /// D33: open "Where are you?" straight away (Home's Navigate does).
  final bool askStart;

  @override
  State<DestinationListScreen> createState() => _DestinationListScreenState();
}

class _DestinationListScreenState extends State<DestinationListScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _isThinking = false;
  bool _isListening = false;
  String? _feedbackMessage;
  int _latestRequestId = 0;

  /// The last request and the place it resolved to, shown as "Understood".
  (String, String)? _understood;

  @override
  void initState() {
    super.initState();
    // D22: pick up a map saved since app start (Home loads it only once).
    _reloadMap().then((_) {
      if (widget.askStart && mounted) _showStartPlaceSelector(context);
    });
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
    if (_isThinking || _feedbackMessage != null || _understood != null) {
      setState(() {
        _isThinking = false;
        _feedbackMessage = null;
        _understood = null;
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
          _understood = (utterance, targetId);
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
        _understood = (utterance, targetId);
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

  Future<void> _scanForStart() async {
    final place = await Navigator.push<Place>(
      context,
      MaterialPageRoute(builder: (_) => const ScanScreen.forStart()),
    );
    if (place != null && mounted) {
      setState(() => Wiring.instance.currentPlaceId = place.id);
    }
  }

  /// D33: "Where are you?", places nearest first from the current choice
  /// (by default the map's last place), plus "Scan a sign".
  void _showStartPlaceSelector(BuildContext context) {
    final wiring = Wiring.instance;
    final map = wiring.map;
    final validPlaces = placesNearestFirst(
      map,
      wiring.effectiveCurrentPlaceId,
      planner: wiring.planner,
    );

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
                          'Where are you?',
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                  child: ListTile(
                    key: const ValueKey('start-scan'),
                    minTileHeight: BreadcrumbTheme.minTouch,
                    tileColor: BreadcrumbTheme.surface2,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BreadcrumbTheme.borderRadius,
                      side: BorderSide(color: BreadcrumbTheme.borderActive),
                    ),
                    leading: const Icon(
                      Icons.document_scanner_outlined,
                      color: BreadcrumbTheme.textPrimary,
                    ),
                    title: const Text(
                      'Scan a sign',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: BreadcrumbTheme.textPrimary,
                      ),
                    ),
                    subtitle: const Text(
                      'Point the camera at a place name',
                      style: TextStyle(fontSize: 15, color: BreadcrumbTheme.textSecondary),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _scanForStart();
                    },
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
                        key: ValueKey('start-place-${p.id}'),
                        minTileHeight: BreadcrumbTheme.minTouch,
                        shape: const RoundedRectangleBorder(
                          borderRadius: BreadcrumbTheme.borderRadius,
                        ),
                        selected: isSelected,
                        selectedColor: BreadcrumbTheme.textPrimary,
                        selectedTileColor: BreadcrumbTheme.surface2,
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
    final multiFloor = map.places.map((p) => p.floor).toSet().length > 1;
    final feedback = _feedbackMessage;
    final understood = _understood;
    final understoodPlace = understood == null
        ? null
        : map.places.cast<Place?>().firstWhere(
            (p) => p?.id == understood.$2,
            orElse: () => null,
          );

    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            // On-device AI status: only the states the app really has.
            Align(
              alignment: Alignment.centerLeft,
              child: ValueListenableBuilder<AiStatus>(
              valueListenable: wiring.aiStatus,
              builder: (context, status, _) {
                if (status.isReady) {
                  return const StatusPill(
                    label: 'On-device AI ready',
                    tone: StatusTone.accent,
                    dotColor: BreadcrumbTheme.accent,
                  );
                } else if (status.isLoading) {
                  return const StatusPill(
                    label: 'AI warming up…',
                    dotColor: BreadcrumbTheme.textSecondary,
                  );
                } else {
                  return Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const StatusPill(
                        // D30: unavailable is the basic tier (matcher + aliases).
                        label: basicMatchingLabel,
                        dotColor: BreadcrumbTheme.textMuted,
                      ),
                      if (status.reason != null && status.reason!.isNotEmpty) ...[
                        Text(
                          status.reason!,
                          style: BreadcrumbTheme.caption,
                        ),
                      ],
                    ],
                  );
                }
              },
            ),
            ),
            const SizedBox(height: 16),
            // D23: "You are at" selector
            _StartPlaceButton(
              placeName: currentPlace?.name ?? currentPlaceId,
              onTap: () => _showStartPlaceSelector(context),
            ),
            const SizedBox(height: 24),
            const Text('Where do you want to go?', style: BreadcrumbTheme.headline),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              onChanged: _onTextChanged,
              onSubmitted: (_) => _submit(),
              textInputAction: TextInputAction.go,
              style: BreadcrumbTheme.body.copyWith(fontSize: 18),
              decoration: InputDecoration(
                hintText: 'Say or type a place, e.g. coffee',
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
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
            const SizedBox(height: 16),
            PrimaryButton(
              label: 'Submit',
              icon: Icons.near_me_rounded,
              busy: _isThinking,
              onPressed: _submit,
            ),
            if (_isThinking) ...[
              const SizedBox(height: 16),
              const _NoteCard(
                icon: Icons.memory_rounded,
                color: BreadcrumbTheme.textPrimary,
                text: 'On-device AI is matching your words to a marked place.',
              ),
            ],
            if (feedback != null) ...[
              const SizedBox(height: 16),
              _NoteCard(
                icon: _isListening ? Icons.graphic_eq_rounded : Icons.info_outline_rounded,
                color: _isListening ? BreadcrumbTheme.textPrimary : BreadcrumbTheme.offRoute,
                text: feedback,
              ),
            ],
            if (understood != null && understoodPlace != null) ...[
              const SizedBox(height: 16),
              _UnderstoodCard(
                key: ValueKey(understood),
                query: understood.$1,
                place: understoodPlace,
                showFloor: multiFloor,
              ),
            ],
            const SizedBox(height: 16),
            PressScale(
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const MapScreen(),
                    ),
                  );
                },
                icon: const Icon(Icons.map_outlined),
                label: const Text('View floor map'),
              ),
            ),
            const SizedBox(height: 32),
            SectionHeader(
              'Marked places',
              trailing: places.length == 1 ? '1 place' : '${places.length} places',
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final place in places)
                  _PlaceChip(
                    place: place,
                    showFloor: multiFloor,
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
      color: BreadcrumbTheme.surface1,
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
                            fontWeight: FontWeight.w600,
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
                    fontWeight: FontWeight.w600,
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
        backgroundColor: BreadcrumbTheme.surface3,
        foregroundColor: BreadcrumbTheme.textPrimary,
        minimumSize: const Size(48, 48),
        side: BorderSide(color: listening ? BreadcrumbTheme.accent : BreadcrumbTheme.borderActive),
        shape: const RoundedRectangleBorder(borderRadius: BreadcrumbTheme.borderRadius),
      ),
      icon: listening ? const ListeningBars() : const Icon(Icons.mic_none_rounded, size: 26),
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
        color: BreadcrumbTheme.surface1,
        borderRadius: BreadcrumbTheme.borderRadius,
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: BreadcrumbTheme.body.copyWith(fontWeight: FontWeight.w500, color: color, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

/// `Understood: "query" → Place (Floor N)`. Fades in and slides up 10 dp.
class _UnderstoodCard extends StatelessWidget {
  const _UnderstoodCard({super.key, required this.query, required this.place, required this.showFloor});

  final String query;
  final Place place;
  final bool showFloor;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: BreadcrumbTheme.medium,
      curve: BreadcrumbTheme.ease,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, 10 * (1 - v)), child: child),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: BreadcrumbTheme.surface1,
          borderRadius: BreadcrumbTheme.borderRadius,
          border: Border.all(color: BreadcrumbTheme.accent.withValues(alpha: 0.6)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.check_circle_outline_rounded, color: BreadcrumbTheme.accent, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: BreadcrumbTheme.body,
                  children: [
                    const TextSpan(
                      text: 'Understood: ',
                      style: TextStyle(color: BreadcrumbTheme.textSecondary),
                    ),
                    TextSpan(text: '"$query"'),
                    const TextSpan(
                      text: '  →  ',
                      style: TextStyle(color: BreadcrumbTheme.accent),
                    ),
                    TextSpan(
                      text: place.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (showFloor)
                      TextSpan(
                        text: ' (Floor ${place.floor})',
                        style: const TextStyle(color: BreadcrumbTheme.textSecondary),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaceChip extends StatelessWidget {
  const _PlaceChip({required this.place, required this.onTap, this.showFloor = false});

  final Place place;
  final VoidCallback onTap;
  final bool showFloor;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      child: Material(
        color: BreadcrumbTheme.surface1,
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
              padding: const EdgeInsets.fromLTRB(12, 10, 16, 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.place_rounded, color: BreadcrumbTheme.accent, size: 20),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          place.name,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: BreadcrumbTheme.textPrimary,
                          ),
                        ),
                        if (place.aliases.isNotEmpty)
                          Text(
                            place.aliases.join(' · '),
                            style: BreadcrumbTheme.secondary,
                          ),
                      ],
                    ),
                  ),
                  if (showFloor) ...[
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: const BoxDecoration(
                        color: BreadcrumbTheme.surface3,
                        borderRadius: BreadcrumbTheme.borderRadiusSm,
                      ),
                      child: Text(
                        'F${place.floor}',
                        style: BreadcrumbTheme.eyebrow.copyWith(color: BreadcrumbTheme.textPrimary),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
