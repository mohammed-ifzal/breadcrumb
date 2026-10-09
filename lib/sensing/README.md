# Teammate 2 sensing spike

Kotlin registers one `breadcrumb/sensing` EventChannel in MainActivity. Gravity and
acceleration are sampled alongside the gyroscope; each gyro callback emits the latest
acceleration magnitude and gyro projected onto unit gravity, converted to degrees per
second. The sampling period requests 50 Hz; device delivery may vary. Kotlin performs
no step/turn detection. Subscription cancellation and activity pause unregister all
listeners. Missing sensors and denied permissions are reported as stream errors.

`StepDetector.onMotion(t, accel)` detects a local peak on its descending sample, using
the first timestamp of a plateau and tuning's peak threshold/minimum gap. It is enabled
only after Kotlin reports that hardware step detection is absent. `TurnDetector`
integrates each qualifying sample over the preceding timestamp interval, waits for a
continuous settling period, then emits the entire angle. The first motion sample sets
the time origin; duplicate/out-of-order and non-finite samples are ignored. Thresholds
come exclusively from `lib/core/tuning.dart`.

`SensingSource` implements the core interface. Subscribe through `events()`; consumers
share one native subscription. `hardwareStepDetector` is a ValueNotifier: unknown
before the first notice/sample, then yes/no. A permission error never enables fallback.
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
overwrite earlier files. Recording outside an active trace is a no-op.

`SensingDebugScreen` is a standalone screen showing detector capability, step count,
last turn and a note/Mark button. It starts a `sensing_spike` trace automatically and
owns/disposes its source, including one injected for testing. This screen never requests
permissions. Teammate 3 must wire it into the app after external permission grant:

```text
adb shell pm grant com.teamgroza.breadcrumb android.permission.ACTIVITY_RECOGNITION
```

This spike supports D15's real live recording. It does not implement MapBuilder or
record_screen.dart, draw a fabricated trail, or require signs. No contract/tuning or
shared build changes are needed. Test with `flutter test --concurrency=1` if parallel
Flutter test compilation exhausts memory on the laptop.
