/// Temporary D29-compatible local types; replace this export after D29 lands.
library;

enum MotionState { walking, still, handling }

enum Placement { hand, pocket, unknown }

class MotionStateEvent {
  const MotionStateEvent(this.state, this.tMs);
  final MotionState state;
  final int tMs;
}

class PlacementEvent {
  const PlacementEvent(this.placement, this.tMs);
  final Placement placement;
  final int tMs;
}
