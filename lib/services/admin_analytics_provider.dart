import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';

class AdminAnalyticsProvider with ChangeNotifier {
  bool _isLoading = false;
  String? _error;
  Map<String, dynamic>? _analytics;

  bool get isLoading => _isLoading;
  String? get error => _error;
  Map<String, dynamic>? get analytics => _analytics;

  String get _apiBaseUrl => getApiBaseUrl();

  Future<String> _authToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('Please sign in first.');
    }
    final token = await user.getIdToken(true);
    if (token == null || token.isEmpty) {
      throw Exception('Unable to get auth token.');
    }
    return token;
  }

  String _extractError(http.Response response, String fallback) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final detail = decoded['detail'];
        if (detail is String && detail.trim().isNotEmpty) {
          return detail.trim();
        }
      }
    } catch (_) {
      // Keep fallback
    }
    return '$fallback (${response.statusCode})';
  }

  Future<void> loadAnalytics({int days = 30}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final token = await _authToken();
      final uri = Uri.parse('$_apiBaseUrl/api/golf/admin/analytics/bootstrap')
          .replace(queryParameters: {'days': '$days'});
      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode >= 400) {
        throw Exception(_extractError(response, 'Failed to load analytics'));
      }
      _analytics = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      _error = e.toString();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
