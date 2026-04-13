import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

void main() {
  runApp(const SensorMonitorApp());
}

class SensorMonitorApp extends StatelessWidget {
  const SensorMonitorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sensor Monitor',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0D12),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00FF88),
          surface: Color(0xFF111820),
        ),
      ),
      home: const SplashScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

enum SensorState { allClear, sensor1Triggered, sensor2Triggered, bothTriggered }

class SensorDashboard extends StatefulWidget {
  final String espIp;
  final String stationName;
  const SensorDashboard({super.key, required this.espIp, required this.stationName});

  @override
  State<SensorDashboard> createState() => _SensorDashboardState();
}

class _SensorDashboardState extends State<SensorDashboard>
    with TickerProviderStateMixin {
  SensorState _state = SensorState.allClear;
  bool _s1 = false;
  bool _s2 = false;
  bool _connected = false;
  bool _sleeping = false;

  Timer? _pollTimer;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  Future<void> _sendSleep() async {
    try {
      setState(() => _sleeping = true); // Update UI immediately
      await http.get(Uri.parse('http://${widget.espIp}/sleep'))
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      // If it fails, the station might already be unreachable
    }
  }

  Future<void> _sendWake() async {
    try {
      await http.get(Uri.parse('http://${widget.espIp}/wake'))
          .timeout(const Duration(seconds: 2));
      setState(() => _sleeping = false); // Update UI to show monitoring is active
    } catch (_) {
      // If wake fails, the poll timer will eventually show "Disconnected"
    }
  }

  @override
  void initState() {
    super.initState();
    
    // 1. Setup Animations
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // 2. WAKE the station immediately
    _sendWake();

    // 3. Start Polling for status
    _pollTimer = Timer.periodic(const Duration(milliseconds: 200), (_) async {
      if (_sleeping) return; // Don't poll if we manually put it to sleep
      
      try {
        final response = await http.get(
          Uri.parse('http://${widget.espIp}/status'),
        ).timeout(const Duration(seconds: 2));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          _updateState(data['s1'], data['s2']);
          if (!_connected) setState(() => _connected = true);
        }
      } catch (e) {
        if (_connected) {
          setState(() {
            _connected = false;
            _state = SensorState.allClear;
          });
        }
      }
    });
  }

  void _updateState(bool s1, bool s2) {
  setState(() {
    _s1 = s1;
    _s2 = s2;
    if (s1 && s2) {
      _state = SensorState.bothTriggered;
    } else if (s1) {
      _state = SensorState.sensor1Triggered;
    } else if (s2) {
      _state = SensorState.sensor2Triggered;
    } else {
      _state = SensorState.allClear;
    }
  });
  }

  @override
  void dispose() {
    // Tell the ESP32 to turn off lights before we destroy this screen
    _sendSleep(); 
    
    _pollTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  Color _ledColor(int index) {
    if (_sleeping) return const Color(0xFF0A0D12); // amber-dim
    final bool isLeft = index < 12;
    switch (_state) {
      case SensorState.allClear:
        // ring goes dark grey when disconnected
        return _connected ? const Color(0xFF00CC55) : const Color(0xFF1A2530);
      case SensorState.bothTriggered:
        return const Color(0xFFDD1111);
      case SensorState.sensor1Triggered:
        return isLeft ? const Color(0xFF00CC55) : const Color(0xFFDD1111);
      case SensorState.sensor2Triggered:
        return isLeft ? const Color(0xFFDD1111) : const Color(0xFF00CC55);
    }
  }

  String get _statusLabel {
    if (_sleeping) return 'STATION STANDBY / LIGHTS OFF';
    if (!_connected) return 'SEARCHING for STATION...';
    switch (_state) {
      case SensorState.allClear:
        return 'ALL CLEAR';
      case SensorState.sensor1Triggered:
        return 'SENSOR 1 — BLOCKED';
      case SensorState.sensor2Triggered:
        return 'SENSOR 2 — BLOCKED';
      case SensorState.bothTriggered:
        return 'BOTH SENSORS — BLOCKED';
    }
  }

  Color get _statusColor {
    if (_sleeping) return const Color(0xFF2A3540);
    if (!_connected) return const Color(0xFF445566);
    return _state == SensorState.allClear
        ? const Color(0xFF00FF88)
        : const Color(0xFFFF3333);
  }

  @override
  Widget build(BuildContext context) {

    final bool isOutOfRange = !_connected && !_sleeping;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0D12),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Color(0xFF00FF88)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.stationName,
          style: const TextStyle(
            fontFamily: 'FrankRuhlLibre',
            fontSize: 20,
            color: Color.fromARGB(255, 217, 221, 225),
            letterSpacing: 2,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // dot turns grey when disconnected
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: _connected
                              ? const Color(0xFF00FF88)
                              : const Color(0xFF445566),
                          shape: BoxShape.circle,
                          boxShadow: _connected
                              ? [
                                  BoxShadow(
                                    color: const Color(0xFF00FF88).withValues(alpha:0.6),
                                    blurRadius: 8,
                                  )
                                ]
                              : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'PARKING ALIGNMENT SENSOR',
                        style: TextStyle(
                          fontFamily: 'FrankRuhlLibre',
                          fontSize: 15,
                          letterSpacing: 3,
                          color: Color(0xFF00FF88),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // LED Ring
                AnimatedBuilder(
                  animation: _pulseAnim,
                  builder: (context, child) {
                    final bool alert = _connected && _state != SensorState.allClear;
                    return Transform.scale(
                      scale: alert ? _pulseAnim.value : 1.0,
                      child: child,
                    );
                  },
                  child: SizedBox(
                    width: MediaQuery.of(context).size.height * 0.28,
                    height: MediaQuery.of(context).size.height * 0.28,
                    child: CustomPaint(
                      painter: LedRingPainter(
                        ledCount: 24,
                        colorOf: _ledColor,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 28),

                // Reconnect indicator badge
                AnimatedBuilder(
                  animation: _pulseAnim,
                  builder: (context, child) {
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                      decoration: BoxDecoration(
                        color: !_connected
                            ? const Color(0xFF445566).withValues(alpha:_pulseAnim.value * 0.15)
                            : _statusColor.withValues(alpha:0.08),
                        borderRadius: BorderRadius.circular(40),
                        border: Border.all(
                          color: !_connected
                              ? const Color(0xFF445566).withValues(alpha:_pulseAnim.value * 0.6)
                              : _statusColor.withValues(alpha:0.4),
                          width: !_connected ? 1.5 : 1.0,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!_connected) ...[
                            SizedBox(
                              width: 10,
                              height: 10,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: const Color(0xFF445566).withValues(alpha:_pulseAnim.value),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Text(
                            _statusLabel,
                            style: TextStyle(
                              fontFamily: 'FrankRuhlLibre',
                              fontSize: 14,
                              letterSpacing: 2.5,
                              color: !_connected
                                  ? const Color(0xFF445566).withValues(alpha:0.5 + (_pulseAnim.value * 0.5))
                                  : _statusColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),

                const SizedBox(height: 28),


                // Sensor toggle buttons
                // Sensor toggle buttons
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          _SensorToggle(
                            label: 'SENSOR 1',
                            active: _s1 && !_sleeping, // Don't show active if sleeping
                            onToggle: _connected && !_sleeping ? (v) => _updateState(v, _s2) : null,
                          ),
                          const SizedBox(width: 16),
                          _SensorToggle(
                            label: 'SENSOR 2',
                            active: _s2 && !_sleeping,
                            onToggle: _connected && !_sleeping ? (v) => _updateState(_s1, v) : null,
                          ),
                        ],
                      ),
                      const SizedBox(height: 30),
                      
                      // CENTERED SLEEP/WAKE BUTTON
                      Center(
                        child: GestureDetector(
                          onTap: isOutOfRange 
                            ? null  // This disables the button click
                            : (_sleeping ? _sendWake : _sendSleep),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
                            decoration: BoxDecoration(
                              color: isOutOfRange
                                ? const Color(0xFF161B22) // Muted background
                                : _sleeping 
                                    ? Colors.transparent 
                                    : const Color(0xFF1A2530),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isOutOfRange
                                    ? const Color(0xFF2D333B) // Muted border
                                    : _sleeping
                                        ? const Color(0xFF445566)
                                        : const Color(0xFF00FF88).withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _sleeping ? Icons.power_settings_new : Icons.bedtime_outlined,
                                  color: isOutOfRange 
                                    ? const Color(0xFF445566) // Greyed out color
                                    : (_sleeping ? const Color(0xFF445566) : const Color(0xFF00FF88)),
                                  size: 18,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  _sleeping ? 'WAKE STATION' : 'SLEEP STATION',
                                  style: TextStyle(
                                    fontFamily: 'FrankRuhlLibre',
                                    fontSize: 13,
                                    letterSpacing: 2,
                                    fontWeight: FontWeight.bold,
                                    color: isOutOfRange 
                                      ? const Color(0xFF445566) // Greyed out color
                                      : (_sleeping ? const Color(0xFF445566) : const Color(0xFF00FF88)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                // Footer — dynamic connection status
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: SizedBox(
                    width: double.infinity,
                    child: Text(
                      _connected
                          ? 'Connected to ${widget.stationName} (${widget.espIp})'
                          : '${widget.stationName} is not reachable',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'FrankRuhlLibre',
                        fontSize: 11,
                        color: _connected
                            ? const Color(0xFF334455)
                            : const Color(0xFFDD1111),
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // Disconnected banner overlay at bottom
            if (!_connected && !_sleeping)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  color: const Color(0xFFDD1111).withValues(alpha:0.95),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.wifi_off,
                        color: Colors.white,
                        size: 16,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '${widget.stationName} is out of range',
                        style: const TextStyle(
                          fontFamily: 'FrankRuhlLibre',
                          fontSize: 13,
                          color: Colors.white,
                          letterSpacing: 1.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  
  int _litLeds = 0;  // how many LEDs are currently lit
  Timer? _animTimer;

  @override
  void initState() {
    super.initState();
    _startAnimation();
  }

  void _startAnimation() {
    // light up one LED every 60ms
    _animTimer = Timer.periodic(const Duration(milliseconds: 30), (timer) {
      if (_litLeds < 24) {
        setState(() => _litLeds++);
      } else {
        // all LEDs lit — wait briefly then navigate
        timer.cancel();
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const DeviceSelectScreen()),
            );
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _animTimer?.cancel();
    super.dispose();
  }

  Color _ledColor(int index) {
    return index < _litLeds
        ? const Color(0xFF00CC55)
        : const Color(0xFF1A2530);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0D12),
      body: Center(
        child: SizedBox(
          width: 280,
          height: 280,
          child: CustomPaint(
            painter: LedRingPainter(
              ledCount: 24,
              colorOf: _ledColor,
            ),
          ),
        ),
      ),
    );
  }
}

/// Home Screen
class DeviceSelectScreen extends StatelessWidget {
  const DeviceSelectScreen({super.key});

  final List<Map<String, String>> devices = const [
    {'name': 'STATION 1', 'ip': '192.168.1.18'},
    {'name': 'STATION 2', 'ip': '192.168.1.185'},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 40),
              const Text(
                'SELECT STATION',
                style: TextStyle(
                  fontFamily: 'FrankRuhlLibre',
                  fontSize: 22,
                  letterSpacing: 4,
                  color: Color(0xFF00FF88),
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Choose a parking station to monitor',
                style: TextStyle(
                  fontFamily: 'FrankRuhlLibre',
                  fontSize: 18,
                  color: Color(0xFF445566),
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 48),
              ...devices.map((device) => _DeviceCard(
                name: device['name']!,
                ip: device['ip']!,
              )),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  final String name;
  final String ip;

  const _DeviceCard({required this.name, required this.ip});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => SensorDashboard(espIp: ip, stationName: name),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF111820),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF223344)),
        ),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: Color(0xFF00FF88),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontFamily: 'FrankRuhlLibre',
                    fontSize: 16,
                    color: Colors.white,
                    letterSpacing: 2,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  ip,
                  style: const TextStyle(
                    fontFamily: 'FrankRuhlLibre',
                    fontSize: 11,
                    color: Color(0xFF445566),
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
            const Spacer(),
            const Icon(
              Icons.arrow_forward_ios,
              color: Color(0xFF445566),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}

/// Custom painter that draws a 24-LED ring
class LedRingPainter extends CustomPainter {
  final int ledCount;
  final Color Function(int index) colorOf;

  LedRingPainter({required this.ledCount, required this.colorOf});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 20;
    final ledRadius = 10.0;

    final trackPaint = Paint()
      ..color = const Color(0xFF1A2530)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 28;
    canvas.drawCircle(center, radius, trackPaint);

    for (int i = 0; i < ledCount; i++) {
      final angle = -pi / 2 + (2 * pi * i / ledCount);
      final ledCenter = Offset(
        center.dx + radius * cos(angle),
        center.dy + radius * sin(angle),
      );

      final color = colorOf(i);

      final glowPaint = Paint()
        ..color = color.withValues(alpha:0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
      canvas.drawCircle(ledCenter, ledRadius + 4, glowPaint);

      final ledPaint = Paint()..color = color;
      canvas.drawCircle(ledCenter, ledRadius, ledPaint);

      final highlightPaint = Paint()
        ..color = Colors.white.withValues(alpha:0.35)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(
        Offset(ledCenter.dx - ledRadius * 0.25, ledCenter.dy - ledRadius * 0.25),
        ledRadius * 0.35,
        highlightPaint,
      );
    }
  }

  @override
  bool shouldRepaint(LedRingPainter old) => true;
}

/// Sensor toggle chip
class _SensorToggle extends StatelessWidget {
  final String label;
  final bool active;
  final ValueChanged<bool>? onToggle; // null = disabled

  const _SensorToggle({
    required this.label,
    required this.active,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final bool disabled = onToggle == null;

    return Expanded(
      child: GestureDetector(
        onTap: disabled ? null : () => onToggle!(!active),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: disabled
                ? const Color(0xFF0F1520)
                : active
                    ? const Color(0xFFDD1111).withValues(alpha:0.12)
                    : const Color(0xFF1A2530),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: disabled
                  ? const Color(0xFF1A2530)
                  : active
                      ? const Color(0xFFDD1111).withValues(alpha:0.5)
                      : const Color(0xFF223344),
            ),
          ),
          child: Column(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: disabled
                      ? const Color(0xFF1A2530)
                      : active
                          ? const Color(0xFFFF3333)
                          : const Color(0xFF334455),
                  boxShadow: (!disabled && active)
                      ? [
                          BoxShadow(
                            color: const Color(0xFFFF3333).withValues(alpha:0.6),
                            blurRadius: 8,
                          )
                        ]
                      : null,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'FrankRuhlLibre',
                  fontSize: 11,
                  letterSpacing: 1.5,
                  color: disabled
                      ? const Color(0xFF2A3540)
                      : active
                          ? const Color(0xFFFF5555)
                          : const Color(0xFF556677),
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                disabled ? 'OFFLINE' : active ? 'TRIGGERED' : 'CLEAR',
                style: TextStyle(
                  fontFamily: 'FrankRuhlLibre',
                  fontSize: 10,
                  color: disabled
                      ? const Color(0xFF1A2530)
                      : active
                          ? const Color(0xFF883333)
                          : const Color(0xFF334455),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}