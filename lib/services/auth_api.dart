import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

import '../models/auth_session.dart';
import '../models/course.dart';
import 'auth_session_manager.dart';

class AuthApi {
  final http.Client _client;
  final AuthSessionManager? sessionManager;
  final String baseUrl;

  AuthApi({http.Client? client, this.sessionManager, String? baseUrl})
    : baseUrl = baseUrl ?? _resolveBaseUrl(),
      _client = client ?? http.Client();

  Future<AuthSession> login({
    required String role,
    required String username,
    required String password,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/v1/auth/lms-login'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'role': role,
        'username': username.trim(),
        'password': password,
      }),
    );

    final body = _decodeResponseBody(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AuthApiException(_readErrorMessage(body));
    }

    final session = AuthSession.fromJson(body);
    await (sessionManager ?? AuthSessionManager()).establish(session);
    return session;
  }

  Future<Course> fetchCourse(String courseId) async {
    return _loadAdminCourse(
      path: '/v1/admin/courses/${Uri.encodeComponent(courseId)}',
      method: 'GET',
    );
  }

  Future<Course> refreshCourse(String courseId) async {
    return _loadAdminCourse(
      path: '/v1/admin/courses/${Uri.encodeComponent(courseId)}/refresh',
      method: 'POST',
    );
  }

  Future<Course> _loadAdminCourse({
    required String path,
    required String method,
  }) async {
    final response = await _sendAuthorizedAdminCourseRequest(
      path: path,
      method: method,
      forceRefreshToken: false,
    );
    final body = _decodeResponseBody(response.body);

    if (_shouldRetryWithFreshFirebaseToken(response.statusCode, body)) {
      final retryResponse = await _sendAuthorizedAdminCourseRequest(
        path: path,
        method: method,
        forceRefreshToken: true,
      );
      final retryBody = _decodeResponseBody(retryResponse.body);

      if (retryResponse.statusCode < 200 || retryResponse.statusCode >= 300) {
        throw AuthApiException(_readErrorMessage(retryBody));
      }

      return Course.fromBackendJson(retryBody);
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AuthApiException(_readErrorMessage(body));
    }

    return Course.fromBackendJson(body);
  }

  Future<http.Response> _sendAuthorizedAdminCourseRequest({
    required String path,
    required String method,
    required bool forceRefreshToken,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw const AuthApiException(
        'Your secure session expired. Please log in again.',
      );
    }

    final idToken = await user.getIdToken(forceRefreshToken);
    if (idToken == null || idToken.isEmpty) {
      throw const AuthApiException(
        'Your secure session expired. Please log in again.',
      );
    }

    final request = http.Request(method, Uri.parse('$baseUrl$path'))
      ..headers.addAll({
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $idToken',
      });
    final streamed = await _client.send(request);
    return http.Response.fromStream(streamed);
  }

  bool _shouldRetryWithFreshFirebaseToken(
    int statusCode,
    Map<String, dynamic> body,
  ) {
    if (statusCode != 401) return false;

    final code = body['code'];
    if (code == 'INVALID_FIREBASE_TOKEN' ||
        code == 'FIREBASE_TOKEN_INVALID' ||
        code == 'FIREBASE_TOKEN_EXPIRED') {
      return true;
    }

    final message = body['message'];
    if (message is! String) return false;

    final normalized = message.toLowerCase();
    return normalized.contains('firebase session') &&
        (normalized.contains('invalid') || normalized.contains('expired'));
  }

  Map<String, dynamic> _decodeResponseBody(String rawBody) {
    final trimmed = rawBody.trim();
    if (trimmed.isEmpty) {
      throw const AuthApiException(
        'The server returned an empty response. Please try again.',
      );
    }

    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Expected a JSON object');
      }
      return decoded;
    } catch (_) {
      throw const AuthApiException(
        'The server returned an unexpected response. Please try again.',
      );
    }
  }

  String _readErrorMessage(Map<String, dynamic> body) {
    final message = body['message'];
    if (message is String && message.trim().isNotEmpty) {
      return message;
    }

    return 'Could not sign in. Please check your credentials and try again.';
  }

  static String _resolveBaseUrl() {
    const envBaseUrl = String.fromEnvironment('EACC_API_BASE_URL');
    final trimmed = envBaseUrl.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }

    if (kReleaseMode) {
      throw StateError('EACC_API_BASE_URL is required for production builds.');
    }

    return 'http://localhost:3000';
  }
}

class AuthApiException implements Exception {
  final String message;

  const AuthApiException(this.message);

  @override
  String toString() => message;
}
