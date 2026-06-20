import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class NotificationApi {
  final http.Client _client;
  final String baseUrl;

  NotificationApi({
    http.Client? client,
    this.baseUrl = const String.fromEnvironment(
      'EACC_API_BASE_URL',
      defaultValue: 'http://localhost:3000',
    ),
  }) : _client = client ?? http.Client();

  Future<void> registerDeviceToken({
    required String token,
    required String platform,
    String? deviceName,
  }) async {
    await _post(
      '/v1/notifications/device-token',
      {
        'token': token,
        'platform': platform,
        'deviceName': deviceName,
      },
    );
  }

  Future<void> notifyChatMessage({
    required String courseId,
    required String threadId,
    required String senderRole,
    required String senderName,
    required String messageType,
    String? previewText,
    String? studentName,
  }) async {
    await _post(
      '/v1/notifications/chat-message',
      {
        'courseId': courseId,
        'threadId': threadId,
        'senderRole': senderRole,
        'senderName': senderName,
        'messageType': messageType,
        'previewText': previewText,
        'studentName': studentName,
      },
    );
  }

  Future<void> _post(String path, Map<String, dynamic> body) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final idToken = await user.getIdToken();
    final response = await _client.post(
      Uri.parse('$baseUrl$path'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $idToken',
      },
      body: jsonEncode(body),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw NotificationApiException(response.body);
    }
  }
}

class NotificationApiException implements Exception {
  final String message;

  const NotificationApiException(this.message);

  @override
  String toString() => message;
}
