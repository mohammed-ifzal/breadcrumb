package com.teamgroza.breadcrumb

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var sensing: SensingChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        sensing = SensingChannel(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onPause() {
        sensing?.pause()
        super.onPause()
    }

    override fun onResume() {
        super.onResume()
        sensing?.resume()
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        sensing?.dispose()
        sensing = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
