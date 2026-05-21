// lib/main.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'thermal_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF060810),
  ));
  runApp(const ThermalCoreApp());
}

// ─── Colour scheme ─────────────────────────────────────────────────────
class TColors {
  static const bg       = Color(0xFF060810);
  static const panel    = Color(0xFF0D1120);
  static const border   = Color(0xFF1A2035);
  static const cold     = Color(0xFF00D4FF);
  static const cool     = Color(0xFF00FF9D);
  static const normal   = Color(0xFF80FF00);
  static const warm     = Color(0xFFFFB800);
  static const hot      = Color(0xFFFF6B35);
  static const critical = Color(0xFFFF1744);
  static const text     = Color(0xFFE8EAF0);
  static const muted    = Color(0xFF5A6070);

  static Color forState(ThermalState s) => switch (s) {
    ThermalState.cold     => cold,
    ThermalState.cool     => cool,
    ThermalState.normal   => normal,
    ThermalState.warm     => warm,
    ThermalState.hot      => hot,
    ThermalState.critical => critical,
    ThermalState.unknown  => muted,
  };

  static Color forTemp(double t) {
    if (t < 20) return cold;
    if (t < 30) return cool;
    if (t < 38) return normal;
    if (t < 43) return warm;
    if (t < 50) return hot;
    return critical;
  }

  static String labelForState(ThermalState s) => switch (s) {
    ThermalState.cold     => 'COLD',
    ThermalState.cool     => 'COOL',
    ThermalState.normal   => 'NORMAL',
    ThermalState.warm     => 'WARM',
    ThermalState.hot      => 'HOT',
    ThermalState.critical => 'CRITICAL',
    ThermalState.unknown  => 'SCANNING',
  };
}

// ─── Root ───────────────────────────────────────────────────────────────
class ThermalCoreApp extends StatelessWidget {
  const ThermalCoreApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'ThermalCore',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: TColors.bg,
      colorScheme: const ColorScheme.dark(primary: TColors.cold),
    ),
    home: const HomePage(),
  );
}

