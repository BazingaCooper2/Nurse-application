import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
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
  List<TimeLog> _timeLogs = [];
  bool _isLoading = true;

  Position? _currentPosition;
  String? _currentAddress;

  StreamSubscription<Position>? _posSub;

  final MapController _mapController = MapController();
  final Distance _distance = const Distance();

  @override
  void initState() {
    super.initState();
    _loadData();
    _startPositionStream();
  }

  @override
  void dispose() {
    _posSub?.cancel();
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

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
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
          final nursePoint = LatLng(pos.latitude, pos.longitude);
          final patientPoint = LatLng(patient!.latitude!, patient.longitude!);

          final dist = _distance.as(LengthUnit.Meter, nursePoint, patientPoint);

          if (dist <= 10) {
            await _clockIn(_todaySchedules.first, auto: true);
          }
        }
      }
    }, onError: (e) {
      _showSnack('Location stream error: $e', isError: true);
    });
  }

  Future<void> _clockIn(Schedule schedule, {bool auto = false}) async {
    if (_currentPosition == null) return;

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
      }).eq('id', timeLog.scheduleId);

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
          : Column(
              children: [
                if (_currentPosition != null)
                  Expanded(
                    child: FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: LatLng(
                          _currentPosition!.latitude,
                          _currentPosition!.longitude,
                        ),
                        initialZoom: 15,
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
                          subdomains: const ['a', 'b', 'c'],
                        ),
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: LatLng(
                                _currentPosition!.latitude,
                                _currentPosition!.longitude,
                              ),
                              child: const Icon(Icons.person_pin_circle,
                                  color: Colors.blue, size: 40),
                            ),
                            if (patient?.latitude != null &&
                                patient?.longitude != null)
                              Marker(
                                point: LatLng(
                                  patient!.latitude!,
                                  patient.longitude!,
                                ),
                                child: const Icon(Icons.location_pin,
                                    color: Colors.red, size: 40),
                              ),
                          ],
                        ),
                        if (_currentPosition != null &&
                            patient?.latitude != null &&
                            patient?.longitude != null)
                          PolylineLayer(
                            polylines: [
                              Polyline(
                                points: [
                                  LatLng(_currentPosition!.latitude,
                                      _currentPosition!.longitude),
                                  LatLng(
                                      patient!.latitude!, patient.longitude!),
                                ],
                                strokeWidth: 4,
                                color: Colors.green,
                              )
                            ],
                          ),
                      ],
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
                if (schedule != null)
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: activeLog == null
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
                          ),
                  ),
              ],
            ),
    );
  }
}
