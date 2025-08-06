import 'patient.dart';

class Schedule {
  final String id;
  final String employeeId;
  final String patientId;
  final DateTime scheduledDate;
  final String scheduledStartTime;
  final String scheduledEndTime;
  final String serviceType;
  final String? notes;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Patient? patient;

  Schedule({
    required this.id,
    required this.employeeId,
    required this.patientId,
    required this.scheduledDate,
    required this.scheduledStartTime,
    required this.scheduledEndTime,
    required this.serviceType,
    this.notes,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.patient,
  });

  factory Schedule.fromJson(Map<String, dynamic> json) {
    return Schedule(
      id: json['id'],
      employeeId: json['employee_id'],
      patientId: json['patient_id'],
      scheduledDate: DateTime.parse(json['scheduled_date']),
      scheduledStartTime: json['scheduled_start_time'],
      scheduledEndTime: json['scheduled_end_time'],
      serviceType: json['service_type'],
      notes: json['notes'],
      status: json['status'],
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
      patient: json['patient'] != null
          ? Patient.fromJson(json['patient'])
          : null,
    );
  }
}
