import 'package:flutter/material.dart';
import 'package:breadcrumb/core/contracts.dart';
import 'package:breadcrumb/core/tuning.dart' as tuning;
import 'package:breadcrumb/app/theme.dart';
import 'package:breadcrumb/app/widgets/ui/ui.dart';
import 'package:breadcrumb/app/widgets/trail_view.dart';
import 'package:breadcrumb/app/wiring.dart';
import 'navigate_screen.dart';

/// Full-screen floor map showing the recorded or demo trail, places, and route preview.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  String? _chosenStartId;
  String? _chosenDestId;
  RoutePlan? _previewRoute;
  String? _routeSummary;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final map = Wiring.instance.map;
    final validPlaces = map.places.where((p) => p.kind != PlaceKind.junction).toList();
    final effectiveCurrent = Wiring.instance.effectiveCurrentPlaceId;
    if (validPlaces.any((p) => p.id == effectiveCurrent)) {
      _chosenStartId = effectiveCurrent;
    } else if (validPlaces.isNotEmpty) {
      _chosenStartId = validPlaces.first.id;
    }
    _reloadMap();
  }

  Future<void> _reloadMap() async {
    final loaded = await Wiring.instance.reloadActiveMap();
    if (!mounted) return;
    if (loaded) {
      final map = Wiring.instance.map;
      final validPlaces = map.places.where((p) => p.kind != PlaceKind.junction).toList();
      final effectiveCurrent = Wiring.instance.effectiveCurrentPlaceId;
      setState(() {
        if (validPlaces.any((p) => p.id == effectiveCurrent)) {
          _chosenStartId = effectiveCurrent;
        } else if (validPlaces.isNotEmpty) {
          _chosenStartId = validPlaces.first.id;
        }
        _updateRoutePreview();
      });
    }
  }

  void _updateRoutePreview() {
    final map = Wiring.instance.map;
    final startId = _chosenStartId;
    final destId = _chosenDestId;

    if (startId == null || destId == null) {
      _previewRoute = null;
      _routeSummary = null;
      _errorMessage = null;
      return;
    }

    if (startId == destId) {
      final place = map.places.cast<Place?>().firstWhere(
        (p) => p?.id == startId,
        orElse: () => null,
      );
      final placeName = place?.name ?? startId;
      _previewRoute = null;
      _routeSummary = "You're already at $placeName";
      _errorMessage = null;
      return;
    }

    try {
      final route = Wiring.instance.planner.plan(map, startId, destId);
      _previewRoute = route;
      _errorMessage = null;

      var turns = 0;
      for (var i = 0; i < route.legs.length - 1; i++) {
        final angle = turnBetween(
          route.legs[i].heading,
          route.legs[i + 1].heading,
        ).abs();
        if (angle >= tuning.straightTolerance) {
          turns++;
        }
      }

      final destPlace = map.places.cast<Place?>().firstWhere(
        (p) => p?.id == destId,
        orElse: () => null,
      );
      final destName = destPlace?.name ?? destId;
      final stepWord = route.totalSteps == 1 ? 'step' : 'steps';
      final turnWord = turns == 1 ? 'turn' : 'turns';
      _routeSummary = '$destName · ${route.totalSteps} $stepWord · $turns $turnWord';
    } on ArgumentError catch (e) {
      _previewRoute = null;
      _routeSummary = null;
      _errorMessage = e.message?.toString() ?? 'No route found';
    } catch (e) {
      _previewRoute = null;
      _routeSummary = null;
      _errorMessage = 'Could not plan route: $e';
    }
  }

  void _showPlacePicker({required bool isStart}) {
    final map = Wiring.instance.map;
    final validPlaces = map.places.where((p) => p.kind != PlaceKind.junction).toList();
    final selectedId = isStart ? _chosenStartId : _chosenDestId;

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
                      Expanded(
                        child: Text(
                          isStart ? 'Change Start Location' : 'Choose Destination',
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
                      final isSelected = p.id == selectedId;
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
                            if (isStart) {
                              _chosenStartId = p.id;
                              Wiring.instance.currentPlaceId = p.id;
                            } else {
                              _chosenDestId = p.id;
                            }
                            _updateRoutePreview();
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
    final validPlaces = map.places.where((p) => p.kind != PlaceKind.junction).toList();
    final placeCount = validPlaces.length;
    final totalSteps = map.corridors.fold<int>(0, (sum, c) => sum + c.steps);
    final isDemo = wiring.isDemoMap;

    final placeWord = placeCount == 1 ? 'place' : 'places';
    final stepWord = totalSteps == 1 ? 'step' : 'steps';
    final walkDesc = isDemo ? 'Demo map' : 'recorded in one walk';
    final summaryLine = '$placeCount $placeWord · $totalSteps $stepWord · $walkDesc';

    final startPlace = map.places.cast<Place?>().firstWhere(
      (p) => p?.id == _chosenStartId,
      orElse: () => null,
    );
    final destPlace = map.places.cast<Place?>().firstWhere(
      (p) => p?.id == _chosenDestId,
      orElse: () => null,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Floor map'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back',
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                summaryLine,
                style: BreadcrumbTheme.bodySecondary.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BreadcrumbTheme.borderRadius,
                child: ColoredBox(
                  color: BreadcrumbTheme.surface,
                  child: AspectRatio(
                    aspectRatio: 1.1,
                    child: TrailView(
                      map: map,
                      route: _previewRoute,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const SectionHeader('Route preview'),
              _SelectorCard(
                icon: Icons.my_location_rounded,
                label: 'You are at',
                value: startPlace?.name ?? 'Select start',
                onTap: () => _showPlacePicker(isStart: true),
              ),
              const SizedBox(height: 10),
              _SelectorCard(
                icon: Icons.place_rounded,
                label: 'Destination',
                value: destPlace?.name ?? 'Choose destination',
                onTap: () => _showPlacePicker(isStart: false),
              ),
              if (_routeSummary != null) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: BreadcrumbTheme.surfaceRaised,
                    borderRadius: BreadcrumbTheme.borderRadius,
                    border: Border.all(
                      color: _previewRoute != null
                          ? BreadcrumbTheme.accent.withValues(alpha: 0.5)
                          : BreadcrumbTheme.border,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _previewRoute != null ? Icons.route_rounded : Icons.info_outline_rounded,
                        color: _previewRoute != null ? BreadcrumbTheme.accent : BreadcrumbTheme.textSecondary,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _routeSummary!,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: _previewRoute != null ? BreadcrumbTheme.accent : BreadcrumbTheme.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: BreadcrumbTheme.warning.withValues(alpha: 0.1),
                    borderRadius: BreadcrumbTheme.borderRadius,
                    border: Border.all(color: BreadcrumbTheme.warning.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: BreadcrumbTheme.warning, size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: BreadcrumbTheme.warning,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              PrimaryButton(
                label: 'Start',
                icon: Icons.navigation_rounded,
                onPressed: _previewRoute != null
                    ? () {
                        wiring.currentPlaceId = _chosenStartId;
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => NavigateScreen(
                              destinationId: _chosenDestId!,
                            ),
                          ),
                        );
                      }
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectorCard extends StatelessWidget {
  const _SelectorCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(icon, color: BreadcrumbTheme.accent, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: BreadcrumbTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        value,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: BreadcrumbTheme.textPrimary,
                        ),
                      ),
                    ],
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