// ─── Home Page ──────────────────────────────────────────────────────────
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  final _service = ThermalService();
  ThermalData? _data;
  StreamSubscription? _sub;
  final List<double> _history = [];
  static const _maxHistory = 60;

  late AnimationController _pulseCtrl;
  late AnimationController _ringCtrl;
  late Animation<double> _ringAnim;
  double _ringTarget = 0;

  int _currentTab = 0;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _ringCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1500));
    _ringAnim = Tween(begin: 0.0, end: 0.0).animate(
      CurvedAnimation(parent: _ringCtrl, curve: Curves.easeInOutCubic));

    _sub = _service.stream.listen(_onData);
    _service.fetchOnce().then((d) { if (d != null) _onData(d); });
  }

  void _onData(ThermalData d) {
    if (!mounted) return;
    setState(() { _data = d; });
    _history.add(d.primaryTemp);
    if (_history.length > _maxHistory) _history.removeAt(0);

    // animate ring
    final pct = ((d.primaryTemp - 15) / 45).clamp(0.0, 1.0);
    final tween = Tween(begin: _ringTarget, end: pct);
    _ringAnim = tween.animate(
      CurvedAnimation(parent: _ringCtrl, curve: Curves.easeInOutCubic));
    _ringTarget = pct;
    _ringCtrl.forward(from: 0);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _pulseCtrl.dispose();
    _ringCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = _data?.thermalState ?? ThermalState.unknown;
    final color = TColors.forState(state);

    return Scaffold(
      backgroundColor: TColors.bg,
      body: SafeArea(
        child: Column(children: [
          _buildHeader(color),
          if (_data?.thermalState == ThermalState.hot ||
              _data?.thermalState == ThermalState.critical)
            _buildWarningBanner(state),
          Expanded(child: _buildTabContent()),
          _buildTabBar(color),
        ]),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────
  Widget _buildHeader(Color color) => Container(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: TColors.border)),
    ),
    child: Row(children: [
      Text('THERMAL', style: GoogleFonts.orbitron(
        fontSize: 18, fontWeight: FontWeight.w900,
        letterSpacing: 3, color: TColors.cold)),
      Text('CORE', style: GoogleFonts.orbitron(
        fontSize: 18, fontWeight: FontWeight.w900,
        letterSpacing: 3, color: TColors.cold.withOpacity(0.4))),
      const Spacer(),
      AnimatedBuilder(
        animation: _pulseCtrl,
        builder: (_, __) => Row(children: [
          Text('LIVE ', style: GoogleFonts.jetBrainsMono(
            fontSize: 10, letterSpacing: 2, color: TColors.muted)),
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _data != null ? TColors.cool : TColors.muted,
              boxShadow: _data != null ? [BoxShadow(
                color: TColors.cool.withOpacity(0.4 + _pulseCtrl.value * 0.4),
                blurRadius: 8)] : null),
          ),
        ]),
      ),
    ]),
  );

  // ── Warning Banner ──────────────────────────────────────────────────
  Widget _buildWarningBanner(ThermalState state) => AnimatedContainer(
    duration: const Duration(milliseconds: 400),
    margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: TColors.hot.withOpacity(0.08),
      border: Border.all(color: TColors.hot.withOpacity(0.4)),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(children: [
      Text(state == ThermalState.critical ? '🚨' : '⚠️',
        style: const TextStyle(fontSize: 16)),
      const SizedBox(width: 10),
      Expanded(child: Text(
        state == ThermalState.critical
          ? 'Critical temperature! Stop charging and close all apps.'
          : 'Device running hot. Close background apps.',
        style: GoogleFonts.jetBrainsMono(
          fontSize: 11, color: TColors.hot, height: 1.5),
      )),
    ]),
  );

  // ── Tab Content ─────────────────────────────────────────────────────
  Widget _buildTabContent() => IndexedStack(
    index: _currentTab,
    children: [
      _DashboardTab(data: _data, history: _history, ringAnim: _ringAnim),
      _ZonesTab(data: _data),
      _InfoTab(data: _data),
    ],
  );

  // ── Bottom Tab Bar ──────────────────────────────────────────────────
  Widget _buildTabBar(Color color) => Container(
    decoration: BoxDecoration(
      color: TColors.panel,
      border: Border(top: BorderSide(color: TColors.border)),
    ),
    child: Row(children: [
      _TabItem(icon: Icons.thermostat, label: 'Dashboard',
        active: _currentTab == 0, color: color,
        onTap: () => setState(() => _currentTab = 0)),
      _TabItem(icon: Icons.memory, label: 'Zones',
        active: _currentTab == 1, color: color,
        onTap: () => setState(() => _currentTab = 1)),
      _TabItem(icon: Icons.info_outline, label: 'Info',
        active: _currentTab == 2, color: color,
        onTap: () => setState(() => _currentTab = 2)),
    ]),
  );
}

class _TabItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final Color color;
  final VoidCallback onTap;
  const _TabItem({required this.icon, required this.label,
    required this.active, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => Expanded(child: InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: active ? color : TColors.muted, size: 20),
        const SizedBox(height: 4),
        Text(label, style: GoogleFonts.jetBrainsMono(
          fontSize: 9, letterSpacing: 1,
          color: active ? color : TColors.muted,
          fontWeight: active ? FontWeight.w600 : FontWeight.normal)),
      ]),
    ),
  ));
}

