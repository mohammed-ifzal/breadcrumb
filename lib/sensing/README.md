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
