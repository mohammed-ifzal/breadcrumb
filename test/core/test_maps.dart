import 'package:breadcrumb/core/contracts.dart';

/// The synthetic walk MapBuilder would produce from the demo (docs/DEMO.md):
///
/// start --12 steps, heading 0--> j1 (left turn) --10 steps, heading 90-->
/// food_counter (mark) --8 steps, heading 90--> j2 (right turn) --6 steps,
/// heading 0--> stage_side (mark)
const demoMap = MapGraph(
  name: 'Table loop',
  start: 'start',
  places: [
    Place(id: 'start', name: 'Start', kind: PlaceKind.start),
    Place(id: 'j1', name: 'Junction 1', kind: PlaceKind.junction),
    Place(
      id: 'food_counter',
      name: 'Food counter',
      aliases: ['canteen', 'खाना काउंटर'],
      kind: PlaceKind.place,
    ),
    Place(id: 'j2', name: 'Junction 2', kind: PlaceKind.junction),
    Place(id: 'stage_side', name: 'Stage side', kind: PlaceKind.place),
  ],
  corridors: [
    Corridor(id: 'c1', from: 'start', to: 'j1', steps: 12, heading: 0),
    Corridor(id: 'c2', from: 'j1', to: 'food_counter', steps: 10, heading: 90),
    Corridor(id: 'c3', from: 'food_counter', to: 'j2', steps: 8, heading: 90),
    Corridor(id: 'c4', from: 'j2', to: 'stage_side', steps: 6, heading: 0),
  ],
);

/// Two floors (D24): Entrance and the stairs foot on Floor 0, the Cafe on Floor 1.
///
/// entrance --10, heading 0--> stairs_foot --stairs, 12 steps, +1, heading 0-->
/// stairs_top (junction, Floor 1) --8, heading 90 (left)--> cafe.
/// Also entrance --4, heading 180--> lift_g --lift, 0 steps, +1--> lift_1
/// (junction, Floor 1) --40, heading 90--> cafe.
const twoFloorMap = MapGraph(
  name: 'Two floors',
  start: 'entrance',
  places: [
    Place(id: 'entrance', name: 'Entrance', kind: PlaceKind.start),
    Place(id: 'stairs_foot', name: 'Stairs', kind: PlaceKind.place),
    Place(id: 'stairs_top', name: 'Landing', kind: PlaceKind.junction, floor: 1),
    Place(id: 'cafe', name: 'Cafe', kind: PlaceKind.place, floor: 1),
    Place(id: 'lift_g', name: 'Lift', kind: PlaceKind.place),
    Place(id: 'lift_1', name: 'Lift floor 1', kind: PlaceKind.junction, floor: 1),
  ],
  corridors: [
    Corridor(id: 'c1', from: 'entrance', to: 'stairs_foot', steps: 10, heading: 0),
    Corridor(
      id: 'c2',
      from: 'stairs_foot',
      to: 'stairs_top',
      steps: 12,
      heading: 0,
      kind: CorridorKind.stairs,
      floorDelta: 1,
    ),
    Corridor(id: 'c3', from: 'stairs_top', to: 'cafe', steps: 8, heading: 90),
    Corridor(id: 'c4', from: 'entrance', to: 'lift_g', steps: 4, heading: 180),
    Corridor(
      id: 'c5',
      from: 'lift_g',
      to: 'lift_1',
      steps: 0,
      heading: 180,
      kind: CorridorKind.lift,
      floorDelta: 1,
    ),
    Corridor(id: 'c6', from: 'lift_1', to: 'cafe', steps: 40, heading: 90),
  ],
);