// ══════════════════════════════════════════════════════════════════════
// TAB 1 — Dashboard
// ══════════════════════════════════════════════════════════════════════
class _DashboardTab extends StatelessWidget {
  final ThermalData? data;
  final List<double> history;
  final Animation<double> ringAnim;
  const _DashboardTab({this.data, required this.history, required this.ringAnim});

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      _buildTempHero(),
      const SizedBox(height: 16),
      _buildMetricsRow(),
      const SizedBox(height: 16),
      _buildHistoryChart(),
      const SizedBox(height: 16),
      _buildBatteryCard(),
    ],
  );

  // ── Temp Hero with animated ring ─────────────────────────────────────
  Widget _buildTempHero() {
    final state  = data?.thermalState ?? ThermalState.unknown;
    final color  = TColors.forState(state);
    final label  = TColors.labelForState(state);
    final temp   = data?.primaryTemp ?? 0;
    final source = data?.primaryTempSource ?? '---';

    return Center(child: SizedBox(
      width: 220, height: 260,
      child: Stack(alignment: Alignment.center, children: [

        // Animated ring
        AnimatedBuilder(
          animation: ringAnim,
          builder: (_, __) => CustomPaint(
            size: const Size(220, 220),
            painter: _RingPainter(progress: ringAnim.value, color: color),
          ),
        ),

        // Inner content
        Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            temp > 0 ? temp.toStringAsFixed(1) : '--.-',
            style: GoogleFonts.orbitron(
              fontSize: 52, fontWeight: FontWeight.w900,
              color: color, letterSpacing: -2,
              shadows: [Shadow(color: color.withOpacity(0.5), blurRadius: 20)]),
          ),
          Text('°C', style: GoogleFonts.orbitron(
            fontSize: 18, color: TColors.muted, letterSpacing: 1)),
          const SizedBox(height: 4),
          Text(source, style: GoogleFonts.jetBrainsMono(
            fontSize: 10, letterSpacing: 2, color: TColors.muted)),
        ]),

        // State label at bottom of ring
        Positioned(
          bottom: 30,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            decoration: BoxDecoration(
              border: Border.all(color: color.withOpacity(0.6)),
              borderRadius: BorderRadius.circular(30),
              boxShadow: [BoxShadow(color: color.withOpacity(0.2), blurRadius: 16)],
            ),
            child: Text(label, style: GoogleFonts.orbitron(
              fontSize: 12, fontWeight: FontWeight.w700,
              color: color, letterSpacing: 4)),
          ),
        ),
      ]),
    ));
  }

  // ── Metrics row ──────────────────────────────────────────────────────
  Widget _buildMetricsRow() => Row(children: [
    Expanded(child: _MetricCard(
      label: 'Battery',
      value: data != null ? '${data!.batteryLevel}%' : '--%',
      sub: data?.isCharging == true ? '⚡ ${data!.plugType}' : 'Discharging',
      color: _batteryColor(),
      progress: (data?.batteryLevel ?? 0) / 100,
    )),
    const SizedBox(width: 12),
    Expanded(child: _MetricCard(
      label: 'Voltage',
      value: data?.voltage != null && data!.voltage > 0
          ? '${(data!.voltage / 1000.0).toStringAsFixed(2)}V' : '--V',
      sub: 'Battery voltage',
      color: TColors.cold,
      progress: data?.voltage != null && data!.voltage > 0
          ? ((data!.voltage - 3000) / 1200).clamp(0.0, 1.0) : 0,
    )),
  ]);

  Color _batteryColor() {
    final l = data?.batteryLevel ?? 50;
    if (l > 50) return TColors.cool;
    if (l > 20) return TColors.warm;
    return TColors.critical;
  }

  // ── History chart ────────────────────────────────────────────────────
  Widget _buildHistoryChart() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: TColors.panel,
      border: Border.all(color: TColors.border),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('TEMPERATURE HISTORY', style: GoogleFonts.jetBrainsMono(
          fontSize: 9, letterSpacing: 2.5, color: TColors.muted)),
        const Spacer(),
        Text('last ${history.length}s', style: GoogleFonts.jetBrainsMono(
          fontSize: 10, color: TColors.muted)),
      ]),
      const SizedBox(height: 16),
      SizedBox(
        height: 80,
        child: history.length < 2
          ? Center(child: Text('Collecting data...',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11, color: TColors.muted)))
          : _buildLineChart(),
      ),
    ]),
  );

  Widget _buildLineChart() {
    final minY = (history.reduce(min) - 2).floorToDouble();
    final maxY = (history.reduce(max) + 2).ceilToDouble();
    final lastTemp = history.last;
    final lineColor = TColors.forTemp(lastTemp);

    final spots = history.asMap().entries
        .map((e) => FlSpot(e.key.toDouble(), e.value))
        .toList();

    return LineChart(LineChartData(
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        getDrawingHorizontalLine: (_) => FlLine(
          color: TColors.border, strokeWidth: 1),
      ),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(sideTitles: SideTitles(
          showTitles: true, reservedSize: 32,
          getTitlesWidget: (v, _) => Text('${v.toInt()}°',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 8, color: TColors.muted)))),
        bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      borderData: FlBorderData(show: false),
      minX: 0, maxX: (_maxHistory - 1).toDouble(),
      minY: minY, maxY: maxY,
      lineBarsData: [LineChartBarData(
        spots: spots,
        isCurved: true,
        color: lineColor,
        barWidth: 2,
        dotData: FlDotData(show: false),
        belowBarData: BarAreaData(
          show: true,
          color: lineColor.withOpacity(0.08),
        ),
      )],
    ));
  }

  // ── Battery card ─────────────────────────────────────────────────────
  Widget _buildBatteryCard() {
    if (data == null) return const SizedBox.shrink();
    final battColor = data!.batteryTemp > 40 ? TColors.hot
        : data!.batteryTemp > 35 ? TColors.warm : TColors.cool;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TColors.panel,
        border: Border.all(color: TColors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('BATTERY THERMAL', style: GoogleFonts.jetBrainsMono(
          fontSize: 9, letterSpacing: 2.5, color: TColors.muted)),
        const SizedBox(height: 12),
        Row(children: [
          Icon(Icons.battery_charging_full, color: battColor, size: 32),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              data!.batteryTemp > 0
                ? '${data!.batteryTemp.toStringAsFixed(1)} °C'
                : '-- °C',
              style: GoogleFonts.orbitron(
                fontSize: 28, fontWeight: FontWeight.w700, color: battColor,
                shadows: [Shadow(color: battColor.withOpacity(0.4), blurRadius: 12)]),
            ),
            Text('Direct battery sensor reading',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 10, color: TColors.muted)),
          ]),
          const Spacer(),
          _InfoBadge(label: data!.batteryHealth, color: battColor),
        ]),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// TAB 2 — Thermal Zones
