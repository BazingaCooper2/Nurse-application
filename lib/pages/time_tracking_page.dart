import 'dart:async';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../main.dart';
import '../models/employee.dart';
import '../models/schedule.dart';
import '../models/time_log.dart';

class TimeTrackingPage extends StatefulWidget {
  final Employee employee;

  const TimeTrackingPage({super.key, required this.employee});

  @override
  State<TimeTrackingPage> createState() => _TimeTrackingPageState();
}

class _TimeTrackingPageState extends State<TimeTrackingPage> {
  List<Schedule> _todaySchedules = [];
  List<TimeLog> _timeLogs = [];
  bool _isLoading = true;

  Position? _currentPosition;
  String? _currentAddress;

  StreamSubscription<Position>? _posSub;
  StreamSubscription<ServiceStatus>? _svcSub;
  bool _locationServiceOn = true;

  GoogleMapController? _mapController;

  Set<Marker> _markers = {};

  @override
  void initState() {
    super.initState();
    _loadData();
    _ensurePermissionThenTrack();
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _svcSub?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      setState(() {
        _isLoading = true;
      });

      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

      final schedulesResponse = await supabase
          .from('schedules')
          .select('''
            *,
            patients (
              id,
              patient_id,
              first_name,
              last_name,
              address,
              phone,
              latitude,
              longitude
            )
          ''')
          .eq('employee_id', widget.employee.id)
          .eq('scheduled_date', today)
          .order('scheduled_start_time');

      final timeLogsResponse = await supabase
          .from('time_logs')
          .select()
          .eq('employee_id', widget.employee.id)
          .gte('created_at', '${today}T00:00:00')
          .order('created_at', ascending: false);

      setState(() {
        _todaySchedules =
            schedulesResponse.map((json) => Schedule.fromJson(json)).toList();
        _timeLogs =
            timeLogsResponse.map((json) => TimeLog.fromJson(json)).toList();
        _isLoading = false;
      });
    } catch (error) {
      _showSnack('Error loading data: $error', isError: true);
      setState(() => _isLoading = false);
    }
  }

  Future<void> _showTurnOnLocationNotif() async {
    const androidDetails = AndroidNotificationDetails(
      'location_channel',
      'Location Alerts',
      importance: Importance.high,
      priority: Priority.high,
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
    );

    await localNotifs.show(
      1001,
      'Turn on Location',
      'Live tracking is paused. Tap to open Location Settings.',
      details,
    );
  }

  void _promptTurnOnLocation() {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Turn on Location'),
        content: const Text(
            'Live tracking needs your device location. Please turn it on.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Later'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await Geolocator.openLocationSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor:
            isError ? Colors.redAccent : Theme.of(context).colorScheme.primary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _ensurePermissionThenTrack() async {
    try {
      if (kIsWeb) {
        // Web only supports Position stream, no ServiceStatusStream
        await _startPositionStream();
        return;
      }

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      setState(() => _locationServiceOn = serviceEnabled);
      if (!serviceEnabled) {
        await _showTurnOnLocationNotif();
        _promptTurnOnLocation();
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        _showSnack('Location permission permanently denied.', isError: true);
        await Geolocator.openAppSettings();
        return;
      }
      if (permission == LocationPermission.denied) {
        _showSnack('Location permission denied.', isError: true);
        return;
      }

      await _svcSub?.cancel();
      if (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS) {
        _svcSub = Geolocator.getServiceStatusStream().listen((status) async {
          final on = status == ServiceStatus.enabled;
          if (mounted) setState(() => _locationServiceOn = on);
          if (!on) {
            await _showTurnOnLocationNotif();
            _promptTurnOnLocation();
          } else {
            await localNotifs.cancel(1001);
          }
        });
      }

      await _startPositionStream();
    } catch (e) {
      _showSnack('Location error: $e', isError: true);
    }
  }

  Future<void> _startPositionStream() async {
    await _posSub?.cancel();
    _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 10,
      ),
    ).listen((pos) async {
      _currentPosition = pos;
      if (_currentAddress == null) {
        final placemarks =
            await placemarkFromCoordinates(pos.latitude, pos.longitude);
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          _currentAddress =
              '${p.street}, ${p.locality}, ${p.administrativeArea}';
        }
      }
      _updateMapLocation();
      if (mounted) setState(() {});
    }, onError: (e) => _showSnack('Location stream error: $e', isError: true));
  }

  void _updateMapLocation() {
    if (_currentPosition == null || _mapController == null) return;

    final newLatLng = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);

    _mapController!.animateCamera(CameraUpdate.newLatLng(newLatLng));

    setState(() {
      _markers = {
        Marker(
          markerId: const MarkerId('currentLocation'),
          position: newLatLng,
          infoWindow: const InfoWindow(title: 'Your Location'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        ),
      };
    });
  }

  Future<void> _clockIn(Schedule schedule) async {
    if (_currentPosition == null) {
      _showSnack('Please wait for location to be detected', isError: true);
      return;
    }
    try {
      await supabase.from('time_logs').insert({
        'employee_id': widget.employee.id,
        'schedule_id': schedule.id,
        'clock_in_time': DateTime.now().toIso8601String(),
        'clock_in_latitude': _currentPosition!.latitude,
        'clock_in_longitude': _currentPosition!.longitude,
        'clock_in_address': _currentAddress,
      });
      await supabase.from('schedules').update({
        'status': 'in_progress',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', schedule.id);
      _showSnack('Clocked in successfully!');
      _loadData();
    } catch (error) {
      _showSnack('Error clocking in: $error', isError: true);
    }
  }

  Future<void> _clockOut(TimeLog timeLog) async {
    if (_currentPosition == null) {
      _showSnack('Please wait for location to be detected', isError: true);
      return;
    }
    try {
      final clockOutTime = DateTime.now();
      final clockInTime = timeLog.clockInTime!;
      final totalHours = clockOutTime.difference(clockInTime).inMinutes / 60.0;

      await supabase.from('time_logs').update({
        'clock_out_time': clockOutTime.toIso8601String(),
        'clock_out_latitude': _currentPosition!.latitude,
        'clock_out_longitude': _currentPosition!.longitude,
        'clock_out_address': _currentAddress,
        'total_hours': totalHours,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', timeLog.id);

      await supabase.from('schedules').update({
        'status': 'completed',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', timeLog.scheduleId);

      _showSnack('Clocked out successfully!');
      _loadData();
    } catch (error) {
      _showSnack('Error clocking out: $error', isError: true);
    }
  }

  TimeLog? _getActiveTimeLog(String scheduleId) {
    return _timeLogs
            .firstWhere(
              (log) => log.scheduleId == scheduleId && log.clockOutTime == null,
              orElse: () => TimeLog(
                id: '',
                employeeId: '',
                scheduleId: '',
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              ),
            )
            .id
            .isEmpty
        ? null
        : _timeLogs.firstWhere(
            (log) => log.scheduleId == scheduleId && log.clockOutTime == null,
          );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Time Tracking'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _loadData();
              _ensurePermissionThenTrack();
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!_locationServiceOn && !kIsWeb)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.redAccent),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.location_off,
                              color: Colors.redAccent),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                                'Location is OFF. Turn it on for live tracking.'),
                          ),
                          TextButton(
                            onPressed: () => Geolocator.openLocationSettings(),
                            child: const Text('Turn on'),
                          ),
                        ],
                      ),
                    ),
                  _LocationCard(
                    currentPosition: _currentPosition,
                    currentAddress: _currentAddress,
                  ),
                  const SizedBox(height: 16),
                  if (_currentPosition != null)
                    SizedBox(
                      height: 300,
                      child: GoogleMap(
                        initialCameraPosition: CameraPosition(
                          target: LatLng(
                            _currentPosition!.latitude,
                            _currentPosition!.longitude,
                          ),
                          zoom: 15,
                        ),
                        markers: _markers,
                        onMapCreated: (controller) => _mapController = controller,
                      ),
                    ),
                  const SizedBox(height: 24),
                  Text(
                    'Today\'s Appointments',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 16),
                  if (_todaySchedules.isEmpty)
                    const Center(
                        child: Text('No appointments scheduled for today'))
                  else
                    ..._todaySchedules.map((schedule) {
                      final activeTimeLog = _getActiveTimeLog(schedule.id);
                      return _TimeTrackingCard(
                        schedule: schedule,
                        activeTimeLog: activeTimeLog,
                        onClockIn: () => _clockIn(schedule),
                        onClockOut: activeTimeLog != null
                            ? () => _clockOut(activeTimeLog)
                            : null,
                      );
                    }),
                  const SizedBox(height: 24),
                  Text(
                    'Recent Time Logs',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 16),
                  if (_timeLogs.isEmpty)
                    const Center(child: Text('No time logs found'))
                  else
                    ..._timeLogs
                        .take(5)
                        .map((timeLog) => _TimeLogCard(timeLog: timeLog)),
                ],
              ),
            ),
    );
  }
}

