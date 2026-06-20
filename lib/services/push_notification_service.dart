import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../firebase_options.dart';
import '../models/auth_session.dart';
import '../models/course.dart';
import '../screens/chat_screen.dart';
import 'auth_session_manager.dart';
import 'notification_api.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

class PushNotificationService {
  PushNotificationService._();

  static final PushNotificationService instance = PushNotificationService._();

  final navigatorKey = GlobalKey<NavigatorState>();
  final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  final NotificationApi _api = NotificationApi();

  AuthSession? _session;
  bool _listenersAttached = false;
  bool _openedInitialMessage = false;
  String? _registeredToken;

  Future<void> initialize({AuthSession? initialSession}) async {
    _session = initialSession;
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    _attachListeners();
    if (initialSession != null) {
      await _requestPermissionIfNeeded();
      await _registerDeviceTokenIfPossible();
      await _openInitialMessageIfNeeded();
    }
  }

  Future<void> activate(AuthSession session) async {
    _session = session;
    await _requestPermissionIfNeeded();
    await _registerDeviceTokenIfPossible(force: true);
  }

  void clearSession() {
    _session = null;
  }

  void _attachListeners() {
    if (_listenersAttached) return;
    _listenersAttached = true;

    FirebaseMessaging.onMessage.listen((message) {
      final notification = message.notification;
      if (notification == null) return;

      final messenger = scaffoldMessengerKey.currentState;
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            notification.body?.trim().isNotEmpty == true
                ? '${notification.title ?? 'New message'}: ${notification.body}'
                : notification.title ?? 'New message',
          ),
          action: SnackBarAction(
            label: 'Open',
            onPressed: () => unawaited(_openChatFromMessage(message)),
          ),
        ),
      );
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      unawaited(_openChatFromMessage(message));
    });

    FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      _registeredToken = null;
      unawaited(_registerSpecificToken(token));
    });
  }

  Future<void> _requestPermissionIfNeeded() async {
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
  }

  Future<void> _registerDeviceTokenIfPossible({bool force = false}) async {
    if (_session == null) return;

    final token = await FirebaseMessaging.instance.getToken(
      vapidKey: kIsWeb && _webVapidKey.isNotEmpty ? _webVapidKey : null,
    );
    if (token == null || token.isEmpty) return;
    if (!force && _registeredToken == token) return;

    await _registerSpecificToken(token);
  }

  Future<void> _registerSpecificToken(String token) async {
    if (_session == null || token.isEmpty) return;

    try {
      await _api.registerDeviceToken(
        token: token,
        platform: _platformLabel,
        deviceName: _deviceName,
      );
      _registeredToken = token;
    } catch (error) {
      debugPrint('Device token registration failed: $error');
    }
  }

  Future<void> _openInitialMessageIfNeeded() async {
    if (_openedInitialMessage) return;
    _openedInitialMessage = true;

    final message = await FirebaseMessaging.instance.getInitialMessage();
    if (message != null) {
      await _openChatFromMessage(message);
    }
  }

  Future<void> _openChatFromMessage(RemoteMessage message) async {
    final session = _session ?? await AuthSessionManager().restore();
    if (session == null) return;
    _session = session;

    final courseId = message.data['courseId']?.toString();
    final threadId = message.data['threadId']?.toString();
    if (courseId == null || courseId.isEmpty || threadId == null || threadId.isEmpty) {
      return;
    }

    final course = _findCourse(session, courseId);
    final studentName = message.data['studentName']?.toString();
    final senderName = message.data['senderName']?.toString() ?? 'EACC Chat';

    final title = session.appUser.role == 'teacher'
        ? (studentName != null && studentName.trim().isNotEmpty
              ? studentName.trim()
              : senderName)
        : (course?.name ?? 'Course Chat');

    final effectiveThreadId = session.appUser.role == 'teacher'
        ? threadId
        : session.lmsUser.lmsUserId;

    final threadStudentName = session.appUser.role == 'teacher'
        ? studentName
        : session.appUser.name;

    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          title: title,
          currentUserRole: session.appUser.role,
          courseId: courseId,
          threadId: effectiveThreadId,
          senderName: session.appUser.name,
          threadStudentName: threadStudentName,
        ),
      ),
    );
  }

  String get _platformLabel {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      default:
        return 'web';
    }
  }

  String get _deviceName {
    if (kIsWeb) return 'Web browser';
    return defaultTargetPlatform.name;
  }

  Course? _findCourse(AuthSession session, String courseId) {
    for (final course in session.courses) {
      if (course.id == courseId) {
        return course;
      }
    }
    return null;
  }

  static const String _webVapidKey = String.fromEnvironment(
    'EACC_FCM_VAPID_KEY',
    defaultValue: '',
  );
}
