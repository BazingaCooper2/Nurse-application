import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../main.dart';
import '../models/employee.dart';
import '../models/schedule.dart';
import 'schedule_details_page.dart';

class SchedulePage extends StatefulWidget {
  final Employee employee;

  const SchedulePage({super.key, required this.employee});

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  List<Schedule> _schedules = [];
  List<Schedule> _today = [];
  List<Schedule> _upcoming = [];
  List<Schedule> _past = [];
  List<Schedule> _rescheduled = [];

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSchedules();
  }

  Future<void> _loadSchedules() async {
    try {
      setState(() {
        _isLoading = true;
      });

      final response = await supabase
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
              medical_notes,
              latitude,
              longitude
            )
          ''')
          .eq('employee_id', widget.employee.id)
          .gte(
              'scheduled_date',
              DateFormat('yyyy-MM-dd')
                  .format(DateTime.now().subtract(const Duration(days: 7))))
          .order('scheduled_date')
          .order('scheduled_start_time');

      final schedules =
          response.map<Schedule>((json) => Schedule.fromJson(json)).toList();

      final now = DateTime.now();

      setState(() {
        _schedules = schedules;

        _today = schedules.where((s) {
          return s.scheduledDate.year == now.year &&
              s.scheduledDate.month == now.month &&
              s.scheduledDate.day == now.day;
        }).toList();

        _upcoming =
            schedules.where((s) => s.scheduledDate.isAfter(now)).toList();

        _past = schedules
            .where(
                (s) => s.scheduledDate.isBefore(now) && s.status == 'completed')
            .toList();

        _rescheduled =
            schedules.where((s) => s.status == 'rescheduled').toList();

        _isLoading = false;
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading schedules: $error'),
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

  Future<void> _rescheduleAppointment(Schedule schedule) async {
    final newDate = await showDatePicker(
      context: context,
      initialDate: schedule.scheduledDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (newDate == null) return;

    final newTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        DateTime.parse('2023-01-01 ${schedule.scheduledStartTime}'),
      ),
    );

    if (newTime == null) return;

    try {
      await supabase.from('schedules').update({
        'scheduled_date': DateFormat('yyyy-MM-dd').format(newDate),
        'scheduled_start_time':
            '${newTime.hour.toString().padLeft(2, '0')}:${newTime.minute.toString().padLeft(2, '0')}:00',
        'status': 'rescheduled',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', schedule.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Appointment rescheduled successfully!'),
            backgroundColor: Theme.of(context).colorScheme.primary,
            behavior: SnackBarBehavior.floating,
          ),
        );
        _loadSchedules();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error rescheduling: $error'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Schedule'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadSchedules,
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
                  if (_today.isNotEmpty)
                    _Section(
                      title: "Today's Appointments",
                      schedules: _today,
                      onReschedule: _rescheduleAppointment,
                    ),
                  if (_upcoming.isNotEmpty)
                    _Section(
                      title: "Upcoming Appointments",
                      schedules: _upcoming,
                      onReschedule: _rescheduleAppointment,
                    ),
                  if (_rescheduled.isNotEmpty)
                    _Section(
                      title: "Rescheduled",
                      schedules: _rescheduled,
                      onReschedule: _rescheduleAppointment,
                    ),
                  if (_past.isNotEmpty)
                    _Section(
                      title: "Past Appointments",
                      schedules: _past,
                      onReschedule: _rescheduleAppointment,
                    ),
                  if (_today.isEmpty &&
                      _upcoming.isEmpty &&
                      _past.isEmpty &&
                      _rescheduled.isEmpty)
                    const Center(
                      child: Column(
                        children: [
                          Icon(Icons.calendar_today,
                              size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text(
                            'No schedules found',
                            style: TextStyle(fontSize: 18, color: Colors.grey),
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

class _Section extends StatelessWidget {
  final String title;
  final List<Schedule> schedules;
  final Function(Schedule) onReschedule;

  const _Section({
    required this.title,
    required this.schedules,
    required this.onReschedule,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 8),
        ...schedules.map((s) => _ScheduleCard(
              schedule: s,
              onReschedule: () => onReschedule(s),
            )),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _ScheduleCard extends StatelessWidget {
  final Schedule schedule;
  final VoidCallback onReschedule;

  const _ScheduleCard({
    required this.schedule,
    required this.onReschedule,
  });

  Color _getStatusColor() {
    switch (schedule.status) {
      case 'scheduled':
        return Colors.blue;
      case 'in_progress':
        return Colors.orange;
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      case 'rescheduled':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
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
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
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
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _getStatusColor().withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _getStatusColor()),
                  ),
                  child: Text(
                    schedule.status.toUpperCase(),
                    style: TextStyle(
                      color: _getStatusColor(),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.calendar_today, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 8),
                Text(
                  DateFormat('MMM dd, yyyy').format(schedule.scheduledDate),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(width: 24),
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
            if (schedule.notes != null && schedule.notes!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.note, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      schedule.notes!,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ],
            if (schedule.patient?.medicalNotes != null &&
                schedule.patient!.medicalNotes!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.medical_services,
                        size: 16, color: Colors.blue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        schedule.patient!.medicalNotes!,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Colors.blue[800]),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                if (schedule.status == 'scheduled') ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onReschedule,
                      icon: const Icon(Icons.schedule),
                      label: const Text('Reschedule'),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) =>
                              ScheduleDetailsPage(schedule: schedule),
                        ),
                      );
                    },
                    icon: const Icon(Icons.info),
                    label: const Text('View Details'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
