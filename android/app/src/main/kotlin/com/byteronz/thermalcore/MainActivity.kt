package com.byteronz.thermalcore

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
import android.os.HardwarePropertiesManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {

    companion object {
        const val METHOD_CHANNEL = "com.byteronz.thermalcore/thermal"
        const val EVENT_CHANNEL  = "com.byteronz.thermalcore/thermal_stream"
    }

    private var eventSink: EventChannel.EventSink? = null
    private var batteryReceiver: BroadcastReceiver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── Method Channel: one-shot reads ──────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getThermalData" -> result.success(buildThermalMap())
                    "getThermalZones" -> result.success(readThermalZones())
                    else -> result.notImplemented()
                }
            }

        // ── Event Channel: live stream every ~3 s via battery broadcast ─
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
                    eventSink = sink
                    registerBatteryReceiver(sink)
                }
                override fun onCancel(arguments: Any?) {
                    unregisterBatteryReceiver()
                    eventSink = null
                }
            })
    }

    // ── Battery broadcast receiver ──────────────────────────────────────
    private fun registerBatteryReceiver(sink: EventChannel.EventSink) {
        batteryReceiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context, intent: Intent) {
                sink.success(buildThermalMap(intent))
            }
        }
        val filter = IntentFilter(Intent.ACTION_BATTERY_CHANGED)
        registerReceiver(batteryReceiver, filter)
        // Send an immediate reading
        val sticky = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        sticky?.let { sink.success(buildThermalMap(it)) }
    }

    private fun unregisterBatteryReceiver() {
        try { batteryReceiver?.let { unregisterReceiver(it) } } catch (_: Exception) {}
        batteryReceiver = null
    }

    // ── Build the full thermal data map ────────────────────────────────
    private fun buildThermalMap(intent: Intent? = null): Map<String, Any> {
        val bm = getSystemService(BATTERY_SERVICE) as BatteryManager

        // 1. Battery temperature (tenths of °C → real °C)
        val battTempRaw = if (intent != null) {
            intent.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, -1)
        } else {
            val stickyIntent = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
            stickyIntent?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, -1) ?: -1
        }
        val battTempC = if (battTempRaw > 0) battTempRaw / 10.0 else -1.0

        // 2. Battery level
        val level = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
        val charging = bm.isCharging

        // 3. Voltage (mV)
        val voltage = intent?.getIntExtra(BatteryManager.EXTRA_VOLTAGE, -1) ?: -1

        // 4. Battery health
        val healthCode = intent?.getIntExtra(BatteryManager.EXTRA_HEALTH,
            BatteryManager.BATTERY_HEALTH_UNKNOWN) ?: BatteryManager.BATTERY_HEALTH_UNKNOWN
        val health = when (healthCode) {
            BatteryManager.BATTERY_HEALTH_GOOD -> "Good"
            BatteryManager.BATTERY_HEALTH_OVERHEAT -> "Overheat"
            BatteryManager.BATTERY_HEALTH_DEAD -> "Dead"
            BatteryManager.BATTERY_HEALTH_OVER_VOLTAGE -> "Over Voltage"
            BatteryManager.BATTERY_HEALTH_COLD -> "Cold"
            else -> "Unknown"
        }

        // 5. Charge plug type
        val plugType = when (intent?.getIntExtra(BatteryManager.EXTRA_PLUGGED, -1)) {
            BatteryManager.BATTERY_PLUGGED_AC -> "AC"
            BatteryManager.BATTERY_PLUGGED_USB -> "USB"
            BatteryManager.BATTERY_PLUGGED_WIRELESS -> "Wireless"
            else -> "Unplugged"
        }

        // 6. HardwarePropertiesManager temps (Android 7.1+, best-effort)
        val hwTemps = mutableMapOf<String, Double>()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            try {
                val hpm = getSystemService(HARDWARE_PROPERTIES_SERVICE) as HardwarePropertiesManager
                val cpuTemps = hpm.getDeviceTemperatures(
                    HardwarePropertiesManager.DEVICE_TEMPERATURE_CPU,
                    HardwarePropertiesManager.TEMPERATURE_CURRENT
                )
                cpuTemps.forEachIndexed { i, t ->
                    if (!t.isNaN() && t > 0) hwTemps["cpu_core_$i"] = t.toDouble()
                }
                val gpuTemps = hpm.getDeviceTemperatures(
                    HardwarePropertiesManager.DEVICE_TEMPERATURE_GPU,
                    HardwarePropertiesManager.TEMPERATURE_CURRENT
                )
                gpuTemps.forEachIndexed { i, t ->
                    if (!t.isNaN() && t > 0) hwTemps["gpu_$i"] = t.toDouble()
                }
                val skinTemps = hpm.getDeviceTemperatures(
                    HardwarePropertiesManager.DEVICE_TEMPERATURE_SKIN,
                    HardwarePropertiesManager.TEMPERATURE_CURRENT
                )
                skinTemps.forEachIndexed { i, t ->
                    if (!t.isNaN() && t > 0) hwTemps["skin_$i"] = t.toDouble()
                }
            } catch (_: Exception) {}
        }

        // 7. Thermal zones from sysfs
        val thermalZones = readThermalZones()

        return mapOf(
            "batteryTemp"   to battTempC,
            "batteryLevel"  to level,
            "isCharging"    to charging,
            "voltage"       to voltage,
            "batteryHealth" to health,
            "plugType"      to plugType,
            "hwTemps"       to hwTemps,
            "thermalZones"  to thermalZones,
            "timestamp"     to System.currentTimeMillis(),
            "deviceModel"   to "${Build.MANUFACTURER} ${Build.MODEL}",
            "androidVersion" to Build.VERSION.RELEASE
        )
    }

    // ── Read /sys/class/thermal/thermal_zone* ──────────────────────────
    private fun readThermalZones(): Map<String, Any> {
        val result = mutableMapOf<String, Any>()
        try {
            val thermalDir = File("/sys/class/thermal")
            if (!thermalDir.exists()) return result

            thermalDir.listFiles { f -> f.name.startsWith("thermal_zone") }
                ?.sortedBy { it.name.removePrefix("thermal_zone").toIntOrNull() ?: 999 }
                ?.take(20) // cap at 20 zones
                ?.forEach { zone ->
                    try {
                        val tempFile = File(zone, "temp")
                        val typeFile = File(zone, "type")
                        if (!tempFile.exists()) return@forEach

                        val rawTemp = tempFile.readText().trim().toLongOrNull() ?: return@forEach
                        val type    = if (typeFile.exists()) typeFile.readText().trim() else zone.name

                        // Samsung reports in millidegrees (>1000) or centidegrees (100–999)
                        val tempC = when {
                            rawTemp > 10000 -> rawTemp / 1000.0  // millidegrees
                            rawTemp > 1000  -> rawTemp / 100.0   // centidegrees
                            rawTemp > 200   -> rawTemp / 10.0    // tenths
                            else            -> rawTemp.toDouble() // already °C
                        }

                        if (tempC in 0.0..150.0) {
                            result[type] = mapOf("temp" to tempC, "zone" to zone.name)
                        }
                    } catch (_: Exception) {}
                }
        } catch (_: Exception) {}
        return result
    }

    override fun onDestroy() {
        super.onDestroy()
        unregisterBatteryReceiver()
    }
}
