import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class AdminUser {
  final String id;
  final String lmsUserId;
  final String role;
  final String name;
  final String? email;
  final String status;
  final String? lastLoginAt;

  const AdminUser({
    required this.id,
    required this.lmsUserId,
    required this.role,
    required this.name,
    this.email,
    required this.status,
    this.lastLoginAt,
  });

  factory AdminUser.fromJson(Map<String, dynamic> json) {
    return AdminUser(
      id: json['id'] as String,
      lmsUserId: json['lmsUserId'] as String,
      role: json['role'] as String,
      name: json['name'] as String,
      email: json['email'] as String?,
      status: json['status'] as String,
      lastLoginAt: json['lastLoginAt'] as String?,
    );
  }
}

class AdminApi {
  final http.Client _client;
  final String baseUrl;

  AdminApi({http.Client? client, String? baseUrl})
    : baseUrl = baseUrl ?? _resolveBaseUrl(),
      _client = client ?? http.Client();

  Future<List<AdminUser>> listUsers() async {
    String? idToken;
    try {
      idToken = await FirebaseAuth.instance.currentUser?.getIdToken();
    } catch (_) {}

    final response = await _client.get(
      Uri.parse('$baseUrl/v1/admin/users'),
      headers: {
        'Content-Type': 'application/json',
        if (idToken != null) 'Authorization': 'Bearer $idToken',
      },
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to load users (${response.statusCode}).');
    }

    final body = jsonDecode(response.body);
    if (body is! List) throw Exception('Unexpected response from server.');

    return body
        .map((e) => AdminUser.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  static String _resolveBaseUrl() {
    const envBaseUrl = String.fromEnvironment('EACC_API_BASE_URL');
    final trimmed = envBaseUrl.trim();
    if (trimmed.isNotEmpty) return trimmed;

    if (kReleaseMode) {
      throw StateError('EACC_API_BASE_URL is required for production builds.');
    }

    return 'http://localhost:3000';
  }
}
