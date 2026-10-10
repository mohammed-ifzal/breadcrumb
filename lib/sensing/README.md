# Teammate 2 sensing spike

Kotlin registers one `breadcrumb/sensing` EventChannel in MainActivity. Gravity and
acceleration are sampled alongside the gyroscope; each gyro callback emits the latest
acceleration magnitude and gyro projected onto unit gravity, converted to degrees per
second. The sampling period requests 50 Hz; device delivery may vary. Kotlin performs
no step/turn detection. Subscription cancellation and activity pause unregister all
listeners. Required gyro/accelerometer failures are stream errors. Dedicated gravity is optional; absence or failure uses the accelerometer estimate. The optional step sensor is isolated: registration/permission or step-event delivery failure emits stepDetector:false once and leaves all motion listeners running.

`StepDetector.onMotion(t, accel)` detects a local peak on its descending sample, using
the first timestamp of a plateau and tuning's peak threshold/minimum gap. It is enabled
only after Kotlin reports that hardware step detection is absent. `TurnDetector`
integrates each qualifying sample over the preceding timestamp interval, waits for a
continuous settling period, then emits the entire angle. The first motion sample sets
the time origin; duplicate/out-of-order and non-finite samples are ignored. Thresholds
come from `lib/core/tuning.dart`. Both detectors use shared `tuning.maxMotionGapMs` (currently 200 ms): longer gaps discard step peaks and turn integration/settling, with the current sample establishing a fresh baseline.

`SensingSource` implements the core interface. Subscribe through `events()`; consumers
share one native subscription. `hardwareStepDetector` is a ValueNotifier: unknown
before the first notice/sample, then yes/no. Only the native optional-step absence/failure notice enables fallback; a required motion sensor error does not.
Await `startTrace(meta)` before collecting a test walk; it waits for hardware capability
and records `stepSource` as `detector` or `accel`. The native stream's timestamp origin
is subscription start, shared by event consumers and trace recording. Supply `map`,
`walker`, `from`, and `to` for a complete trace. Raw native events are preserved;
fallback steps and derived turns are regenerated from motion during replay.
`mark(note)` writes a ground-truth note with a walk-relative timestamp. Await
`stopTrace()` to flush/close. Dispose the source when its session ends.

`TraceRecorder` uses the already-installed path_provider and writes to the app's private
`documents/traces/` directory. Every JSONL file starts with a meta line. Names contain
date, sanitized walker/map and a unique microsecond timestamp; repeated walks do not
overwrite earlier files. Recording outside an active trace is a no-op. A write/flush/close failure stops that trace, logs once, preserves its path/error and leaves sensing running. A new trace can be started after cleanup. `traceState` exposes recording status and the full path, including after stop.

`SensingDebugScreen` is a standalone screen showing detector capability, step count,
last turn in degrees (left positive), Reset, Start/Stop trace and a note/Mark button. Start trace explicitly begins a `sensing_spike` JSONL file; the full path stays visible after stop. Reset clears only the displayed step count and angle, without restarting sensors or modifying the trace. The screen
owns/disposes its source, including one injected for testing. This screen never requests
permissions. Teammate 3 must wire it into the app after external permission grant:

```text
adb shell pm grant com.teamgroza.breadcrumb android.permission.ACTIVITY_RECOGNITION
```

This spike supports D15's real live recording. It does not implement MapBuilder or
record_screen.dart, draw a fabricated trail, or require signs. No contract/tuning or
shared build changes were made. The motion-gap limit is now read directly from shared tuning. Test with `flutter test --concurrency=1` if parallel
Flutter test compilation exhausts memory on the laptop.

## Android build memory failure (10 Oct)

The first captured failure was `Gradle build daemon disappeared unexpectedly` at
`build_log.txt:61`. It did not identify a Kotlin source line. The JVM crash log
`android/hs_err_pid11692.log:2-3` reported insufficient memory and a failed native
allocation of 1,245,708,288 bytes. The current `android/gradle.properties:1` allows an
8 GB Java heap and 4 GB metaspace. No Kotlin changes were needed.

A debug APK built successfully with the following temporary process-only override.
This leaves all captain-owned files unchanged and restores the shell's original value:

```powershell
$previousGradleOpts = $env:GRADLE_OPTS
try {
    $env:GRADLE_OPTS = '-Dorg.gradle.jvmargs="-Xmx2G -XX:MaxMetaspaceSize=768m -XX:ReservedCodeCacheSize=256m -XX:ActiveProcessorCount=2 -XX:+HeapDumpOnOutOfMemoryError" -Dorg.gradle.workers.max=1 -Dorg.gradle.parallel=false -Dorg.gradle.daemon=false'
    flutter build apk --debug
} finally {
    $env:GRADLE_OPTS = $previousGradleOpts
}
adb install -r build\app\outputs\flutter-apk\app-debug.apk
```