class _LocationCard extends StatelessWidget {
  final Position? currentPosition;
  final String? currentAddress;

  const _LocationCard({
    required this.currentPosition,
    required this.currentAddress,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.location_on,
                    color: currentPosition != null ? Colors.green : Colors.red),
                const SizedBox(width: 8),
                Text(
                  'Current Location',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (currentPosition != null) ...[
              Text(currentAddress ?? 'Address not available'),
              const SizedBox(height: 8),
              Text(
                'Lat: ${currentPosition!.latitude.toStringAsFixed(6)}, '
                'Lng: ${currentPosition!.longitude.toStringAsFixed(6)}',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ] else
              const Text(
                  'Location not available. Please enable location services.',
                  style: TextStyle(color: Colors.red)),
          ],
        ),
      ),
    );
  }
}

class _TimeTrackingCard extends StatelessWidget {
  final Schedule schedule;
  final TimeLog? activeTimeLog;
  final VoidCallback onClockIn;
  final VoidCallback? onClockOut;

  const _TimeTrackingCard({
    required this.schedule,
    required this.activeTimeLog,
    required this.onClockIn,
    required this.onClockOut,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = activeTimeLog != null;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        schedule.patient?.fullName ?? 'Unknown Patient',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                      ),
                      const SizedBox(height: 4),
                      Text(schedule.serviceType,
                          style: TextStyle(color: Colors.grey[600])),
                    ],
                  ),
                ),
                if (isActive)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.green),
                    ),
                    child: const Text('ACTIVE',
                        style: TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                            fontSize: 12)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
                '${schedule.scheduledStartTime} - ${schedule.scheduledEndTime}'),
            if (schedule.patient?.address != null)
              Text(schedule.patient!.address),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: isActive ? onClockOut : onClockIn,
              icon: Icon(isActive ? Icons.logout : Icons.login),
              label: Text(isActive ? 'Clock Out' : 'Clock In'),
              style: ElevatedButton.styleFrom(
                backgroundColor: isActive ? Colors.red : Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeLogCard extends StatelessWidget {
  final TimeLog timeLog;
  const _TimeLogCard({required this.timeLog});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          timeLog.clockOutTime != null ? Icons.check_circle : Icons.timer,
          color: timeLog.clockOutTime != null ? Colors.green : Colors.orange,
        ),
        title: Text(timeLog.clockInTime != null
            ? DateFormat('MMM dd, HH:mm').format(timeLog.clockInTime!)
            : 'No clock in time'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (timeLog.clockOutTime != null)
              Text('Out: ${DateFormat('HH:mm').format(timeLog.clockOutTime!)}')
            else
              const Text('Still active'),
            if (timeLog.totalHours != null)
              Text('Total: ${timeLog.totalHours!.toStringAsFixed(2)} hours'),
          ],
        ),
      ),
    );
  }
}
