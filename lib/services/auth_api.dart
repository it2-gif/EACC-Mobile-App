import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/auth_session.dart';
import 'auth_session_manager.dart';

class AuthApi {
  final http.Client _client;
  final AuthSessionManager? sessionManager;
  final String baseUrl;

  AuthApi({
    http.Client? client,
    this.sessionManager,
    this.baseUrl = const String.fromEnvironment(
      'EACC_API_BASE_URL',
      defaultValue: 'http://localhost:3000',
    ),
  }) : _client = client ?? http.Client();

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

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AuthApiException(_readErrorMessage(body));
    }

    final session = AuthSession.fromJson(body);
    await (sessionManager ?? AuthSessionManager()).establish(session);
    return session;
  }

  String _readErrorMessage(Map<String, dynamic> body) {
    final message = body['message'];
    if (message is String && message.trim().isNotEmpty) {
      return message;
    }

    return 'Could not sign in. Please check your credentials and try again.';
  }
}

class AuthApiException implements Exception {
  final String message;

  const AuthApiException(this.message);

  @override
  String toString() => message;
}