// ══════════════════════════════════════════════════════════════════════
class _ZonesTab extends StatelessWidget {
  final ThermalData? data;
  const _ZonesTab({this.data});

  @override
  Widget build(BuildContext context) {
    final zones = data?.thermalZones ?? [];
    final hwTemps = data?.hwTemps ?? {};

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (hwTemps.isNotEmpty) ...[
          _SectionHeader(label: 'HARDWARE SENSORS (${hwTemps.length})'),
          const SizedBox(height: 8),
          ...hwTemps.entries.map((e) => _ZoneRow(
            name: e.key.replaceAll('_', ' ').toUpperCase(),
            temp: e.value,
            badge: _hwBadge(e.key),
          )),
          const SizedBox(height: 16),
        ],
        _SectionHeader(label: 'THERMAL ZONES (${zones.length})'),
        const SizedBox(height: 8),
        if (zones.isEmpty)
          _EmptyState(message: 'No thermal zones accessible.\nSome Samsung devices restrict sysfs access.')
        else
          ...zones.map((z) => _ZoneRow(
            name: z.name.replaceAll('-', ' ').toUpperCase(),
            temp: z.temp,
            badge: z.zone,
          )),
      ],
    );
  }

  String _hwBadge(String key) {
    if (key.contains('skin')) return 'SKIN';
    if (key.contains('cpu')) return 'CPU';
    if (key.contains('gpu')) return 'GPU';
    return 'HW';
  }
}

class _ZoneRow extends StatelessWidget {
  final String name;
  final double temp;
  final String badge;
  const _ZoneRow({required this.name, required this.temp, required this.badge});

