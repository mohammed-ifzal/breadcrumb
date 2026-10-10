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
{"type":"proximity","t":21,"near":true,"cm":0.0}
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