For a persistent fix on this laptop, ask the captain to replace the first line of
`android/gradle.properties` and add the three build controls below (keep its AndroidX
and Kotlin migration settings unchanged):

```properties
org.gradle.jvmargs=-Xmx2G -XX:MaxMetaspaceSize=768m -XX:ReservedCodeCacheSize=256m -XX:ActiveProcessorCount=2 -XX:+HeapDumpOnOutOfMemoryError
org.gradle.workers.max=1
org.gradle.parallel=false
org.gradle.daemon=false
```

The captured build log is temporary and is deleted after diagnosis; it is not committed.
The existing flutter_tts built-in-Kotlin compatibility message was a warning, not the
cause of this failure. Physical step/turn calibration still requires a phone walk.

## Optional raw sensors (t2/robust-sensing)

SensingSource.events() additionally broadcasts GravitySample, ProximitySample,
LightSample and DeviceInfo from lib/sensing/raw_events.dart. Navigation and record
consumers continue selecting StepEvent/TurnEvent; auxiliary events do not gate,
fuse or suppress detection. A malformed optional packet reports a decoding error
without poisoning the motion capability needed by startTrace.

Raw native/JSONL shapes (t is milliseconds since the stream started):

```json
{"type":"gravity","t":20,"x":0.0,"y":0.0,"z":9.8,"source":"sensor"}
{"type":"proximity","t":21,"near":true,"cm":0.0,"maximumRange":8.0,"origin":"sensor"}
{"type":"light","t":22,"lux":12.5}
{"type":"info","t":0,"totalRamMb":8192}
{"type":"info","gravityAvailable":false,"gravitySource":"accelerometer","gravityLowPassEnabled":true}
{"type":"info","proximityAvailable":false}
{"type":"info","lightAvailable":false}
```

Gravity vectors are m/s² in Android device axes and accompany each motion sample
at the gyro rate (requested about 50 Hz). TYPE_GRAVITY is preferred. Its failure
unregisters only that sensor and enables an accelerometer estimate. Proximity uses
the sensor's own maximumRange for its native near/far label, preserving raw cm;
there is no hardcoded near-distance threshold. Light is sent only when changed,
at most one delivery every 200 ms (5 Hz), even if the main thread was delayed.
Each optional missing/registration/data/delivery failure sends its false flag once
per stream session; gyro, accel and steps remain registered. Pause/cancel removes
all listeners and the single pending light flush. RAM uses ActivityManager's
physical totalMem / 1024² once per native stream session, not available memory.

Only these ADDITIVE tuning constants are new:

- gravityFallbackLowPassEnabled = true: only when native gravity is absent/failed.
- gravityFallbackLowPassAlpha = 0.8: previous-vector weight; valid range [0, 1).
- lightCoalescingEnabled = true: retain the latest intervening lux change.
  False drops intervening changes; both modes retain the mandatory 5 Hz cap.

SensingSource constructor overrides are for controlled experiments. Options travel
to Kotlin in the EventChannel listen arguments; Kotlin defines no new step/turn,
proximity-distance or lux thresholds. Legacy clients without options receive an
unfiltered accelerometer fallback. The selected options are saved in the trace's
meta.rawSensorFilters. Startup RAM/capability info is cached and written as one
info snapshot immediately after meta when tracing starts, so the one-time RAM
notice is not lost; subsequent raw packets are recorded without alteration.
The existing TraceRecorder already accepts raw JSON maps and needs no code change.

This checkout has only spike_walk_talha.jsonl; expected_turns.json and the later
labelled walks are absent. The spike regression verifies unchanged detected turn
angles/timestamps with auxiliary gravity samples interleaved; it is not a substitute
for retesting the absent labelled walks. No trace or expected label is invented.

## Separate D29 preparation: motion, bouts and placement

These pure-Dart classes are NOT wired into SensingSource.events(). Live phone
behavior and existing step/turn detectors remain unchanged, even though the new
standalone flags default true. Current contracts.dart contains no D29 types;
state_events.dart temporarily defines exactly MotionState {walking, still,
handling}, Placement {hand, pocket, unknown}, MotionStateEvent(state, tMs), and
PlacementEvent(placement, tMs). Replace that single type boundary with D29 exports
when the captain's types become available; no shared contract was edited here.

- WalkingBoutGate.onStep(StepEvent) returns zero or more original step objects.
  Three candidates with inclusive 250..1500 ms gaps confirm a bout and release its
  first three steps retroactively, with their original timestamps. Too-close
  samples do not advance the valid cadence baseline; unconfirmed isolated steps
  expire without being flushed. advanceTo(tMs) expires bout state; reset() clears
  it. useBoutGating=false forwards every valid hardware step immediately,
  including delayed timestamps, without applying a new cadence filter.
