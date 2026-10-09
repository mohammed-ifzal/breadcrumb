/// Every threshold in the app. Starting guesses from `docs/CONTRACTS.md`; retune them
/// with recorded traces. Only the captain changes this file.
library;

/// deg/s above which the phone is turning.
const double turnRateMin = 25;

/// ms the rate must stay below [turnRateMin] to finish a turn.
const int turnSettleMs = 500;

/// Minimum total degrees to count as a turn.
const double turnMinAngle = 60;

/// Motion samples further apart than this many ms reset turn integration.
const int maxMotionGapMs = 200;

/// MapBuilder rounds each recorded turn angle to the nearest multiple of this.
const double turnSnapDegrees = 45;

/// Leg-to-leg changes smaller than this are "straight on".
const double straightTolerance = 30;

/// Changes larger than this are "turn around".
const double turnAroundAngle = 150;

/// Say "turn now" this many steps before the end of a leg.
const int turnNowSteps = 3;

/// A turn snaps in the last 40% of a leg…
const double snapZone = 0.4;

/// …or within this many steps of its end.
const int snapSteps = 8;

/// 30% past a leg's length triggers a rescan prompt.
const double overwalk = 0.3;

/// Minimum fuzzy score for a place match.
const double matchThreshold = 0.8;

/// m/s² peak needed to count a step (fallback only).
const double accelPeakThreshold = 11.5;

/// Minimum ms between fallback step peaks.
const int accelPeakMinGapMs = 300;
