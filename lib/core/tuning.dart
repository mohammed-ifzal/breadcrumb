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

/// Apply a low-pass only when native gravity is missing or fails. No step/turn gate.
const bool gravityFallbackLowPassEnabled = true;

/// Previous-vector weight for the optional native accelerometer gravity estimate.
const double gravityFallbackLowPassAlpha = 0.8;

/// Preserve the latest changed lux sample during the mandatory 5 Hz transport cap.
/// False drops intervening light changes instead; the cap remains in both modes.
const bool lightCoalescingEnabled = true;

/// Rapid gravity direction change used only by the separate motion classifier.
const double handlingGravityDeg = 35;
const int handlingWindowMs = 600;

/// Linger after the latest excessive angle, rather than delaying handling entry.
const int handlingHoldMs = 1200;

const int boutMinSteps = 3;
const int boutMinGapMs = 250;
const int boutMaxGapMs = 1500;

/// Off: the T2 gates are standalone and not wired into the Tracker yet.
const bool useBoutGating = false;
const bool useHandlingGate = false;
const bool usePlacement = false;

const double pocketLuxMax = 10;

/// Pocket requires continuous near-and-dark for MORE than this many ms.
const int pocketHoldMs = 2000;

// ---------------------------------------------------------------------------
// D29: robust core. Each feature has a flag, so it can be switched off on the
// phone if it misbehaves.
// ---------------------------------------------------------------------------

/// Pass raw turns through the TurnConfirmer before the Tracker and the
/// MapBuilder (D29).
const bool useTurnConfirmer = true;

/// A raw turn counts only once this many steps follow it…
const int turnConfirmSteps = 2;

/// …within this many ms of it; otherwise it is dropped. 8000: in the spike
/// walk the tester paused after each turn and the second step came 5.1-5.5 s
/// later (D29 replay sweep: 6000 is the smallest window with 0 missed).
const int turnConfirmWindowMs = 8000;

/// Track position confidence and ask "Are you at {place}?" when it drops (D29).
const bool useConfidence = true;

/// Confidence is multiplied by this on every step.
const double confidenceDecayPerStep = 0.98;

/// Confidence after a snapped corner (an "I'm here" tap or arrival resets to 1.0).
const double confidenceCornerReset = 0.9;

/// Below this the Guide asks "Are you at {next place}?", once per leg.
const double confidenceAskBelow = 0.5;

/// Arrive only after enough steps on the final leg and all its turns (D29).
const bool useArrivalGuard = false;

/// Fraction of the final leg's steps needed before arrival counts.
const double arrivalMinFraction = 0.7;

/// No step for this many ms means MotionState.still (T2, sensing).
const int stillAfterMs = 1500;

/// Rotation rate (deg/s, any axis but yaw) above which the phone is being
/// handled, not carried by a turning body (T2, sensing).
const double handlingRotationMin = 120;

/// Total RAM (MB) at or above which the device is DeviceTier.full.
const int fullTierMinRamMb = 8000;

// ---------------------------------------------------------------------------
// D30: aliases and device tier.
// ---------------------------------------------------------------------------

/// At most this many aliases Gemma suggests for a marked place.
const int maxAliases = 8;

/// Words in one suggested alias, at most.
const int maxAliasWords = 3;

/// Longest wait for Gemma's alias suggestions before the place keeps none.
const int aliasSuggestTimeoutMs = 15000;
