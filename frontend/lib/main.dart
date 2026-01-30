import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

// ============================================================================
// Main Entry Point
// ============================================================================

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => NetCutProvider(),
      child: const NetCutApp(),
    ),
  );
}

// ============================================================================
// App Theme & Configuration
// ============================================================================

class AppColors {
  // Safe/Unblocked - Teal palette
  static const Color safeLight = Color(0xFF4DB6AC);
  static const Color safeDark = Color(0xFF00897B);
  static const Color safeGradientStart = Color(0xFF26A69A);
  static const Color safeGradientEnd = Color(0xFF00796B);

  // Blocked - Salmon/Red palette
  static const Color blockedLight = Color(0xFFEF9A9A);
  static const Color blockedDark = Color(0xFFE57373);
  static const Color blockedGradientStart = Color(0xFFFF8A80);
  static const Color blockedGradientEnd = Color(0xFFD32F2F);

  // Neutral colors
  static const Color background = Color(0xFFF5F7FA);
  static const Color cardBackground = Colors.white;
  static const Color textPrimary = Color(0xFF2D3748);
  static const Color textSecondary = Color(0xFF718096);

  // Preset colors
  static const Color breakfast = Color(0xFFFFB74D);
  static const Color lunch = Color(0xFF4FC3F7);
  static const Color dinner = Color(0xFFBA68C8);
  static const Color bedtime = Color(0xFF7986CB);
}

class NetCutApp extends StatelessWidget {
  const NetCutApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NetCut Parental Control',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.safeDark,
          brightness: Brightness.light,
        ),
        textTheme: GoogleFonts.poppinsTextTheme(),
        cardTheme: CardTheme(
          elevation: 4,
          shadowColor: Colors.black.withOpacity(0.1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
      home: const MainScreen(),
    );
  }
}

// ============================================================================
// Data Models
// ============================================================================

class DeviceInfo {
  final String mac;
  final String ip;
  final String? name;

  DeviceInfo({required this.mac, required this.ip, this.name});

  factory DeviceInfo.fromJson(Map<String, dynamic> json) {
    return DeviceInfo(
      mac: json['mac'] ?? '',
      ip: json['ip'] ?? '',
      name: json['name'],
    );
  }

  String get displayName => name ?? ip;
}

class PresetSchedule {
  final String start;
  final String end;
  final bool enabled;

  PresetSchedule({
    required this.start,
    required this.end,
    this.enabled = true,
  });

  factory PresetSchedule.fromJson(Map<String, dynamic> json) {
    return PresetSchedule(
      start: json['start'] ?? '00:00',
      end: json['end'] ?? '00:00',
      enabled: json['enabled'] ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'start': start,
        'end': end,
        'enabled': enabled,
      };
}

class NetCutStatus {
  final bool isBlocking;
  final String? activeMode;
  final String? targetMac;
  final String? targetName;
  final Map<String, PresetSchedule> presets;
  final String? nextScheduledAction;

  NetCutStatus({
    required this.isBlocking,
    this.activeMode,
    this.targetMac,
    this.targetName,
    required this.presets,
    this.nextScheduledAction,
  });

  factory NetCutStatus.fromJson(Map<String, dynamic> json) {
    final presetsMap = <String, PresetSchedule>{};
    if (json['presets'] != null) {
      (json['presets'] as Map<String, dynamic>).forEach((key, value) {
        presetsMap[key] = PresetSchedule.fromJson(value);
      });
    }

    return NetCutStatus(
      isBlocking: json['is_blocking'] ?? false,
      activeMode: json['active_mode'],
      targetMac: json['target_mac'],
      targetName: json['target_name'],
      presets: presetsMap,
      nextScheduledAction: json['next_scheduled_action'],
    );
  }
}

// ============================================================================
// API Service
// ============================================================================

class ApiService {
  static const String baseUrl = 'http://127.0.0.1:8000';

