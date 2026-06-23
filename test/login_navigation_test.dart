import 'package:chatt_eacc/screens/admin_dashboard_screen.dart';
import 'package:chatt_eacc/screens/login_screen.dart';
import 'package:chatt_eacc/screens/student_courses_screen.dart';
import 'package:chatt_eacc/screens/teacher_courses_screen.dart';
import 'package:chatt_eacc/services/auth_api.dart';
import 'package:chatt_eacc/theme/app_theme.dart';
import 'package:chatt_eacc/models/auth_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeAuthApi extends AuthApi {
  FakeAuthApi(this.session);

  final AuthSession session;

  @override
  Future<AuthSession> login({
    required String role,
    required String username,
    required String password,
  }) async {
    return session;
  }
}

const studentSession = AuthSession(
  lmsUser: LmsUser(lmsUserId: '3937', role: 'student', name: 'Esam Test'),
  appUser: AppUser(
    id: '08e5943c-21b4-4bd2-9bae-89b9ba4b1798',
    role: 'student',
    name: 'Esam Test',
  ),
  courses: [],
);

const teacherSession = AuthSession(
  lmsUser: LmsUser(
    lmsUserId: '721258',
    role: 'teacher',
    name: 'Mohamed El-Sayad',
  ),
  appUser: AppUser(
    id: 'c8d9b7d0-3fdc-4df2-b9ed-49ea8b3a1111',
    role: 'teacher',
    name: 'Mohamed El-Sayad',
  ),
  courses: [],
);

const adminSession = AuthSession(
  lmsUser: LmsUser(lmsUserId: 'admin', role: 'admin', name: 'Admin'),
  appUser: AppUser(
    id: 'a1b2c3d4-0000-0000-0000-000000000000',
    role: 'admin',
    name: 'Admin',
  ),
  courses: [],
);

Future<void> pumpLogin(WidgetTester tester, {AuthApi? authApi}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: LoginScreen(authApi: authApi ?? FakeAuthApi(studentSession)),
    ),
  );
}

Future<void> selectRole(WidgetTester tester, String roleLabel) async {
  await tester.tap(find.byType(DropdownButtonFormField<String>));
  await tester.pumpAndSettle();
  await tester.tap(find.text(roleLabel).last);
  await tester.pumpAndSettle();
}

Future<void> submitLogin(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).at(0), 'student@example.com');
  await tester.enterText(find.byType(TextField).at(1), 'password');
  final loginButton = find.widgetWithText(FilledButton, 'Login');
  await tester.ensureVisible(loginButton);
  await tester.pumpAndSettle();
  await tester.tap(loginButton);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('login displays the EACC logo', (tester) async {
    await pumpLogin(tester);

    final logo = tester.widget<Image>(find.byType(Image));
    expect(logo.semanticLabel, 'Egyptian American Center');
  });

  testWidgets('student role opens the student courses screen', (tester) async {
    await pumpLogin(tester);

    await submitLogin(tester);

    expect(find.byType(StudentCoursesScreen), findsOneWidget);
    expect(find.text('Hello, Esam Test'), findsOneWidget);
    expect(find.text('No open courses'), findsOneWidget);
    expect(find.text('Elementary Level - 3'), findsNothing);
  });

  testWidgets('teacher role opens the teacher courses screen', (tester) async {
    await pumpLogin(tester, authApi: FakeAuthApi(teacherSession));
    await selectRole(tester, 'Teacher');

    await submitLogin(tester);

    expect(find.byType(TeacherCoursesScreen), findsOneWidget);
  });

  testWidgets('admin role opens the admin dashboard', (tester) async {
    await pumpLogin(tester, authApi: FakeAuthApi(adminSession));
    await selectRole(tester, 'Admin');

    await submitLogin(tester);

    expect(find.byType(AdminDashboardScreen), findsOneWidget);
  });
}