- MotionStateDetector.onGravity(GravitySample, inWalkingBout: ...) normalizes
  gravity vectors and compares them within a rolling 600 ms window. Exceeding
  35 degrees enters handling immediately, and each crossing refreshes a 1200 ms
  hold. The hold is NOT a 1200 ms delay before detecting a quick phone flip.
  Handling takes precedence over walking; walking requires the supplied bout
  state; otherwise still. Zero/non-finite vectors are ignored. Gravity-source
  changes and gaps over the existing maxMotionGapMs reset the observation window.
- PlacementDetector consumes the existing ProximitySample, LightSample and
  DeviceInfo classes. Continuous near AND lux <=10 for MORE than 2000 ms means
  pocket. Bright light or far proximity returns hand immediately. Missing inputs
  or explicit sensor-unavailable notices mean unknown, never an inferred pocket.
  On-change values persist until changed or unavailable. RAM notices have no
  effect. usePlacement=false emits no placement events and remains unknown.
- SensingGates is the future adapter: onRaw(existingRawEvent),
  onStep(hardwareStep), onMotion(tMs, yawRate, accel: optionalFallbackAccel), and
  advanceTo(tMs) return List<Object> containing StepEvent/TurnEvent plus local
  state-change events. Supply accel only for fallback mode, never alongside
  hardware steps. Process gravity before same-frame yaw, as native transport does.
  A clock pulse (or normal motion/gravity input) finishes holds, placement dwell and
  bout expiry without wall-clock timers or synthetic gyro samples.

useHandlingGate=true drops steps and skips both fallback-step and turn processing
while handling; it clears pending bouts and replaces detector state on entry and
exit. The first motion afterwards seeds a fresh timestamp, discarding any partial
heading integration instead of combining motion across the handling period.
useHandlingGate=false preserves step/turn processing even if the classifier reports
handling. Placement never gates counts or integration. The all-flags-off path is
unit-tested against today's detectors, including independent invalid accel/yaw
validation. No existing detector was modified.

ADDITIVE defaults only: handlingGravityDeg=35, handlingWindowMs=600,
handlingHoldMs=1200, boutMinSteps=3, boutMinGapMs=250, boutMaxGapMs=1500,
useBoutGating=true, useHandlingGate=true, usePlacement=true, pocketLuxMax=10,
pocketHoldMs=2000. No existing tuning value changed. All production files here
import only Dart libraries and the existing pure models; no Flutter or I/O imports.

## Proximity state and replay timing fix (11 Oct)

Investigation: the native comparison already used cm < sensor.maximumRange, and
its pair-based change check did not suppress a received far value. The proven
startup-state gaps were no explicit state at registration, a blanket timestamp
filter that could discard an old initial value, and no source proximity snapshot
when a trace starts later than the native stream. The one-near-record trace does
not prove why its final far callback was absent. Normal sampling delay was also
requested; proximity now requests FASTEST on-change delivery with zero batching.

After optional registration, an already-queued hardware value wins. Otherwise the
channel emits the last observed value, or the explicit maximum-range far reference
requested for sensors that supply no initial callback. Every proximity packet
contains cm, maximumRange and near=(cm<maximumRange). origin identifies sensor,
cached or assumed; an assumed far is not a claimed hardware measurement. The first
real callback is forced even if equal to that fallback. Subsequent cm/near changes,
including near->far, are emitted; old timestamps are retimed at receipt and marked
cached rather than dropping the value. Registration generation/paused/sink guards
cancel obsolete initial callbacks. Missing/failing proximity remains optional and
announces proximityAvailable:false once, without unregistering motion/steps.

ProximitySample keeps its original constructor and adds optional maximumRange,
origin and snapshot fields, so old traces and tests still parse unchanged. Source
records all new native fields unchanged. It caches valid proximity state, clears it
on an unavailable notice, and copies it after meta/device info at trace start with
snapshot:true and a capture-time t (not an old stream-start sample timestamp).
Known observations are labelled cached; an assumed origin remains assumed. Source
does not invent a far snapshot when no proximity observation is available.

trace_replay.dart adds pure-Dart TraceReplayData.parse(jsonl), fromRecords(...),
.timing (firstTimestampMs, lastTimestampMs, durationMs, durationSeconds) and .frames
(record, tMs, delayMs). Only timestamped sample/mark/sign/scan/turn records affect
timing. Info and meta remain in .records, but never start/end/reset/delay the replay
clock, even if their t is old, future or not numeric. Duration uses min/max valid
sample times, not row order. Delayed hardware samples have zero replay delay and do
not move the playback clock backwards. No file I/O, timers or Flutter imports.

There was no replay/duration module in lib/sensing before this change. The existing
Teammate 3 lib/app/screens/replay_screen.dart timing loop is outside this task's
allowed paths and was NOT edited; its owner can use TraceReplayData.parse(content)
.frames instead of updating prevT from info records. External trace inspection
scripts should likewise use .timing rather than every record's t.

Phone verification is still required. Compile/unit results do not establish that
the iQOO driver delivers the final far callback. Cover/uncover with marks, leave
time for the returned far before Stop, and inspect cm/maximumRange/near/origin.
