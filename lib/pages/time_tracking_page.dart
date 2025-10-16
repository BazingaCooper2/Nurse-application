import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';

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
  List<Schedule> _allSchedules = [];
  List<TimeLog> _timeLogs = [];
  bool _isLoading = true;
  bool _isTimerRunning = false;
  Duration _elapsedTime = Duration.zero;
  Timer? _timer;

  Position? _currentPosition;
  String? _currentAddress;

  StreamSubscription<Position>? _posSub;

  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};

  @override
  void initState() {
    super.initState();
    _requestPermission();
  }

  // ✅ Added method to move camera to user's current position
  Future<void> _moveCameraToUser() async {
    if (_currentPosition != null && _mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
          15,
        ),
      );
    }
  }

  Future<void> _requestPermission() async {
    var status = await Permission.location.request();
    if (status.isGranted) {
      _loadData();
      _startPositionStream();
    } else {
      _showSnack('Location permission denied', isError: true);
    }
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      setState(() => _isLoading = true);

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

      final allSchedulesResponse = await supabase
          .from('schedules')
          .select('''
            *
          ''')
          .eq('employee_id', widget.employee.id)
          .order('scheduled_date')
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
        _allSchedules = allSchedulesResponse
            .map((json) => Schedule.fromJson(json))
            .toList();
        _timeLogs =
            timeLogsResponse.map((json) => TimeLog.fromJson(json)).toList();
        _isLoading = false;
      });
    } catch (error) {
      _showSnack('Error loading data: $error', isError: true);
      setState(() => _isLoading = false);
    }
  }

  void _showSnack(Object? msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg.toString()),
        backgroundColor:
            isError ? Colors.redAccent : Theme.of(context).colorScheme.primary,
      ),
    );
  }

  Future<void> _startPositionStream() async {
    await _posSub?.cancel();
    _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 5,
      ),
    ).listen((pos) async {
      setState(() => _currentPosition = pos);

      if (_currentAddress == null) {
        final placemarks =
            await placemarkFromCoordinates(pos.latitude, pos.longitude);
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          _currentAddress =
              '${p.street}, ${p.locality}, ${p.administrativeArea}';
        }
      }

      // Auto clock-in (10m rule)
      if (_todaySchedules.isNotEmpty) {
        final patient = _todaySchedules.first.patient;
        if (patient?.latitude != null && patient?.longitude != null) {
          final dist = Geolocator.distanceBetween(pos.latitude, pos.longitude,
              patient!.latitude!, patient.longitude!);

          if (dist <= 10) {
            await _clockIn(_todaySchedules.first, auto: true);
          }
        }
      }

      // Update markers and polylines
      _updateMarkersAndPolylines();

      // ✅ Added: move camera to current location
      _moveCameraToUser();
    }, onError: (e) {
      _showSnack('Location stream error: $e', isError: true);
    });
  }

  void _updateMarkersAndPolylines() {
    if (_currentPosition == null) return;

    _markers.clear();
    _polylines.clear();

    // Current location marker
    _markers.add(
      Marker(
        markerId: const MarkerId('current'),
        position:
            LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
        infoWindow: const InfoWindow(title: 'Your Location'),
      ),
    );

    // Patient marker if available
    final patient =
        _todaySchedules.isNotEmpty ? _todaySchedules.first.patient : null;
    if (patient?.latitude != null && patient?.longitude != null) {
      _markers.add(
        Marker(
          markerId: const MarkerId('patient'),
          position: LatLng(patient!.latitude!, patient.longitude!),
          infoWindow: InfoWindow(title: patient.fullName ?? 'Patient'),
        ),
      );

      // Polyline between nurse and patient
      _polylines.add(
        Polyline(
          polylineId: const PolylineId('route'),
          points: [
            LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
            LatLng(patient.latitude!, patient.longitude!),
          ],
          color: Colors.blue,
          width: 5,
        ),
      );
    }

    setState(() {});
  }

  Future<void> _clockIn(Schedule? schedule, {bool auto = false}) async {
    if (_currentPosition == null) return;

    if (schedule == null) {
      _startManualTimer();
      return;
    }

    // Skip if already clocked in
    if (_getActiveTimeLog(schedule.id) != null) return;

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

      _showSnack(auto
          ? '✅ Auto clocked in (within 10m of patient)'
          : '✅ Manually clocked in');
      _loadData();
    } catch (e) {
      _showSnack('Error clocking in: $e', isError: true);
    }
  }

  Future<void> _clockOut(TimeLog timeLog) async {
    if (_currentPosition == null) return;
    try {
      final clockOutTime = DateTime.now();
      final totalHours = timeLog.clockInTime != null
          ? clockOutTime.difference(timeLog.clockInTime!).inMinutes / 60.0
          : null;

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
      }).eq('id', timeLog.scheduleId!);

      _showSnack('✅ Clocked out successfully');
      _loadData();
    } catch (e) {
      _showSnack('Error clocking out: $e', isError: true);
    }
  }

  TimeLog? _getActiveTimeLog(String scheduleId) {
    try {
      return _timeLogs.firstWhere(
        (log) => log.scheduleId == scheduleId && log.clockOutTime == null,
      );
    } catch (_) {
      return null;
    }
  }

  void _startManualTimer() {
    setState(() {
      _isTimerRunning = true;
      _elapsedTime = Duration.zero;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _elapsedTime += const Duration(seconds: 1);
        });
      }
    });

    _showSnack('Manual timer started');
  }

  void _stopTimer() {
    _timer?.cancel();
    setState(() {
      _isTimerRunning = false;
    });
    _showSnack('Timer stopped at ${_formatDuration(_elapsedTime)}');
  }

  Future<void> _updateManualHours() async {
    if (_elapsedTime.inMinutes < 1) {
      _showSnack('Please work at least 1 minute', isError: true);
      return;
    }

    final totalHours = _elapsedTime.inMinutes / 60.0;
    final clockInTime = DateTime.now().subtract(_elapsedTime);

    Map<String, dynamic> data = {
      'employee_id': widget.employee.id,
      'clock_in_time': clockInTime.toIso8601String(),
      'clock_out_time': DateTime.now().toIso8601String(),
      'total_hours': totalHours,
      'created_at': DateTime.now().toIso8601String(),
    };

    if (_currentPosition != null) {
      data['clock_in_latitude'] = _currentPosition!.latitude;
      data['clock_in_longitude'] = _currentPosition!.longitude;
      data['clock_out_latitude'] = _currentPosition!.latitude;
      data['clock_out_longitude'] = _currentPosition!.longitude;
    }

    if (_currentAddress != null) {
      data['clock_in_address'] = _currentAddress;
      data['clock_out_address'] = _currentAddress;
    }

    try {
      await supabase.from('time_logs').insert(data);
      _showSnack('Hours updated: ${totalHours.toStringAsFixed(2)}h');
      setState(() {
        _isTimerRunning = false;
        _elapsedTime = Duration.zero;
      });
      _timer?.cancel();
      _loadData();
    } catch (e) {
      _showSnack('Error updating hours: ${e.toString()}', isError: true);
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$hours:$minutes:$seconds";
  }

  @override
  Widget build(BuildContext context) {
    final patient =
        _todaySchedules.isNotEmpty ? _todaySchedules.first.patient : null;
    final schedule = _todaySchedules.isNotEmpty ? _todaySchedules.first : null;
    final activeLog = schedule != null ? _getActiveTimeLog(schedule.id) : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Time Tracking'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _loadData();
              _startPositionStream();
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                children: [
                  if (_currentPosition != null)
                    Center(
                      child: Container(
                        width: 300,
                        height: 300,
                        margin: const EdgeInsets.all(16.0),
                        child: GoogleMap(
                          initialCameraPosition: CameraPosition(
                            target: LatLng(
                              _currentPosition!.latitude,
                              _currentPosition!.longitude,
                            ),
                            zoom: 15,
                          ),
                          markers: _markers,
                          polylines: _polylines,
                          onMapCreated: (controller) {
                            _mapController = controller;
                          },
                          myLocationEnabled: true,
                          myLocationButtonEnabled: true,
                        ),
                      ),
                    )
                  else
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text("Waiting for location..."),
                      ),
                    ),

                  // Manual buttons
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: schedule != null
                        ? (activeLog == null
                            ? ElevatedButton.icon(
                                onPressed: () => _clockIn(schedule),
                                icon: const Icon(Icons.login),
                                label: const Text("Clock In Manually"),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size(double.infinity, 50),
                                ),
                              )
                            : ElevatedButton.icon(
                                onPressed: () => _clockOut(activeLog),
                                icon: const Icon(Icons.logout),
                                label: const Text("Clock Out"),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size(double.infinity, 50),
                                ),
                              ))
                        : (!_isTimerRunning
                            ? ElevatedButton.icon(
                                onPressed: () => _clockIn(null),
                                icon: const Icon(Icons.timer),
                                label: const Text("Clock In Manually"),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size(double.infinity, 50),
                                ),
                              )
                            : const SizedBox.shrink()),
                  ),

                  if (schedule == null && _isTimerRunning)
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          Text(
                            _formatDuration(_elapsedTime),
                            style: Theme.of(context)
                                    .textTheme
                                    .headlineLarge
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                    ) ??
                                const TextStyle(
                                  fontSize: 48,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _stopTimer,
                                  icon: const Icon(Icons.stop,
                                      color: Colors.white),
                                  label: const Text(
                                    'Stop',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.orange,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _updateManualHours,
                                  icon: const Icon(Icons.save,
                                      color: Colors.white),
                                  label: const Text(
                                    'Update Hours',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                  // Schedules list
                  ..._allSchedules
                      .where((s) =>
                          s.status == 'scheduled' || s.status == 'rescheduled')
                      .map(_buildScheduleCard),
                ],
              ),
            ),
    );
  }

  Widget _buildScheduleCard(Schedule schedule) {
    final date = DateFormat('MMM dd, yyyy').format(schedule.scheduledDate);
    final start = schedule.scheduledStartTime;
    final end = schedule.scheduledEndTime;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListTile(
        title: Text(schedule.serviceType),
        subtitle: Text('$date $start - $end'),
        trailing: Text(schedule.status),
      ),
    );
  }
}
