class Employee {
  final String id;
  final String userId;
  final String employeeId;
  final String firstName;
  final String lastName;
  final String email;
  final String? phone;
  final String position;
  final String? department;
  final DateTime hireDate;
  final bool isActive;
  final String? profileImageUrl;
  final double? totalVacationHours;
  final double? usedVacationHours;
  final DateTime createdAt;
  final DateTime updatedAt;

  Employee({
    required this.id,
    required this.userId,
    required this.employeeId,
    required this.firstName,
    required this.lastName,
    required this.email,
    this.phone,
    required this.position,
    this.department,
    required this.hireDate,
    required this.isActive,
    this.profileImageUrl,
    this.totalVacationHours,
    this.usedVacationHours,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Employee.fromJson(Map<String, dynamic> json) {
    return Employee(
      id: json['id'],
      userId: json['user_id'],
      employeeId: json['employee_id'],
      firstName: json['first_name'],
      lastName: json['last_name'],
      email: json['email'],
      phone: json['phone'],
      position: json['position'],
      department: json['department'],
      hireDate: DateTime.parse(json['hire_date']),
      isActive: json['is_active'],
      profileImageUrl: json['profile_image_url'],
      totalVacationHours: json['total_vacation_hours'] != null ? (json['total_vacation_hours'] as num).toDouble() : null,
      usedVacationHours: json['used_vacation_hours'] != null ? (json['used_vacation_hours'] as num).toDouble() : null,
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'employee_id': employeeId,
      'first_name': firstName,
      'last_name': lastName,
      'email': email,
      'phone': phone,
      'position': position,
      'department': department,
      'hire_date': hireDate.toIso8601String(),
      'is_active': isActive,
      'profile_image_url': profileImageUrl,
      'total_vacation_hours': totalVacationHours,
      'used_vacation_hours': usedVacationHours,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  String get fullName => '$firstName $lastName';
}
