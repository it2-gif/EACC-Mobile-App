import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class NotificationApi {
  final http.Client _client;
  final String baseUrl;

  NotificationApi({http.Client? client, String? baseUrl})
    : baseUrl = baseUrl ?? _resolveBaseUrl(),
      _client = client ?? http.Client();

  Future<void> registerDeviceToken({
    required String token,
    required String platform,
    String? deviceName,
  }) async {
    await _post('/v1/notifications/device-token', {
      'token': token,
      'platform': platform,
      'deviceName': deviceName,
    });
  }

  Future<void> notifyChatMessage({
    required String courseId,
    required String threadId,
    required String senderRole,
    required String senderName,
    required String messageType,
    String? previewText,
    String? studentName,
    String? audience,
  }) async {
    await _post('/v1/notifications/chat-message', {
      'courseId': courseId,
      'threadId': threadId,
      'senderRole': senderRole,
      'senderName': senderName,
      'messageType': messageType,
      'previewText': previewText,
      'studentName': studentName,
      'audience': audience,
    });
  }

  Future<void> _post(String path, Map<String, dynamic> body) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint('Notification API skipped $path: no Firebase user.');
      return;
    }

    debugPrint('Notification API POST $path -> $baseUrl');
    final idToken = await user.getIdToken();
    final response = await _client.post(
      Uri.parse('$baseUrl$path'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $idToken',
      },
      body: jsonEncode(body),
    );

    debugPrint(
      'Notification API response $path: ${response.statusCode} ${response.body}',
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw NotificationApiException(response.body);
    }
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

class NotificationApiException implements Exception {
  final String message;

  const NotificationApiException(this.message);

  @override
  String toString() => message;
}