  Future<NetCutStatus?> getStatus() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/status'));
      if (response.statusCode == 200) {
        return NetCutStatus.fromJson(jsonDecode(response.body));
      }
    } catch (e) {
      debugPrint('Error getting status: $e');
    }
    return null;
  }

  Future<bool> toggleBlock(bool block) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/toggle_block'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'block': block}),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error toggling block: $e');
      return false;
    }
  }

  Future<bool> setMode(String mode) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/set_mode'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'mode': mode}),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error setting mode: $e');
      return false;
    }
  }

  Future<bool> updateSchedule(
      String preset, String start, String end, bool enabled) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/update_schedule'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'preset': preset,
          'start': start,
          'end': end,
          'enabled': enabled,
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error updating schedule: $e');
      return false;
    }
  }

  Future<List<DeviceInfo>> scanDevices() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/devices'));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((e) => DeviceInfo.fromJson(e)).toList();
      }
    } catch (e) {
      debugPrint('Error scanning devices: $e');
    }
    return [];
  }

  Future<bool> setTarget(String mac, String? name) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/target'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'mac': mac, 'name': name}),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error setting target: $e');
      return false;
    }
  }
}

// ============================================================================
// State Provider
// ============================================================================

class NetCutProvider extends ChangeNotifier {
  final ApiService _api = ApiService();
  NetCutStatus? _status;
  List<DeviceInfo> _devices = [];
  bool _isLoading = false;
  bool _isConnected = false;
  Timer? _pollTimer;

  NetCutStatus? get status => _status;
  List<DeviceInfo> get devices => _devices;
  bool get isLoading => _isLoading;
  bool get isConnected => _isConnected;
  bool get isBlocking => _status?.isBlocking ?? false;

  NetCutProvider() {
    _startPolling();
  }

  void _startPolling() {
    refreshStatus();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      refreshStatus();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> refreshStatus() async {
    final status = await _api.getStatus();
    _isConnected = status != null;
    if (status != null) {
      _status = status;
    }
    notifyListeners();
  }

  Future<void> toggleBlock(bool block) async {
    _isLoading = true;
    notifyListeners();

    await _api.toggleBlock(block);
    await refreshStatus();

    _isLoading = false;
    notifyListeners();
  }

  Future<void> setMode(String mode) async {
    _isLoading = true;
    notifyListeners();

    await _api.setMode(mode);
    await refreshStatus();

    _isLoading = false;
    notifyListeners();
  }

  Future<void> updateSchedule(
      String preset, String start, String end, bool enabled) async {
    _isLoading = true;
    notifyListeners();

    await _api.updateSchedule(preset, start, end, enabled);
    await refreshStatus();

    _isLoading = false;
    notifyListeners();
  }

  Future<void> scanDevices() async {
    _isLoading = true;
    notifyListeners();

    _devices = await _api.scanDevices();

    _isLoading = false;
    notifyListeners();
  }

  Future<void> setTarget(DeviceInfo device) async {
    _isLoading = true;
    notifyListeners();

    await _api.setTarget(device.mac, device.name ?? device.ip);
    await refreshStatus();

    _isLoading = false;
    notifyListeners();
  }
}

// ============================================================================
// Main Screen with Bottom Navigation
// ============================================================================

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const DashboardScreen(),
    const ConfigurationScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Configuration',
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Dashboard Screen
// ============================================================================

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<NetCutProvider>(
      builder: (context, provider, _) {
        return Scaffold(
          backgroundColor: AppColors.background,
          body: SafeArea(
            child: CustomScrollView(
              slivers: [
                // App Bar
                SliverAppBar(
                  floating: true,
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  title: Text(
                    'NetCut',
                    style: GoogleFonts.poppins(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  actions: [
                    // Connection indicator
                    Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: Icon(
                        provider.isConnected
                            ? Icons.cloud_done
                            : Icons.cloud_off,
                        color: provider.isConnected
                            ? AppColors.safeDark
                            : Colors.red,
                      ),
                    ),
                  ],
                ),

                // Status Card
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: StatusCard(
                      isBlocking: provider.isBlocking,
                      targetName: provider.status?.targetName,
                      activeMode: provider.status?.activeMode,
                    ),
                  ),
                ),

                // Target Device Section
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Target Device',
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TargetDeviceCard(
                          targetMac: provider.status?.targetMac,
                          targetName: provider.status?.targetName,
                          onTap: () => _showDeviceSelector(context),
                        ),
                      ],
                    ),
                  ),
                ),

                // Presets Section
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Quick Presets',
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 140,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              PresetCard(
                                name: 'Breakfast',
                                icon: Icons.free_breakfast,
                                color: AppColors.breakfast,
                                schedule:
                                    provider.status?.presets['Breakfast'],
                                isActive:
                                    provider.status?.activeMode == 'Breakfast',
                                onTap: () => provider.setMode('Breakfast'),
                              ),
                              PresetCard(
                                name: 'Lunch',
                                icon: Icons.lunch_dining,
                                color: AppColors.lunch,
                                schedule: provider.status?.presets['Lunch'],
                                isActive:
                                    provider.status?.activeMode == 'Lunch',
                                onTap: () => provider.setMode('Lunch'),
                              ),
                              PresetCard(
                                name: 'Dinner',
                                icon: Icons.dinner_dining,
                                color: AppColors.dinner,
                                schedule: provider.status?.presets['Dinner'],
                                isActive:
                                    provider.status?.activeMode == 'Dinner',
                                onTap: () => provider.setMode('Dinner'),
                              ),
                              PresetCard(
                                name: 'Bedtime',
                                icon: Icons.bedtime,
                                color: AppColors.bedtime,
                                schedule: provider.status?.presets['Bedtime'],
                                isActive:
                                    provider.status?.activeMode == 'Bedtime',
                                onTap: () => provider.setMode('Bedtime'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Spacer
                const SliverToBoxAdapter(
                  child: SizedBox(height: 80),
                ),
              ],
            ),
          ),

