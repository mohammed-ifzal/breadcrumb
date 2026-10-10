/// Every threshold in the app. Starting guesses from `docs/CONTRACTS.md`; retune them
/// with recorded traces. Only the captain changes this file.
library;

/// deg/s above which the phone is turning.
const double turnRateMin = 15;

/// ms the rate must stay below [turnRateMin] to finish a turn.
const int turnSettleMs = 300;

/// Minimum total degrees to count as a turn.
const double turnMinAngle = 60;

/// Motion samples further apart than this many ms reset turn integration.
const int maxMotionGapMs = 200;

/// MapBuilder rounds each recorded turn angle to the nearest multiple of this.
/// 90: corridors at the venue are orthogonal (D25).
const double turnSnapDegrees = 90;

/// Leg-to-leg changes smaller than this are "straight on".
const double straightTolerance = 30;

/// Changes larger than this are "turn around".
const double turnAroundAngle = 150;

/// Say "turn now" this many steps before the end of a leg.
const int turnNowSteps = 3;

/// A turn snaps in the last half of a leg… (D27; was 0.4)
const double snapZone = 0.5;

/// …or within this many steps of its end (D27; was 8). Off route, a matching
/// turn within twice this of the next turning point snaps back on.
const int snapSteps = 10;

/// A turn this many steps after a node the position already moved past (by
/// "I am here", a sign or a turn snap) is that node's turn, not off route (D26).
const int lateTurnSteps = 3;

/// Extra route cost, in steps, of each stairs, escalator or lift corridor, on
/// top of its own steps (D24).
const int floorChangeCostSteps = 20;

/// Walking 30% of a run past its corner with no turn seen moves on to the next
/// leg (D27; was a rescan prompt).
const double overwalk = 0.3;

/// Minimum fuzzy score for a place match.
const double matchThreshold = 0.8;

/// m/s² peak needed to count a step (fallback only).
const double accelPeakThreshold = 11.5;

/// Minimum ms between fallback step peaks.
const int accelPeakMinGapMs = 300;

/// Longest wait for Gemma to choose a destination before giving up (null).
const int gemmaTimeoutMs = 20000;
