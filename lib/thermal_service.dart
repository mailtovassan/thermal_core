// lib/thermal_service.dart
import 'package:flutter/services.dart';

class ThermalZone {
  final String name;
  final double temp;
  final String zone;
  ThermalZone({required this.name, required this.temp, required this.zone});
}

class ThermalData {
  final double batteryTemp;
  final int batteryLevel;
  final bool isCharging;
  final int voltage;
  final String batteryHealth;
  final String plugType;
  final Map<String, double> hwTemps;
  final List<ThermalZone> thermalZones;
  final DateTime timestamp;
  final String deviceModel;
  final String androidVersion;

  ThermalData({
    required this.batteryTemp,
    required this.batteryLevel,
    required this.isCharging,
    required this.voltage,
    required this.batteryHealth,
    required this.plugType,
    required this.hwTemps,
    required this.thermalZones,
    required this.timestamp,
    required this.deviceModel,
    required this.androidVersion,
  });

  // Best available temperature reading
  double get primaryTemp {
    // Prefer skin temp if available (closest to surface feel)
    final skinKey = hwTemps.keys.firstWhere(
      (k) => k.contains('skin'), orElse: () => '');
    if (skinKey.isNotEmpty) return hwTemps[skinKey]!;

    // Then CPU temp average
    final cpuTemps = hwTemps.entries
        .where((e) => e.key.contains('cpu'))
        .map((e) => e.value)
        .toList();
    if (cpuTemps.isNotEmpty) {
      return cpuTemps.reduce((a, b) => a + b) / cpuTemps.length;
    }

    // Fallback: battery temp (always available)
    return batteryTemp > 0 ? batteryTemp : 0;
  }

  String get primaryTempSource {
    if (hwTemps.keys.any((k) => k.contains('skin'))) return 'Skin Sensor';
    if (hwTemps.keys.any((k) => k.contains('cpu'))) return 'CPU Sensor';
    return 'Battery Sensor';
  }

  ThermalState get thermalState {
    final t = primaryTemp;
    if (t <= 0) return ThermalState.unknown;
    if (t < 20) return ThermalState.cold;
    if (t < 30) return ThermalState.cool;
    if (t < 38) return ThermalState.normal;
    if (t < 43) return ThermalState.warm;
    if (t < 50) return ThermalState.hot;
    return ThermalState.critical;
  }

  factory ThermalData.fromMap(Map<dynamic, dynamic> map) {
    final hwRaw = map['hwTemps'] as Map? ?? {};
    final hwTemps = <String, double>{};
    hwRaw.forEach((k, v) => hwTemps[k.toString()] = (v as num).toDouble());

    final zonesRaw = map['thermalZones'] as Map? ?? {};
    final zones = <ThermalZone>[];
    zonesRaw.forEach((key, val) {
      if (val is Map) {
        final t = (val['temp'] as num?)?.toDouble() ?? 0;
        zones.add(ThermalZone(
          name: key.toString(),
          temp: t,
          zone: val['zone']?.toString() ?? '',
        ));
      }
    });
    zones.sort((a, b) => a.name.compareTo(b.name));

    return ThermalData(
      batteryTemp:    (map['batteryTemp'] as num?)?.toDouble() ?? -1,
      batteryLevel:   (map['batteryLevel'] as num?)?.toInt() ?? -1,
      isCharging:     map['isCharging'] as bool? ?? false,
      voltage:        (map['voltage'] as num?)?.toInt() ?? -1,
      batteryHealth:  map['batteryHealth']?.toString() ?? 'Unknown',
      plugType:       map['plugType']?.toString() ?? 'Unknown',
      hwTemps:        hwTemps,
      thermalZones:   zones,
      timestamp:      DateTime.fromMillisecondsSinceEpoch(
                        (map['timestamp'] as num?)?.toInt() ?? 0),
      deviceModel:    map['deviceModel']?.toString() ?? 'Unknown',
      androidVersion: map['androidVersion']?.toString() ?? 'Unknown',
    );
  }
}

enum ThermalState { unknown, cold, cool, normal, warm, hot, critical }

class ThermalService {
  static const _methodChannel = MethodChannel('com.byteronz.thermalcore/thermal');
  static const _eventChannel  = EventChannel('com.byteronz.thermalcore/thermal_stream');

  Stream<ThermalData> get stream => _eventChannel
      .receiveBroadcastStream()
      .where((e) => e != null)
      .map((e) => ThermalData.fromMap(e as Map));

  Future<ThermalData?> fetchOnce() async {
    try {
      final result = await _methodChannel.invokeMethod('getThermalData');
      return ThermalData.fromMap(result as Map);
    } catch (e) {
      return null;
    }
  }
}
