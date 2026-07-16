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

class AdminUsersCounts {
  final int all;
  final int admins;
  final int teachers;
  final int students;

  const AdminUsersCounts({
    required this.all,
    required this.admins,
    required this.teachers,
    required this.students,
  });

  const AdminUsersCounts.empty()
    : all = 0,
      admins = 0,
      teachers = 0,
      students = 0;

  factory AdminUsersCounts.fromJson(Map<String, dynamic> json) {
    return AdminUsersCounts(
      all: json['all'] as int? ?? 0,
      admins: json['admins'] as int? ?? 0,
      teachers: json['teachers'] as int? ?? 0,
      students: json['students'] as int? ?? 0,
    );
  }
}

class AdminUsersPage {
  final List<AdminUser> items;
  final int total;
  final int skip;
  final int take;
  final bool hasMore;
  final AdminUsersCounts counts;

  const AdminUsersPage({
    required this.items,
    required this.total,
    required this.skip,
    required this.take,
    required this.hasMore,
    required this.counts,
  });

  factory AdminUsersPage.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return AdminUsersPage(
      items: rawItems is List
          ? rawItems
                .map((e) => AdminUser.fromJson(e as Map<String, dynamic>))
                .toList(growable: false)
          : const [],
      total: json['total'] as int? ?? 0,
      skip: json['skip'] as int? ?? 0,
      take: json['take'] as int? ?? 10,
      hasMore: json['hasMore'] as bool? ?? false,
      counts: json['counts'] is Map<String, dynamic>
          ? AdminUsersCounts.fromJson(json['counts'] as Map<String, dynamic>)
          : const AdminUsersCounts.empty(),
    );
  }
}

class AdminApi {
  final http.Client _client;
  final String baseUrl;

  AdminApi({http.Client? client, String? baseUrl})
    : baseUrl = baseUrl ?? _resolveBaseUrl(),
      _client = client ?? http.Client();

  Future<AdminUsersPage> listUsers({
    int skip = 0,
    int take = 10,
    String? role,
    String? query,
  }) async {
    String? idToken;
    try {
      idToken = await FirebaseAuth.instance.currentUser?.getIdToken();
    } catch (_) {}

    final uri = Uri.parse('$baseUrl/v1/admin/users').replace(
      queryParameters: {
        'skip': '$skip',
        'take': '$take',
        if (role != null && role.trim().isNotEmpty) 'role': role.trim(),
        if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
      },
    );

    final response = await _client.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        if (idToken != null) 'Authorization': 'Bearer $idToken',
      },
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to load users (${response.statusCode}).');
    }

    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic>) {
      throw Exception('Unexpected response from server.');
    }

    return AdminUsersPage.fromJson(body);
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
