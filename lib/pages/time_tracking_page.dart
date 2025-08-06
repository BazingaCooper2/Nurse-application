import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
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

  @override
  void initState() {
    super.initState();
    _loadData();
    _getCurrentLocation();
  }

  Future<void> _loadData() async {
    try {
      setState(() {
        _isLoading = true;
      });

      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

      // Load today's schedules
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

      // Load time logs
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading data: $error'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Location services are disabled.');
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permissions are denied');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception('Location permissions are permanently denied');
      }

      final position = await Geolocator.getCurrentPosition();
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      setState(() {
        _currentPosition = position;
        if (placemarks.isNotEmpty) {
          final placemark = placemarks.first;
          _currentAddress =
              '${placemark.street}, ${placemark.locality}, ${placemark.administrativeArea}';
        }
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error getting location: $error'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _clockIn(Schedule schedule) async {
    if (_currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please wait for location to be detected'),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
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

      // Update schedule status
      await supabase.from('schedules').update({
        'status': 'in_progress',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', schedule.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Clocked in successfully!'),
            backgroundColor: Theme.of(context).colorScheme.primary,
            behavior: SnackBarBehavior.floating,
          ),
        );
        _loadData();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error clocking in: $error'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _clockOut(TimeLog timeLog) async {
    if (_currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please wait for location to be detected'),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
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

      // Update schedule status
      await supabase.from('schedules').update({
        'status': 'completed',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', timeLog.scheduleId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Clocked out successfully!'),
            backgroundColor: Theme.of(context).colorScheme.primary,
            behavior: SnackBarBehavior.floating,
          ),
        );
        _loadData();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error clocking out: $error'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
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
              _getCurrentLocation();
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
                  _LocationCard(
                    currentPosition: _currentPosition,
                    currentAddress: _currentAddress,
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
                      child: Column(
                        children: [
                          Icon(Icons.calendar_today,
                              size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text(
                            'No appointments scheduled for today',
                            style: TextStyle(fontSize: 16, color: Colors.grey),
                          ),
                        ],
                      ),
                    )
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
                    const Center(
                      child: Text(
                        'No time logs found',
                        style: TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                    )
                  else
                    ..._timeLogs
                        .take(5)
                        .map((timeLog) => _TimeLogCard(timeLog: timeLog))
                        ,
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
                Icon(
                  Icons.location_on,
                  color: currentPosition != null ? Colors.green : Colors.red,
                ),
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
              Text(
                currentAddress ?? 'Address not available',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Lat: ${currentPosition!.latitude.toStringAsFixed(6)}, '
                'Lng: ${currentPosition!.longitude.toStringAsFixed(6)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey[600],
                    ),
              ),
            ] else
              const Text(
                'Location not available. Please enable location services.',
                style: TextStyle(color: Colors.red),
              ),
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
                      Text(
                        schedule.serviceType,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.grey[600],
                            ),
                      ),
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
                    child: const Text(
                      'ACTIVE',
                      style: TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.access_time, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 8),
                Text(
                  '${schedule.scheduledStartTime} - ${schedule.scheduledEndTime}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
            if (schedule.patient?.address != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.location_on, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      schedule.patient!.address,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ],
            if (isActive && activeTimeLog!.clockInTime != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.timer, color: Colors.blue),
                    const SizedBox(width: 8),
                    Text(
                      'Started at ${DateFormat('HH:mm').format(activeTimeLog!.clockInTime!)}',
                      style: TextStyle(
                        color: Colors.blue[800],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: isActive ? onClockOut : onClockIn,
                icon: Icon(isActive ? Icons.logout : Icons.login),
                label: Text(isActive ? 'Clock Out' : 'Clock In'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isActive ? Colors.red : Colors.green,
                  foregroundColor: Colors.white,
                ),
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
        leading: CircleAvatar(
          backgroundColor: timeLog.clockOutTime != null
              ? Colors.green.withOpacity(0.2)
              : Colors.orange.withOpacity(0.2),
          child: Icon(
            timeLog.clockOutTime != null ? Icons.check : Icons.timer,
            color: timeLog.clockOutTime != null ? Colors.green : Colors.orange,
          ),
        ),
        title: Text(
          timeLog.clockInTime != null
              ? DateFormat('MMM dd, HH:mm').format(timeLog.clockInTime!)
              : 'No clock in time',
        ),
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
        trailing: timeLog.clockOutTime != null
            ? const Icon(Icons.check_circle, color: Colors.green)
            : const Icon(Icons.timer, color: Colors.orange),
      ),
    );
  }
}
