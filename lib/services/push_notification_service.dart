import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../firebase_options.dart';
import '../models/auth_session.dart';
import '../models/course.dart';
import '../screens/chat_screen.dart';
import '../utils/notification_sound.dart';
import 'auth_session_manager.dart';
import 'notification_api.dart';
import 'web_browser_notification.dart';
import 'web_fcm_token.dart';

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

  void showInAppNotification({
    required String title,
    String? body,
    VoidCallback? onOpen,
    bool playSound = true,
  }) {
    if (title.trim().isEmpty && (body == null || body.trim().isEmpty)) {
      return;
    }

    if (playSound) {
      playNotificationSound();
    }

    _showTopBanner(title: title, body: body, onOpen: onOpen ?? () {});
  }

  void _attachListeners() {
    if (_listenersAttached) return;
    _listenersAttached = true;

    FirebaseMessaging.onMessage.listen((message) {
      _handleForegroundMessage(message);
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
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      debugPrint(
        'Notification permission status: ${settings.authorizationStatus.name}',
      );
    } catch (error) {
      debugPrint('Notification permission request failed: $error');
    }
  }

  Future<void> _registerDeviceTokenIfPossible({bool force = false}) async {
    if (_session == null) {
      debugPrint('Device token registration skipped: no active session.');
      return;
    }

    if (kIsWeb && _webVapidKey.isEmpty) {
      debugPrint(
        'Web push is disabled: set EACC_FCM_VAPID_KEY from Firebase Console '
        '(Project settings -> Cloud Messaging -> Web Push certificates).',
      );
      return;
    }

    if (kIsWeb) {
      await Future<void>.delayed(const Duration(seconds: 1));
    }

    debugPrint(
      'Requesting FCM device token for $_platformLabel. '
      'Web VAPID key configured: ${!kIsWeb || _webVapidKey.isNotEmpty}',
    );
    final token = kIsWeb
        ? await _getWebToken()
        : await FirebaseMessaging.instance.getToken();
    if (token == null || token.isEmpty) {
      debugPrint('FCM device token was not returned for $_platformLabel.');
      return;
    }
    if (!force && _registeredToken == token) return;

    await _registerSpecificToken(token);
  }

  Future<String?> _getWebToken() async {
    final bridgeToken = await requestWebFcmToken(_webVapidKey);
    if (bridgeToken != null && bridgeToken.isNotEmpty) {
      debugPrint('FCM web token returned from EACC service worker bridge.');
      return bridgeToken;
    }

    debugPrint(
      'FCM web token was not created. GitHub Pages must use the EACC '
      'service-worker bridge; the Firebase plugin fallback expects a root '
      'service worker and is intentionally skipped.',
    );
    return null;
  }

  void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('Foreground push received: ${message.messageId ?? 'no id'}');
    final data = message.data;
    final notification = message.notification;
    final title =
        notification?.title ?? data['senderName']?.toString() ?? 'New message';
    final body =
        notification?.body ??
        data['previewText']?.toString() ??
        'You received a new chat message';

    if (title.trim().isEmpty && body.trim().isEmpty) {
      return;
    }

    if (kIsWeb) {
      unawaited(
        showWebBrowserNotification(
          title: title,
          body: body,
          courseId: data['courseId']?.toString() ?? '',
          threadId: data['threadId']?.toString() ?? '',
          studentName: data['studentName']?.toString() ?? '',
          senderName: data['senderName']?.toString() ?? title,
        ),
      );
    }

    showInAppNotification(
      title: title,
      body: body,
      onOpen: () => unawaited(_openChatFromMessage(message)),
    );
  }

  Future<void> _registerSpecificToken(String token) async {
    if (_session == null || token.isEmpty) {
      debugPrint(
        'Device token registration skipped: missing session or token.',
      );
      return;
    }

    try {
      await _api.registerDeviceToken(
        token: token,
        platform: _platformLabel,
        deviceName: _deviceName,
      );
      _registeredToken = token;
      final tokenPreview = token.length > 12 ? token.substring(0, 12) : token;
      debugPrint(
        'Device token registered for $_platformLabel: $tokenPreview...',
      );
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
    if (courseId == null ||
        courseId.isEmpty ||
        threadId == null ||
        threadId.isEmpty) {
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
    if (courseId == null ||
        courseId.isEmpty ||
        threadId == null ||
        threadId.isEmpty) {
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
    defaultValue:
        'BI9vFbWr5a4snY-mJk2uiae56Nf-zEA3axDqG1PzWruGrENyyguwW1ZHHfo8A7xCAC3AMxYMZelwnbYnNh-BZvg',
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

class _TopNotificationBannerState extends State<_TopNotificationBanner>
    with TickerProviderStateMixin {
  // Slide controller — forward = enter, reverse = exit.
  late final AnimationController _slideController;
  // Progress controller — forward = bar drains from full to empty.
  late final AnimationController _progressController;

  late final Animation<Offset> _slideAnim;
  late final Animation<double> _fadeAnim;

  bool _isDismissing = false;

  static const _slideInDuration = Duration(milliseconds: 480);
  static const _slideOutDuration = Duration(milliseconds: 280);
  static const _displayDuration = Duration(milliseconds: 4800);

  @override
  void initState() {
    super.initState();

    _slideController = AnimationController(vsync: this, value: 0);
    _progressController = AnimationController(
      vsync: this,
      duration: _displayDuration,
    );

    _slideAnim = Tween<Offset>(begin: const Offset(0, -1.6), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _slideController,
            curve: Curves.easeOutBack,
            reverseCurve: Curves.easeInCubic,
          ),
        );

    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _slideController,
        curve: const Interval(0.0, 0.55),
      ),
    );

    // Slide in, then start the progress drain.
    _slideController.animateTo(1.0, duration: _slideInDuration).then((_) {
      if (mounted) _progressController.forward();
    });

    // Auto-dismiss after display duration.
    Future<void>.delayed(_slideInDuration + _displayDuration, _dismiss);
  }

  Future<void> _dismiss() async {
    if (_isDismissing || !mounted) return;
    _isDismissing = true;
    _progressController.stop();
    await _slideController.animateTo(0.0, duration: _slideOutDuration);
    if (mounted) widget.onDismiss();
  }

  @override
  void dispose() {
    _slideController.dispose();
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;

    return Positioned(
      top: topInset + 10,
      left: 12,
      right: 12,
      child: SlideTransition(
        position: _slideAnim,
        child: FadeTransition(
          opacity: _fadeAnim,
          child: GestureDetector(
            onVerticalDragEnd: (details) {
              if (details.primaryVelocity != null &&
                  details.primaryVelocity! < -100) {
                _dismiss();
              }
            },
            child: Material(
              color: Colors.transparent,
              child: _BannerCard(
                title: widget.title,
                body: widget.body,
                progressController: _progressController,
                onOpen: () {
                  _dismiss();
                  widget.onOpen();
                },
                onDismiss: _dismiss,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── The visual card ─────────────────────────────────────────────────────────

class _BannerCard extends StatelessWidget {
  final String title;
  final String? body;
  final AnimationController progressController;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  const _BannerCard({
    required this.title,
    required this.body,
    required this.progressController,
    required this.onOpen,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D1F35),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x55000000),
            blurRadius: 28,
            spreadRadius: 2,
            offset: Offset(0, 12),
          ),
        ],
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      clipBehavior: Clip.hardEdge,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(18),
        splashColor: Colors.white.withValues(alpha: 0.06),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 10, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // App icon
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1D5DA8), Color(0xFF0C2E68)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.chat_bubble_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Text block
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // App label + "now"
                        Row(
                          children: [
                            const Text(
                              'EACC Chat',
                              style: TextStyle(
                                color: Color(0xFF7FA8D4),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.3,
                              ),
                            ),
                            const Spacer(),
                            const Text(
                              'now',
                              style: TextStyle(
                                color: Color(0xFF4C6A8C),
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(width: 4),
                          ],
                        ),
                        const SizedBox(height: 3),

                        // Sender name
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 14.5,
                            height: 1.2,
                          ),
                        ),

                        // Message body
                        if (body != null && body!.trim().isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            body!.trim(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFB0C8E4),
                              fontSize: 13,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Dismiss (×) button
                  GestureDetector(
                    onTap: onDismiss,
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 4, 0),
                      child: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: Colors.white.withValues(alpha: 0.35),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Draining progress bar
            AnimatedBuilder(
              animation: progressController,
              builder: (context, _) {
                return LinearProgressIndicator(
                  value: 1.0 - progressController.value,
                  backgroundColor: Colors.white.withValues(alpha: 0.06),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    Color(0xFF2B66B0),
                  ),
                  minHeight: 3,
                );
              },
            ),
          ],
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
