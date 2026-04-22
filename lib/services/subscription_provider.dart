import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';

class SubscriptionProvider with ChangeNotifier {
  bool _isLoading = false;
  String? _error;
  List<Map<String, dynamic>> _subscriptions = [];

  bool get isLoading => _isLoading;
  String? get error => _error;
  List<Map<String, dynamic>> get subscriptions => _subscriptions;

  String get _apiBaseUrl => getApiBaseUrl();

  int planAmountCents(String planId) {
    switch (_normalizedPlanId(planId)) {
      case 'monthly':
        return 999;
      case 'yearly':
        return 4999;
      default:
        return 999;
    }
  }

  String _normalizedPlanId(String planId) {
    switch (planId) {
      case 'basic':
        return 'monthly';
      case 'vip':
        return 'yearly';
      default:
        return planId.trim().toLowerCase();
    }
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

  Future<void> loadSubscriptions() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final token = await _authToken();
      final uri = Uri.parse('$_apiBaseUrl/api/golf/me/subscription');
      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode >= 400) {
        throw Exception(_extractError(response, 'Failed to load subscription'));
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['has_subscription'] == true) {
        _subscriptions = [data];
      } else {
        _subscriptions = [];
      }
    } catch (e) {
      _error = e.toString();
      _subscriptions = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> createSubscription(
    String _,
    String planId, {
    String paymentProvider = 'stripe_mock',
    required String charityId,
    required double charityContributionPct,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final token = await _authToken();
      final normalizedPlan = _normalizedPlanId(planId);
      final amountCents = planAmountCents(normalizedPlan);

      final uri = Uri.parse(
        '$_apiBaseUrl/api/golf/me/subscription/checkout-complete',
      );
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'plan_id': normalizedPlan,
          'amount_paid_cents': amountCents,
          'charity_id': charityId,
          'charity_contribution_pct': charityContributionPct,
          'payment_provider': paymentProvider,
        }),
      );

      if (response.statusCode >= 400) {
        throw Exception(_extractError(response, 'Subscription failed'));
      }

      await loadSubscriptions();
    } catch (e) {
      _error = e.toString();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> cancelSubscription(String _) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final token = await _authToken();
      final uri = Uri.parse('$_apiBaseUrl/api/golf/me/subscription/cancel');
      final response = await http.post(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode >= 400) {
        throw Exception(_extractError(response, 'Cancel failed'));
      }

      await loadSubscriptions();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
