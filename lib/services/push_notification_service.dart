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

  Future<void> openBrowserNotificationLaunch() async {
    final route = _readBrowserNotificationRoute();
    if (route == null) return;

    final session = _session ?? await AuthSessionManager().restore();
    if (session == null) return;
    _session = session;

    await _waitForNavigator();
    if (navigatorKey.currentState == null) return;

    debugPrint(
      'Opening notification route: courseId=${route.courseId}, threadId=${route.threadId}',
    );

    _openChatFromRoute(
      session: session,
      courseId: route.courseId,
      threadId: route.threadId,
      studentName: route.studentName,
      senderName: route.senderName,
    );
  }

  Future<void> activate(AuthSession session) async {
    _session = session;
    try {
      await _requestPermissionIfNeeded();
      await _registerDeviceTokenIfPossible(force: true);
    } catch (error, stackTrace) {
      debugPrint('Push notification activation failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> deactivate() async {
    _session = null;
    _registeredToken = null;

    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (error) {
      debugPrint('FCM token cleanup failed during logout: $error');
    }
  }

  void clearSession() {
    _session = null;
    _registeredToken = null;
  }

  void _attachListeners() {
    if (_listenersAttached) return;
    _listenersAttached = true;

    FirebaseMessaging.onMessage.listen((message) {
      final notification = message.notification;
      if (notification == null) return;

      _showTopBanner(
        title: notification.title ?? 'New message',
        body: notification.body,
        onOpen: () => unawaited(_openChatFromMessage(message)),
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
    try {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
    } catch (error) {
      debugPrint('Notification permission request failed: $error');
    }
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
      debugPrint('Device token registered for $_platformLabel');
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

    _openChatFromRoute(
      session: session,
      courseId: courseId,
      threadId: threadId,
      studentName: studentName,
      senderName: senderName,
      course: course,
    );
  }

  void _showTopBanner({
    required String title,
    String? body,
    required VoidCallback onOpen,
  }) {
    final overlay = navigatorKey.currentState?.overlay;
    if (overlay == null) return;

    var isRemoved = false;
    void dismiss(OverlayEntry entry) {
      if (isRemoved) return;
      isRemoved = true;
      entry.remove();
    }

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _TopNotificationBanner(
        title: title,
        body: body,
        onOpen: () {
          dismiss(entry);
          onOpen();
        },
        onDismiss: () => dismiss(entry),
      ),
    );

    overlay.insert(entry);
  }

  void _openChatFromRoute({
    required AuthSession session,
    required String courseId,
    required String threadId,
    String? studentName,
    String? senderName,
    Course? course,
  }) {
    final resolvedCourse = course ?? _findCourse(session, courseId);
    final resolvedStudentName = studentName?.trim();
    final resolvedSenderName = senderName?.trim();

    final title = session.appUser.role == 'teacher'
        ? (resolvedStudentName != null && resolvedStudentName.isNotEmpty
              ? resolvedStudentName
              : (resolvedSenderName != null && resolvedSenderName.isNotEmpty
                    ? resolvedSenderName
                    : 'Student Chat'))
        : (resolvedCourse?.name ?? 'Course Chat');

    final effectiveThreadId = session.appUser.role == 'teacher'
        ? threadId
        : session.lmsUser.lmsUserId;

    final threadStudentName = session.appUser.role == 'teacher'
        ? resolvedStudentName ?? resolvedSenderName
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

  Future<void> _waitForNavigator() async {
    for (var attempt = 0; attempt < 40; attempt++) {
      if (navigatorKey.currentState != null) return;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  _BrowserNotificationRoute? _readBrowserNotificationRoute() {
    final uri = Uri.base;
    final courseId = uri.queryParameters['courseId']?.trim();
    final threadId = uri.queryParameters['threadId']?.trim();
    if (courseId == null || courseId.isEmpty || threadId == null || threadId.isEmpty) {
      return null;
    }

    return _BrowserNotificationRoute(
      courseId: courseId,
      threadId: threadId,
      studentName: uri.queryParameters['studentName']?.trim(),
      senderName: uri.queryParameters['senderName']?.trim(),
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

class _TopNotificationBanner extends StatefulWidget {
  final String title;
  final String? body;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  const _TopNotificationBanner({
    required this.title,
    required this.body,
    required this.onOpen,
    required this.onDismiss,
  });

  @override
  State<_TopNotificationBanner> createState() => _TopNotificationBannerState();
}

class _TopNotificationBannerState extends State<_TopNotificationBanner> {
  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(seconds: 5), () {
      if (mounted) {
        widget.onDismiss();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top + 12;

    return Positioned(
      top: topPadding,
      left: 12,
      right: 12,
      child: SafeArea(
        bottom: false,
        child: Material(
          color: Colors.transparent,
          child: Dismissible(
            key: UniqueKey(),
            direction: DismissDirection.up,
            onDismissed: (_) => widget.onDismiss(),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF0F2742),
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 20,
                    offset: Offset(0, 10),
                  ),
                ],
                border: Border.all(color: Colors.white12),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: widget.onOpen,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFF2B66B0),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.notifications_active_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                            if (widget.body != null &&
                                widget.body!.trim().isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                widget.body!.trim(),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFFD8E2F0),
                                  fontSize: 13,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.white70,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BrowserNotificationRoute {
  final String courseId;
  final String threadId;
  final String? studentName;
  final String? senderName;

  const _BrowserNotificationRoute({
    required this.courseId,
    required this.threadId,
    this.studentName,
    this.senderName,
  });
}
