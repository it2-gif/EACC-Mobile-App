class Course {
  final String id;
  final String name;
  final String category;
  final String? teacherName;
  final List<CourseStudent> students;

  Course({
    required this.id,
    required this.name,
    required this.category,
    this.teacherName,
    this.students = const [],
  });

  factory Course.fromBackendJson(Map<String, dynamic> json) {
    final students = json['students'] as List<dynamic>? ?? [];
    final category = (json['category'] as String?) ?? 'Course';

    return Course(
      id: json['lmsCourseId'] as String,
      name: json['name'] as String,
      category: category,
      teacherName: _readTeacherName(json) ?? _extractTeacherName(category),
      students: students
          .map(
            (student) =>
                CourseStudent.fromJson(student as Map<String, dynamic>),
          )
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'lmsCourseId': id,
      'name': name,
      'category': category,
      'teacherName': teacherName,
      'students': students.map((student) => student.toJson()).toList(),
    };
  }

  static String? _extractTeacherName(String category) {
    final parts = category.split(' - ');
    if (parts.length < 2) return null;

    final teacher = parts.last.trim();
    return teacher.isEmpty ? null : teacher;
  }

  static String? _readTeacherName(Map<String, dynamic> json) {
    final value = json['teacherName'] ?? json['teacher_name'];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }

    return null;
  }
}

class CourseStudent {
  final String id;
  final String name;

  const CourseStudent({required this.id, required this.name});

  factory CourseStudent.fromJson(Map<String, dynamic> json) {
    return CourseStudent(
      id: json['lmsUserId'] as String,
      name: json['name'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {'lmsUserId': id, 'name': name};
  }
}
