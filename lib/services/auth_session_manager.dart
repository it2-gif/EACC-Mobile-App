import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/auth_session.dart';

class AuthSessionManager {
  static const _sessionKey = 'authenticated_lms_session';
  static const _expiresAtKey = 'authenticated_lms_session_expires_at';
  static const sessionDuration = Duration(hours: 12);

  final FirebaseAuth _firebaseAuth;

  AuthSessionManager({FirebaseAuth? firebaseAuth})
    : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance;

  Future<void> establish(AuthSession session) async {
    final customToken = session.firebaseCustomToken;
    if (customToken == null || customToken.isEmpty) {
      throw const AuthSessionException(
        'The backend did not return a Firebase authentication token.',
      );
    }

    if (kIsWeb) {
      await _firebaseAuth.setPersistence(Persistence.SESSION);
    }
    await _firebaseAuth.signOut();

    final credential = await _firebaseAuth.signInWithCustomToken(customToken);
    final expectedUid = '${session.lmsUser.role}:${session.lmsUser.lmsUserId}';

    if (credential.user?.uid != expectedUid) {
      await _firebaseAuth.signOut();
      throw const AuthSessionException(
        'The Firebase identity does not match the LMS account.',
      );
    }

    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _sessionKey,
      jsonEncode(session.toStoredJson()),
    );
    await preferences.setString(
      _expiresAtKey,
      DateTime.now().add(sessionDuration).toUtc().toIso8601String(),
    );
  }

  Future<AuthSession?> restore() async {
    final preferences = await SharedPreferences.getInstance();
    final storedSession = preferences.getString(_sessionKey);
    final storedExpiry = preferences.getString(_expiresAtKey);
    final firebaseUser = _firebaseAuth.currentUser;

    if (storedSession == null || storedExpiry == null || firebaseUser == null) {
      await logout();
      return null;
    }

    final expiresAt = DateTime.tryParse(storedExpiry);
    if (expiresAt == null || !DateTime.now().toUtc().isBefore(expiresAt)) {
      await logout();
      return null;
    }

    try {
      final json = jsonDecode(storedSession) as Map<String, dynamic>;
      final session = AuthSession.fromStoredJson(json);
      final expectedUid =
          '${session.lmsUser.role}:${session.lmsUser.lmsUserId}';

      if (firebaseUser.uid != expectedUid) {
        await logout();
        return null;
      }

      return session;
    } catch (_) {
      await logout();
      return null;
    }
  }

  Future<void> logout() async {
    await _firebaseAuth.signOut();
    await clear();
  }

  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_sessionKey);
    await preferences.remove(_expiresAtKey);
  }
}

class AuthSessionException implements Exception {
  final String message;

  const AuthSessionException(this.message);

  @override
  String toString() => message;
}
