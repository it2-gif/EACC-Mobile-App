import 'course.dart';

class AuthSession {
  final LmsUser lmsUser;
  final AppUser appUser;
  final List<Course> courses;
  final String? firebaseCustomToken;

  const AuthSession({
    required this.lmsUser,
    required this.appUser,
    required this.courses,
    this.firebaseCustomToken,
  });

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>;
    final appUser = json['appUser'] as Map<String, dynamic>;
    final courses = json['courses'] as List<dynamic>? ?? [];
    final firebase = json['firebase'] as Map<String, dynamic>?;

    return AuthSession(
      lmsUser: LmsUser.fromJson(user),
      appUser: AppUser.fromJson(appUser),
      courses: courses
          .map(
            (course) => Course.fromBackendJson(course as Map<String, dynamic>),
          )
          .toList(growable: false),
      firebaseCustomToken: firebase?['customToken'] as String?,
    );
  }

  factory AuthSession.fromStoredJson(Map<String, dynamic> json) {
    return AuthSession.fromJson({...json, 'firebase': null});
  }

  Map<String, dynamic> toStoredJson() {
    return {
      'user': lmsUser.toJson(),
      'appUser': appUser.toJson(),
      'courses': courses.map((course) => course.toJson()).toList(),
    };
  }
}

class LmsUser {
  final String lmsUserId;
  final String role;
  final String name;

  const LmsUser({
    required this.lmsUserId,
    required this.role,
    required this.name,
  });

  factory LmsUser.fromJson(Map<String, dynamic> json) {
    return LmsUser(
      lmsUserId: json['lmsUserId'] as String,
      role: json['role'] as String,
      name: json['name'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {'lmsUserId': lmsUserId, 'role': role, 'name': name};
  }
}

class AppUser {
  final String id;
  final String role;
  final String name;
  final String? email;

  const AppUser({
    required this.id,
    required this.role,
    required this.name,
    this.email,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) {
    final email = json['email'];

    return AppUser(
      id: json['id'] as String,
      role: json['role'] as String,
      name: json['name'] as String,
      email: email is String && email.isNotEmpty ? email : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'role': role, 'name': name, 'email': email};
  }
}