  @override
  Widget build(BuildContext context) {
    final color = TColors.forTemp(temp);
    final pct = ((temp - 15) / 45).clamp(0.0, 1.0);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: TColors.panel,
        border: Border.all(color: TColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(children: [
        Row(children: [
          Expanded(child: Text(name,
            style: GoogleFonts.jetBrainsMono(fontSize: 11, color: TColors.text),
            overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 8),
          _InfoBadge(label: badge, color: TColors.muted),
          const SizedBox(width: 8),
          Text('${temp.toStringAsFixed(1)}°C',
            style: GoogleFonts.orbitron(
              fontSize: 16, fontWeight: FontWeight.w700, color: color)),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: pct,
            backgroundColor: TColors.border,
            valueColor: AlwaysStoppedAnimation(color),
            minHeight: 3,
          ),
        ),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// TAB 3 — Device Info
// ══════════════════════════════════════════════════════════════════════
class _InfoTab extends StatelessWidget {
  final ThermalData? data;
  const _InfoTab({this.data});

  @override
  Widget build(BuildContext context) {
    final hwCount = data?.hwTemps.length ?? 0;
    final zoneCount = data?.thermalZones.length ?? 0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionHeader(label: 'DEVICE'),
        const SizedBox(height: 8),
        _InfoCard(rows: [
          ('Model',    data?.deviceModel ?? '---'),
          ('Android',  data?.androidVersion != null ? 'Android ${data!.androidVersion}' : '---'),
          ('HW Sensors', '$hwCount available'),
          ('Thermal Zones', '$zoneCount readable'),
        ]),
        const SizedBox(height: 16),
        _SectionHeader(label: 'DATA SOURCES'),
        const SizedBox(height: 8),
        _InfoCard(rows: [
          ('Battery Temp',  data?.batteryTemp != null && data!.batteryTemp > 0
              ? '✓ ${data!.batteryTemp.toStringAsFixed(1)}°C' : '✓ Available'),
          ('HW Props API',  hwCount > 0 ? '✓ $hwCount readings' : '⚠ Restricted'),
          ('Sysfs Zones',   zoneCount > 0 ? '✓ $zoneCount zones' : '⚠ Restricted'),
          ('Primary Source', data?.primaryTempSource ?? '---'),
        ]),
        const SizedBox(height: 16),
        _SectionHeader(label: 'ABOUT'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: TColors.panel,
            border: Border.all(color: TColors.border),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            'ThermalCore reads real hardware temperatures via:\n\n'
            '• Intent.ACTION_BATTERY_CHANGED → real battery °C\n'
            '• HardwarePropertiesManager → CPU/GPU/Skin sensors\n'
            '• /sys/class/thermal/thermal_zone* → SoC zones\n\n'
            'Samsung S24 FE battery sensor typically reports\n'
            'accurate temperature within ±1°C of actual battery.\n\n'
            'Built by Byteronz',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 11, color: TColors.muted, height: 1.7),
          ),
        ),
      ],
    );
  }
}

// ─── Shared Widgets ──────────────────────────────────────────────────
class _MetricCard extends StatelessWidget {
  final String label, value, sub;
  final Color color;
  final double progress;
  const _MetricCard({required this.label, required this.value,
    required this.sub, required this.color, required this.progress});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: TColors.panel,
      border: Border.all(color: TColors.border),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: GoogleFonts.jetBrainsMono(
        fontSize: 9, letterSpacing: 2.5, color: TColors.muted)),
      const SizedBox(height: 8),
      Text(value, style: GoogleFonts.orbitron(
        fontSize: 22, fontWeight: FontWeight.w700, color: color)),
      const SizedBox(height: 4),
      Text(sub, style: GoogleFonts.jetBrainsMono(
        fontSize: 10, color: TColors.muted)),
      const SizedBox(height: 8),
      ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: LinearProgressIndicator(
          value: progress.clamp(0.0, 1.0),
          backgroundColor: TColors.border,
          valueColor: AlwaysStoppedAnimation(color),
          minHeight: 3,
        ),
      ),
    ]),
  );
}

class _InfoBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _InfoBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      border: Border.all(color: color.withOpacity(0.4)),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(label, style: GoogleFonts.jetBrainsMono(
      fontSize: 9, letterSpacing: 1, color: color)),
  );
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) => Row(children: [
    Text(label, style: GoogleFonts.jetBrainsMono(
      fontSize: 9, letterSpacing: 2.5, color: TColors.muted)),
    const SizedBox(width: 8),
    Expanded(child: Divider(color: TColors.border, height: 1)),
  ]);
}

class _InfoCard extends StatelessWidget {
  final List<(String, String)> rows;
  const _InfoCard({required this.rows});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: TColors.panel,
      border: Border.all(color: TColors.border),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(children: rows.asMap().entries.map((e) {
      final isLast = e.key == rows.length - 1;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: isLast ? null : Border(
            bottom: BorderSide(color: TColors.border))),
        child: Row(children: [
          Text(e.value.$1, style: GoogleFonts.jetBrainsMono(
            fontSize: 12, color: TColors.muted)),
          const Spacer(),
          Text(e.value.$2, style: GoogleFonts.jetBrainsMono(
            fontSize: 12, color: TColors.text, fontWeight: FontWeight.w600)),
        ]),
      );
    }).toList()),
  );
}

class _EmptyState extends StatelessWidget {
  final String message;
  const _EmptyState({required this.message});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: TColors.panel,
      border: Border.all(color: TColors.border),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Center(child: Text(message,
      textAlign: TextAlign.center,
      style: GoogleFonts.jetBrainsMono(
        fontSize: 12, color: TColors.muted, height: 1.7))),
  );
}

// ─── Custom ring painter ─────────────────────────────────────────────
class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  const _RingPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 14;
    const startAngle = -pi / 2;
    const fullSweep = 2 * pi;

    // Track
    canvas.drawCircle(center, radius, Paint()
      ..color = TColors.border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8);

    // Progress arc
    if (progress > 0) {
      final sweepAngle = fullSweep * progress;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle, sweepAngle, false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8
          ..strokeCap = StrokeCap.round
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4),
      );
      // Solid on top of glow
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle, sweepAngle, false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color;
}

const _maxHistory = 60;
