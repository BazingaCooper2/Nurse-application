import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../main.dart';
import '../models/employee.dart';
import '../models/time_log.dart';

class ReportsPage extends StatefulWidget {
  final Employee employee;

  const ReportsPage({super.key, required this.employee});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  bool _loading = true;
  int _completed = 0;
  int _rescheduled = 0;
  int _cancelled = 0;
  double _totalHours = 0;
  List<double> _dailyHours = [];
  List<String> _days = [];

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

      final response = await supabase
          .from('time_logs')
          .select()
          .eq('employee_id', widget.employee.id)
          .gte('created_at', '${today}T00:00:00');

      int completed = 0;
      int rescheduled = 0;
      int cancelled = 0;
      double totalHours = 0;

      for (final log in response) {
        final timeLog = TimeLog.fromJson(log);
        if (timeLog.totalHours != null) {
          totalHours += timeLog.totalHours!;
        }
        if (timeLog.clockOutTime != null) completed++;
      }

      final schedules = await supabase
          .from('schedules')
          .select('status')
          .eq('employee_id', widget.employee.id);

      for (final s in schedules) {
        switch (s['status']) {
          case 'rescheduled':
            rescheduled++;
            break;
          case 'cancelled':
            cancelled++;
            break;
        }
      }

      // Load daily hours for the past 7 days
      final startDate = DateTime.now().subtract(const Duration(days: 7));
      final startDateStr = DateFormat('yyyy-MM-dd').format(startDate);

      final weeklyLogs = await supabase
          .from('time_logs')
          .select()
          .eq('employee_id', widget.employee.id)
          .gte('created_at', '${startDateStr}T00:00:00');

      Map<String, double> dailyHoursMap = {};
      for (int i = 0; i < 7; i++) {
        final date = DateTime.now().subtract(Duration(days: i));
        final dateStr = DateFormat('yyyy-MM-dd').format(date);
        dailyHoursMap[dateStr] = 0.0;
      }

      for (final log in weeklyLogs) {
        final timeLog = TimeLog.fromJson(log);
        if (timeLog.totalHours != null) {
          final dateStr = DateFormat('yyyy-MM-dd').format(timeLog.createdAt);
          if (dailyHoursMap.containsKey(dateStr)) {
            dailyHoursMap[dateStr] = dailyHoursMap[dateStr]! + timeLog.totalHours!;
          }
        }
      }

      List<double> dailyHours = [];
      List<String> days = [];
      for (int i = 6; i >= 0; i--) {
        final date = DateTime.now().subtract(Duration(days: i));
        final dateStr = DateFormat('yyyy-MM-dd').format(date);
        final dayStr = DateFormat('E').format(date); // Mon, Tue, etc.
        days.add(dayStr);
        dailyHours.add(dailyHoursMap[dateStr] ?? 0.0);
      }

      setState(() {
        _completed = completed;
        _rescheduled = rescheduled;
        _cancelled = cancelled;
        _totalHours = totalHours;
        _dailyHours = dailyHours;
        _days = days;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error loading reports: $e")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Reports")),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _SummaryCard(
                        title: "Hours Worked",
                        value: "${_totalHours.toStringAsFixed(1)} h",
                        color: Colors.blue,
                      ),
                      _SummaryCard(
                        title: "Completed",
                        value: "$_completed",
                        color: Colors.green,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _SummaryCard(
                        title: "Rescheduled",
                        value: "$_rescheduled",
                        color: Colors.purple,
                      ),
                      _SummaryCard(
                        title: "Cancelled",
                        value: "$_cancelled",
                        color: Colors.red,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Schedule Status Distribution',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 200,
                    child: PieChart(
                      PieChartData(
                        sections: _getPieSections(),
                        sectionsSpace: 2,
                        centerSpaceRadius: 40,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Daily Hours (Last 7 Days)',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 200,
                    child: BarChart(
                      BarChartData(
                        barGroups: _getBarGroups(),
                        borderData: FlBorderData(show: false),
                        titlesData: FlTitlesData(
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (value, meta) {
                                if (value.toInt() < _days.length) {
                                  return Text(_days[value.toInt()], style: const TextStyle(fontSize: 12));
                                }
                                return const Text('');
                              },
                            ),
                          ),
                          leftTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: true),
                          ),
                          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  List<PieChartSectionData> _getPieSections() {
    final total = _completed + _rescheduled + _cancelled;
    if (total == 0) return [];
    return [
      PieChartSectionData(
        value: _completed.toDouble(),
        title: 'Completed\n$_completed',
        color: Colors.green,
        radius: 50,
      ),
      PieChartSectionData(
        value: _rescheduled.toDouble(),
        title: 'Rescheduled\n$_rescheduled',
        color: Colors.purple,
        radius: 50,
      ),
      PieChartSectionData(
        value: _cancelled.toDouble(),
        title: 'Cancelled\n$_cancelled',
        color: Colors.red,
        radius: 50,
      ),
    ];
  }

  List<BarChartGroupData> _getBarGroups() {
    return List.generate(_dailyHours.length, (index) {
      return BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(
            toY: _dailyHours[index],
            color: Colors.blue,
          ),
        ],
      );
    });
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final Color color;

  const _SummaryCard({
    required this.title,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(title,
                  style: const TextStyle(fontSize: 14, color: Colors.grey)),
              const SizedBox(height: 8),
              Text(value,
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: color)),
            ],
          ),
        ),
      ),
    );
  }
}
