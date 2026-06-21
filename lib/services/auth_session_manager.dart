import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/auth_session.dart';

class AuthSessionManager {
  static const _sessionKey = 'authenticated_lms_session';
  static bool _webPersistenceConfigured = false;

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

    if (kIsWeb && !_webPersistenceConfigured) {
      await _firebaseAuth.setPersistence(Persistence.LOCAL);
      _webPersistenceConfigured = true;
    }

    if (_firebaseAuth.currentUser != null) {
      await _firebaseAuth.signOut();
    }

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
  }

  Future<AuthSession?> restore() async {
    final preferences = await SharedPreferences.getInstance();
    final storedSession = preferences.getString(_sessionKey);
    final firebaseUser = _firebaseAuth.currentUser;

    if (storedSession == null || firebaseUser == null) {
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
  }
}

class AuthSessionException implements Exception {
  final String message;

  const AuthSessionException(this.message);

  @override
  String toString() => message;
}
