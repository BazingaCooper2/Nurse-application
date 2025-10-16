import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../main.dart';
import '../models/employee.dart';
import '../models/schedule.dart';

class SchedulePage extends StatefulWidget {
  final Employee employee;

  const SchedulePage({super.key, required this.employee});

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  List<Schedule> _schedules = [];
  List<Schedule> _scheduled = [];
  List<Schedule> _rescheduled = [];
  List<Schedule> _completed = [];

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
          .order('scheduled_date')
          .order('scheduled_start_time');

      final schedules =
          response.map<Schedule>((json) => Schedule.fromJson(json)).toList();

      setState(() {
        _schedules = schedules;

        _scheduled = schedules.where((s) => s.status == 'scheduled').toList();
        _rescheduled =
            schedules.where((s) => s.status == 'rescheduled').toList();
        _completed = schedules.where((s) => s.status == 'completed').toList();

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Schedules'),
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
                  _buildSection('Scheduled', _scheduled),
                  _buildSection('Rescheduled', _rescheduled),
                  _buildSection('Completed', _completed),
                ],
              ),
            ),
    );
  }

  Widget _buildSection(String title, List<Schedule> schedules) {
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
        if (schedules.isEmpty)
          const Text('No tasks in this category')
        else
          ...schedules.map(_buildCard),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildCard(Schedule schedule) {
    final date = DateFormat('MMM dd, yyyy').format(schedule.scheduledDate);
    final start = schedule.scheduledStartTime;
    final end = schedule.scheduledEndTime;
    final status = schedule.status;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: ListTile(
        title: Text(schedule.serviceType),
        subtitle: Text('$date $start - $end ($status)'),
        trailing: schedule.notes != null ? const Icon(Icons.info) : null,
      ),
    );
  }
}
