import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

import '../models/auth_session.dart';
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
