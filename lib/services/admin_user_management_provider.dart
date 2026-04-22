import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';

class AdminUserManagementProvider with ChangeNotifier {
  bool _isLoading = false;
  String? _error;
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _selectedUserScores = [];
  List<Map<String, dynamic>> _selectedUserSubscriptions = [];
  int? _selectedUserId;

  bool get isLoading => _isLoading;
  String? get error => _error;
  List<Map<String, dynamic>> get users => _users;
  List<Map<String, dynamic>> get selectedUserScores => _selectedUserScores;
  List<Map<String, dynamic>> get selectedUserSubscriptions =>
      _selectedUserSubscriptions;
  int? get selectedUserId => _selectedUserId;

  String get _apiBaseUrl => getApiBaseUrl();

  Future<String> _authToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('Please sign in first.');
    }
    String? token = await user.getIdToken(false);
    if (token == null || token.isEmpty) {
      token = await user.getIdToken(true);
    }
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
    } catch (_) {}
    return '$fallback (${response.statusCode})';
  }

  Future<void> loadUsers({
    String? query,
    String? role,
    int limit = 100,
    int offset = 0,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final token = await _authToken();
      final qp = <String, String>{
        'limit': '$limit',
        'offset': '$offset',
      };
      if ((query ?? '').trim().isNotEmpty) qp['query'] = query!.trim();
      if ((role ?? '').trim().isNotEmpty) qp['role'] = role!.trim();

      final uri = Uri.parse('$_apiBaseUrl/api/golf/admin/users')
          .replace(queryParameters: qp);
      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode >= 400) {
        throw Exception(_extractError(response, 'Failed to load users'));
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      _users = List<Map<String, dynamic>>.from(body['items'] ?? const []);
    } catch (e) {
      _error = e.toString();
      _users = [];
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateUser(
    int userId,
    Map<String, dynamic> patch,
  ) async {
    final token = await _authToken();
    final uri = Uri.parse('$_apiBaseUrl/api/golf/admin/users/$userId');
    final response = await http.put(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(patch),
    );
    if (response.statusCode >= 400) {
      throw Exception(_extractError(response, 'Failed to update user'));
    }
    await loadUsers();
  }

  Future<void> loadUserDetails(int userId) async {
    _selectedUserId = userId;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final token = await _authToken();
      final scoresUri =
          Uri.parse('$_apiBaseUrl/api/golf/admin/users/$userId/scores');
      final subsUri =
          Uri.parse('$_apiBaseUrl/api/golf/admin/users/$userId/subscriptions');

      final responses = await Future.wait([
        http.get(scoresUri, headers: {'Authorization': 'Bearer $token'}),
        http.get(subsUri, headers: {'Authorization': 'Bearer $token'}),
      ]);
      final scoresResp = responses[0];
      final subsResp = responses[1];

      if (scoresResp.statusCode >= 400) {
        throw Exception(_extractError(scoresResp, 'Failed to load user scores'));
      }
      if (subsResp.statusCode >= 400) {
        throw Exception(
            _extractError(subsResp, 'Failed to load user subscriptions'));
      }

      _selectedUserScores = List<Map<String, dynamic>>.from(
        (jsonDecode(scoresResp.body) as Map<String, dynamic>)['items'] ??
            const [],
      );
      _selectedUserSubscriptions = List<Map<String, dynamic>>.from(
        (jsonDecode(subsResp.body) as Map<String, dynamic>)['items'] ??
            const [],
      );
    } catch (e) {
      _error = e.toString();
      _selectedUserScores = [];
      _selectedUserSubscriptions = [];
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateScore(
    String scoreId,
    Map<String, dynamic> patch,
  ) async {
    final token = await _authToken();
    final uri = Uri.parse('$_apiBaseUrl/api/golf/admin/scores/$scoreId');
    final response = await http.put(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(patch),
    );
    if (response.statusCode >= 400) {
      throw Exception(_extractError(response, 'Failed to update score'));
    }
    if (_selectedUserId != null) {
      await loadUserDetails(_selectedUserId!);
    }
  }

  Future<void> updateSubscription(
    String subscriptionId,
    Map<String, dynamic> patch,
  ) async {
    final token = await _authToken();
    final uri =
        Uri.parse('$_apiBaseUrl/api/golf/admin/subscriptions/$subscriptionId');
    final response = await http.put(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(patch),
    );
    if (response.statusCode >= 400) {
      throw Exception(_extractError(response, 'Failed to update subscription'));
    }
    if (_selectedUserId != null) {
      await loadUserDetails(_selectedUserId!);
    }
    await loadUsers();
  }
}