          // Emergency Block Button
          floatingActionButton: EmergencyBlockButton(
            isBlocking: provider.isBlocking,
            isLoading: provider.isLoading,
            hasTarget: provider.status?.targetMac != null,
            onPressed: () {
              provider.toggleBlock(!provider.isBlocking);
            },
          ),
          floatingActionButtonLocation:
              FloatingActionButtonLocation.centerFloat,
        );
      },
    );
  }

  void _showDeviceSelector(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const DeviceSelectorSheet(),
    );
  }
}

// ============================================================================
// Status Card with Pulsing Animation
// ============================================================================

class StatusCard extends StatefulWidget {
  final bool isBlocking;
  final String? targetName;
  final String? activeMode;

  const StatusCard({
    super.key,
    required this.isBlocking,
    this.targetName,
    this.activeMode,
  });

  @override
  State<StatusCard> createState() => _StatusCardState();
}

class _StatusCardState extends State<StatusCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gradientColors = widget.isBlocking
        ? [AppColors.blockedGradientStart, AppColors.blockedGradientEnd]
        : [AppColors.safeGradientStart, AppColors.safeGradientEnd];

    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _pulseAnimation.value,
          child: child,
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradientColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: gradientColors[1].withOpacity(0.4),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(
              widget.isBlocking ? Icons.wifi_off : Icons.wifi,
              size: 64,
              color: Colors.white,
            ),
            const SizedBox(height: 16),
            Text(
              widget.isBlocking ? 'INTERNET BLOCKED' : 'INTERNET ALLOWED',
              style: GoogleFonts.poppins(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            if (widget.targetName != null) ...[
              const SizedBox(height: 8),
              Text(
                'Target: ${widget.targetName}',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: Colors.white.withOpacity(0.9),
                ),
              ),
            ],
            if (widget.activeMode != null && widget.activeMode != 'Manual') ...[
              const SizedBox(height: 4),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${widget.activeMode} Mode',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Target Device Card
// ============================================================================

class TargetDeviceCard extends StatelessWidget {
  final String? targetMac;
  final String? targetName;
  final VoidCallback onTap;

  const TargetDeviceCard({
    super.key,
    this.targetMac,
    this.targetName,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasTarget = targetMac != null;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: hasTarget
                ? AppColors.safeDark.withOpacity(0.3)
                : Colors.grey.withOpacity(0.3),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: hasTarget
                    ? AppColors.safeDark.withOpacity(0.1)
                    : Colors.grey.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                hasTarget ? Icons.devices : Icons.device_unknown,
                color: hasTarget ? AppColors.safeDark : Colors.grey,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasTarget ? targetName ?? 'Unknown Device' : 'No Target',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    hasTarget ? targetMac! : 'Tap to select a device',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Preset Card
// ============================================================================

class PresetCard extends StatelessWidget {
  final String name;
  final IconData icon;
  final Color color;
  final PresetSchedule? schedule;
  final bool isActive;
  final VoidCallback onTap;

  const PresetCard({
    super.key,
    required this.name,
    required this.icon,
    required this.color,
    this.schedule,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 120,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isActive
                  ? [color, color.withOpacity(0.7)]
                  : [Colors.white, Colors.white],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isActive ? color : color.withOpacity(0.3),
              width: 2,
            ),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: color.withOpacity(0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 36,
                color: isActive ? Colors.white : color,
              ),
              const SizedBox(height: 8),
              Text(
                name,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isActive ? Colors.white : AppColors.textPrimary,
                ),
              ),
              if (schedule != null) ...[
                const SizedBox(height: 4),
                Text(
                  '${schedule!.start} - ${schedule!.end}',
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    color: isActive
                        ? Colors.white.withOpacity(0.9)
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Emergency Block Button
// ============================================================================

class EmergencyBlockButton extends StatelessWidget {
  final bool isBlocking;
  final bool isLoading;
  final bool hasTarget;
  final VoidCallback onPressed;

  const EmergencyBlockButton({
    super.key,
    required this.isBlocking,
    required this.isLoading,
    required this.hasTarget,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 24),
      child: FilledButton.icon(
        onPressed: hasTarget && !isLoading ? onPressed : null,
        style: FilledButton.styleFrom(
          backgroundColor:
              isBlocking ? AppColors.safeDark : AppColors.blockedDark,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 8,
          shadowColor: (isBlocking ? AppColors.safeDark : AppColors.blockedDark)
              .withOpacity(0.5),
        ),
        icon: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Icon(isBlocking ? Icons.lock_open : Icons.lock),
        label: Text(
          isBlocking ? 'UNBLOCK NOW' : 'EMERGENCY BLOCK',
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Device Selector Bottom Sheet
// ============================================================================

class DeviceSelectorSheet extends StatefulWidget {
  const DeviceSelectorSheet({super.key});

  @override
  State<DeviceSelectorSheet> createState() => _DeviceSelectorSheetState();
}

class _DeviceSelectorSheetState extends State<DeviceSelectorSheet> {
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    _scanDevices();
  }

  Future<void> _scanDevices() async {
    setState(() => _isScanning = true);
    await context.read<NetCutProvider>().scanDevices();
    setState(() => _isScanning = false);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<NetCutProvider>(
      builder: (context, provider, _) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.7,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Select Target Device',
                      style: GoogleFonts.poppins(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    IconButton(
                      onPressed: _isScanning ? null : _scanDevices,
                      icon: _isScanning
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh),
                    ),
                  ],
                ),
              ),

              // Device List
              Expanded(
                child: provider.devices.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.devices,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _isScanning
                                  ? 'Scanning network...'
                                  : 'No devices found',
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: provider.devices.length,
                        itemBuilder: (context, index) {
                          final device = provider.devices[index];
                          final isSelected =
                              provider.status?.targetMac == device.mac;

                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            color: isSelected
                                ? AppColors.safeDark.withOpacity(0.1)
                                : null,
                            child: ListTile(
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppColors.safeDark
                                      : Colors.grey[200],
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  Icons.laptop,
                                  color:
                                      isSelected ? Colors.white : Colors.grey,
                                ),
                              ),
                              title: Text(
                                device.displayName,
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                device.mac,
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              trailing: isSelected
                                  ? const Icon(
                                      Icons.check_circle,
                                      color: AppColors.safeDark,
                                    )
                                  : null,
                              onTap: () {
                                provider.setTarget(device);
                                Navigator.pop(context);
                              },
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ============================================================================
// Configuration Screen
// ============================================================================

class ConfigurationScreen extends StatelessWidget {
  const ConfigurationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<NetCutProvider>(
      builder: (context, provider, _) {
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: Text(
              'Configuration',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.bold,
              ),
            ),
            backgroundColor: Colors.transparent,
            elevation: 0,
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Schedule Settings Section
              Text(
                'Schedule Settings',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),

              // Preset Schedule Cards
              ..._buildPresetCards(context, provider),

              const SizedBox(height: 24),

              // Connection Info
              Text(
                'Connection Info',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              _buildInfoCard(
                icon: Icons.cloud,
                title: 'Backend Status',
                value: provider.isConnected ? 'Connected' : 'Disconnected',
                valueColor:
                    provider.isConnected ? AppColors.safeDark : Colors.red,
              ),
              const SizedBox(height: 8),
              _buildInfoCard(
                icon: Icons.schedule,
                title: 'Next Scheduled Action',
                value: provider.status?.nextScheduledAction ?? 'None',
              ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildPresetCards(BuildContext context, NetCutProvider provider) {
    final presets = provider.status?.presets ?? {};
    final presetInfo = {
      'Breakfast': (Icons.free_breakfast, AppColors.breakfast),
      'Lunch': (Icons.lunch_dining, AppColors.lunch),
      'Dinner': (Icons.dinner_dining, AppColors.dinner),
      'Bedtime': (Icons.bedtime, AppColors.bedtime),
    };

    return presetInfo.entries.map((entry) {
      final schedule = presets[entry.key];
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: ScheduleConfigCard(
          name: entry.key,
          icon: entry.value.$1,
          color: entry.value.$2,
          schedule: schedule,
          onUpdate: (start, end, enabled) {
            provider.updateSchedule(entry.key, start, end, enabled);
          },
        ),
      );
    }).toList();
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String value,
    Color? valueColor,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: AppColors.textSecondary),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  Text(
                    value,
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: valueColor ?? AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Schedule Configuration Card
// ============================================================================

class ScheduleConfigCard extends StatelessWidget {
  final String name;
  final IconData icon;
  final Color color;
  final PresetSchedule? schedule;
  final Function(String start, String end, bool enabled) onUpdate;

  const ScheduleConfigCard({
    super.key,
    required this.name,
    required this.icon,
    required this.color,
    this.schedule,
    required this.onUpdate,
  });

  @override
  Widget build(BuildContext context) {
    final isEnabled = schedule?.enabled ?? true;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    name,
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Switch(
                  value: isEnabled,
                  activeColor: color,
                  onChanged: (value) {
                    onUpdate(
                      schedule?.start ?? '00:00',
                      schedule?.end ?? '00:00',
                      value,
                    );
                  },
                ),
              ],
            ),
            if (isEnabled) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _TimePickerButton(
                      label: 'Start',
                      time: schedule?.start ?? '00:00',
                      color: color,
                      onChanged: (time) {
                        onUpdate(time, schedule?.end ?? '00:00', true);
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _TimePickerButton(
                      label: 'End',
                      time: schedule?.end ?? '00:00',
                      color: color,
                      onChanged: (time) {
                        onUpdate(schedule?.start ?? '00:00', time, true);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TimePickerButton extends StatelessWidget {
  final String label;
  final String time;
  final Color color;
  final Function(String) onChanged;

  const _TimePickerButton({
    required this.label,
    required this.time,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final parts = time.split(':');
        final initialTime = TimeOfDay(
          hour: int.parse(parts[0]),
          minute: int.parse(parts[1]),
        );

        final picked = await showTimePicker(
          context: context,
          initialTime: initialTime,
          builder: (context, child) {
            return Theme(
              data: Theme.of(context).copyWith(
                colorScheme: ColorScheme.light(primary: color),
              ),
              child: child!,
            );
          },
        );

        if (picked != null) {
          final formattedTime =
              '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
          onChanged(formattedTime);
        }
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  time,
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                Icon(Icons.access_time, size: 18, color: color),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
