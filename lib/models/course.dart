class Course {
  final String id;
  final String name;
  final String category;
  final String? teacherName;
  final String? keyPersonLmsUserId;
  final String? keyPersonName;
  final List<CourseStudent> students;

  Course({
    required this.id,
    required this.name,
    required this.category,
    this.teacherName,
    this.keyPersonLmsUserId,
    this.keyPersonName,
    this.students = const [],
  });

  String get displayName {
    final normalizedName = name.trim();
    final normalizedCategory = category.trim();
    final genericName = RegExp(
      '^course\\s+${RegExp.escape(id.trim())}\$',
      caseSensitive: false,
    ).hasMatch(normalizedName);

    if (genericName &&
        normalizedCategory.isNotEmpty &&
        normalizedCategory.toLowerCase() != 'course') {
      return normalizedCategory;
    }

    return normalizedName.isEmpty ? 'Course $id' : normalizedName;
  }

  String? get displayCategory {
    final normalizedCategory = category.trim();
    if (normalizedCategory.isEmpty ||
        normalizedCategory.toLowerCase() == 'course' ||
        normalizedCategory.toLowerCase() == displayName.toLowerCase()) {
      return null;
    }
    return normalizedCategory;
  }

  factory Course.fromBackendJson(Map<String, dynamic> json) {
    final students = json['students'] as List<dynamic>? ?? [];
    final id = json['lmsCourseId'] as String;
    final rawName = (json['name'] as String?)?.trim() ?? '';
    final category = (json['category'] as String?) ?? 'Course';
    final genericName = RegExp(
      '^course\\s+${RegExp.escape(id.trim())}\$',
      caseSensitive: false,
    ).hasMatch(rawName);
    final resolvedName =
        genericName &&
            category.trim().isNotEmpty &&
            category.trim().toLowerCase() != 'course'
        ? category.trim()
        : rawName;

    return Course(
      id: id,
      name: resolvedName.isEmpty ? 'Course $id' : resolvedName,
      category: category,
      teacherName: _readTeacherName(json) ?? _extractTeacherName(category),
      keyPersonLmsUserId: _readKeyPersonLmsUserId(json),
      keyPersonName: _readKeyPersonName(json),
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
      'keyPersonLmsUserId': keyPersonLmsUserId,
      'keyPersonName': keyPersonName,
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

  static String? _readKeyPersonLmsUserId(Map<String, dynamic> json) {
    final value =
        json['keyPersonLmsUserId'] ?? json['key_person_lms_user_id'];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }

    return null;
  }

  static String? _readKeyPersonName(Map<String, dynamic> json) {
    final value = json['keyPersonName'] ?? json['key_person_name'];
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
