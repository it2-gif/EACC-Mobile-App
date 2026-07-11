import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'auth_session_manager.dart';

class AppUpdatePolicyService {
  static const int currentBuild = 1;

  final FirebaseFirestore _firestore;
  final AuthSessionManager _sessionManager;

  AppUpdatePolicyService({
    FirebaseFirestore? firestore,
    AuthSessionManager? sessionManager,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _sessionManager = sessionManager ?? AuthSessionManager();

  Future<AppUpdatePolicyResult> apply() async {
    await _sessionManager.refreshFirebaseToken();

    try {
      final snapshot = await _firestore
          .collection('app_config')
          .doc('client')
          .get()
          .timeout(const Duration(seconds: 5));
      final data = snapshot.data();
      if (data == null) return AppUpdatePolicyResult.keepSession;

      final minBuild = (data['minBuild'] as num?)?.toInt() ?? 0;
      final forceLogout = data['forceLogout'] == true;

      if (forceLogout || minBuild > currentBuild) {
        final message = data['message']?.toString().trim();
        await _sessionManager.logout();
        return AppUpdatePolicyResult.logout(
          message != null && message.isNotEmpty
              ? message
              : 'We updated EACC Connect. Please log in again.',
        );
      }

      return AppUpdatePolicyResult.keepSession;
    } catch (error) {
      debugPrint('App update policy check skipped: $error');
      return AppUpdatePolicyResult.keepSession;
    }
  }
}

class AppUpdatePolicyResult {
  final bool shouldLogout;
  final String? message;

  const AppUpdatePolicyResult._({
    required this.shouldLogout,
    required this.message,
  });

  static const keepSession = AppUpdatePolicyResult._(
    shouldLogout: false,
    message: null,
  );

  factory AppUpdatePolicyResult.logout(String message) {
    return AppUpdatePolicyResult._(shouldLogout: true, message: message);
  }
}
