/// Which AI the phone runs (D30). [DeviceTier.full]: enough RAM and Gemma
/// loaded, so a request PlaceMatcher can't place goes to Gemma. [DeviceTier.basic]:
/// Gemma is never loaded; PlaceMatcher over names and aliases (from
/// alias_suggester.dart or typed) is all there is, and the AI chip says
/// [basicMatchingLabel]. Pure Dart: RAM and loading come in as functions.
library;

import 'dart:async';

import '../core/contracts.dart';
import '../core/tuning.dart';
import 'destination_resolver.dart';

/// The AI chip on the basic tier.
const String basicMatchingLabel = 'Basic matching';

/// The AI chip on the full tier.
const String fullTierLabel = 'AI on-device';

String aiChipLabel(DeviceTier tier) =>
    tier == DeviceTier.full ? fullTierLabel : basicMatchingLabel;

/// Whether a phone with [totalRamMb] may try to load Gemma. 0 means unknown
/// (`SensingSource.totalRamMb()`), and then loading decides.
bool ramAllowsGemma(int totalRamMb) =>
    totalRamMb <= 0 || totalRamMb >= fullTierMinRamMb;

/// Decides the tier once: reads the RAM, loads Gemma only when the RAM allows it,
/// and settles on [DeviceTier.full] only if that load succeeds. Concurrent and
/// later calls to [decide] share the first answer.
class AiTierGate {
  AiTierGate({
    required this.totalRamMb,
    required this.loadGemma,
    this.loadTimeout,
  });

  /// `SensingSource.totalRamMb`; a throw counts as unknown (0).
  final Future<int> Function() totalRamMb;

  /// Loads and warms up Gemma; throws when it can't.
  final Future<void> Function() loadGemma;

  /// A load slower than this counts as failed; null waits for ever.
  final Duration? loadTimeout;

  Future<DeviceTier>? _decision;
  DeviceTier? _tier;

  /// Null until [decide] has finished.
  DeviceTier? get tier => _tier;

  /// Why the tier is basic, for logs and the debug screen; null on full.
  String? reason;

  /// The RAM [decide] read, in MB (0 when unknown).
  int ramMb = 0;

  Future<DeviceTier> decide() => _decision ??= _decide();

  Future<DeviceTier> _decide() async {
    try {
      ramMb = await totalRamMb();
    } catch (_) {
      ramMb = 0;
    }
    if (!ramAllowsGemma(ramMb)) {
      reason = '$ramMb MB RAM, below $fullTierMinRamMb MB';
      return _tier = DeviceTier.basic;
    }
    try {
      final load = loadGemma();
      final limit = loadTimeout;
      await (limit == null ? load : load.timeout(limit));
      return _tier = DeviceTier.full;
    } catch (e) {
      reason = 'Gemma did not load: $e';
      return _tier = DeviceTier.basic;
    }
  }
}

/// The basic-tier resolver: PlaceMatcher over names and aliases, nothing else.
class BasicDestinationResolver implements DestinationResolver {
  BasicDestinationResolver(this.matcher);

  final PlaceMatcher matcher;

  @override
  Future<PlaceMatch?> resolve(String utterance, MapGraph map) async =>
      utterance.trim().isEmpty ? null : matcher.match(utterance, map);
}

/// The resolver for [tier]: Gemma as a fallback only on [DeviceTier.full] with
/// a [chooser]; otherwise [BasicDestinationResolver].
DestinationResolver destinationResolverFor(
  DeviceTier tier, {
  required PlaceMatcher matcher,
  PlaceChooser? chooser,
}) => tier == DeviceTier.full && chooser != null
    ? GemmaDestinationResolver(matcher: matcher, chooser: chooser)
    : BasicDestinationResolver(matcher);
