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
