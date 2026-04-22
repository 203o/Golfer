import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';

class CharityProvider with ChangeNotifier {
  bool _isLoading = false;
  String? _error;
  List<Map<String, dynamic>> _charities = [];
  List<String> _availableCauses = [];
  Map<String, dynamic>? _selectedCharity;
  Map<String, dynamic>? _featuredCharity;
  Map<String, dynamic>? _myCharitySelection;
  List<Map<String, dynamic>> _adminDonationSummary = [];
  List<Map<String, dynamic>> _adminDonationEntries = [];

  bool get isLoading => _isLoading;
  String? get error => _error;
  List<Map<String, dynamic>> get charities => _charities;
  List<String> get availableCauses => _availableCauses;
  Map<String, dynamic>? get selectedCharity => _selectedCharity;
  Map<String, dynamic>? get featuredCharity => _featuredCharity;
  Map<String, dynamic>? get myCharitySelection => _myCharitySelection;
  List<Map<String, dynamic>> get adminDonationSummary => _adminDonationSummary;
  List<Map<String, dynamic>> get adminDonationEntries => _adminDonationEntries;

  double get totalDonations => _charities.fold(
        0.0,
        (sum, charity) =>
            sum +
            (((charity['total_raised_cents'] ?? 0) as num).toDouble() / 100.0),
      );

  String get _apiBaseUrl => getApiBaseUrl();

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

  List<Map<String, dynamic>> _mapList(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Map<String, dynamic>? _mapOrNull(dynamic raw) {
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    return null;
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

  Future<void> loadCharities({
    String? search,
    String? cause,
    bool featuredOnly = false,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final uri = Uri.parse('$_apiBaseUrl/api/golf/public/charities').replace(
        queryParameters: {
          if ((search ?? '').trim().isNotEmpty) 'search': search!.trim(),
          if ((cause ?? '').trim().isNotEmpty) 'cause': cause!.trim(),
          if (featuredOnly) 'featured_only': 'true',
        },
      );
      final response = await http.get(uri);

      if (response.statusCode >= 400) {
        throw Exception(_extractError(response, 'Failed to load charities'));
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      _charities = _mapList(data['charities']);
      _availableCauses =
          List<String>.from(data['available_causes'] ?? const []);
      _featuredCharity = _mapOrNull(data['featured_charity']);

      final selectedId = (_selectedCharity?['id'] ?? '').toString();
      if (selectedId.isNotEmpty) {
        try {
          _selectedCharity = _charities
              .firstWhere((c) => (c['id'] ?? '').toString() == selectedId);
        } catch (_) {}
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> selectCharity(String charityId) async {
    try {
      _selectedCharity = _charities.firstWhere(
        (c) => (c['id'] ?? '').toString() == charityId,
      );
      notifyListeners();
    } catch (_) {
      _error = 'Charity not found';
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>?> loadCharityProfile(String charityRef) async {
    final uri = Uri.parse('$_apiBaseUrl/api/golf/public/charities/$charityRef');
    final response = await http.get(uri);
    if (response.statusCode >= 400) {
      throw Exception(
          _extractError(response, 'Failed to load charity profile'));
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return _mapOrNull(data['charity']);
  }

  Future<Map<String, dynamic>?> getMyCharitySelection() async {
    try {
      final token = await _authToken();
      final uri = Uri.parse('$_apiBaseUrl/api/golf/me/charity-selection');
      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode >= 400) {
        return null;
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      _myCharitySelection = data;

      final id = data['charity_id']?.toString();
      if (id != null && id.isNotEmpty) {
        try {
          _selectedCharity = _charities.firstWhere(
            (c) => (c['id'] ?? '').toString() == id,
          );
        } catch (_) {
          _selectedCharity = _mapOrNull(data['charity']);
        }
      }
      notifyListeners();
      return data;
    } catch (_) {
      return null;
    }
  }

  Future<String?> getMyCharitySelectionId() async {
    final data = await getMyCharitySelection();
    final id = data?['charity_id']?.toString();
    if (id == null || id.isEmpty) return null;
    return id;
  }

  Future<void> saveMyCharitySelection({
    required String charityId,
    required double contributionPct,
  }) async {
    final token = await _authToken();
    final uri = Uri.parse('$_apiBaseUrl/api/golf/me/charity-selection');
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'charity_id': charityId,
        'contribution_pct': contributionPct,
      }),
    );
    if (response.statusCode >= 400) {
      throw Exception(
        _extractError(response, 'Failed to save charity preference'),
      );
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    _myCharitySelection = data;
    _selectedCharity = _mapOrNull(data['charity']) ??
        _charities.cast<Map<String, dynamic>?>().firstWhere(
              (c) => (c?['id'] ?? '').toString() == charityId,
              orElse: () => null,
            );
    notifyListeners();
  }

  Future<void> createCharity(
    String name,
    String description,
    String website,
  ) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final token = await _authToken();
      final slug = name
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
          .replaceAll(RegExp(r'^-+|-+$'), '');

      final uri = Uri.parse('$_apiBaseUrl/api/golf/admin/charities');
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'name': name,
          'slug': slug,
          'description': description,
          'website_url': website.isEmpty ? null : website,
        }),
      );

      if (response.statusCode >= 400) {
        throw Exception(_extractError(response, 'Create charity failed'));
      }

      await loadCharities();
      await loadAdminDonationLedger();
    } catch (e) {
      _error = e.toString();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateCharity({
    required String charityId,
    required String name,
    required String slug,
    required String description,
    required String website,
    required bool isActive,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final token = await _authToken();
      final uri = Uri.parse('$_apiBaseUrl/api/golf/admin/charities/$charityId');
      final response = await http.put(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'name': name.trim(),
          'slug': slug.trim().toLowerCase(),
          'description': description.trim(),
          'website_url': website.trim().isEmpty ? null : website.trim(),
          'is_active': isActive,
        }),
      );

      if (response.statusCode >= 400) {
        throw Exception(_extractError(response, 'Update charity failed'));
      }

      await loadCharities();
      await loadAdminDonationLedger();
    } catch (e) {
      _error = e.toString();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> deleteCharity(String charityId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final token = await _authToken();
      final uri = Uri.parse('$_apiBaseUrl/api/golf/admin/charities/$charityId');
      final response = await http.delete(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode >= 400) {
        throw Exception(_extractError(response, 'Delete charity failed'));
      }
      await loadCharities();
      await loadAdminDonationLedger();
    } catch (e) {
      _error = e.toString();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> createIndependentDonation({
    required String charityId,
    required double amountUsd,
    String paymentProvider = 'stripe_mock',
  }) async {
    final token = await _authToken();
    final uri = Uri.parse('$_apiBaseUrl/api/golf/me/charity-donations');
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'charity_id': charityId,
        'amount_cents': (amountUsd * 100).round(),
        'payment_provider': paymentProvider,
      }),
    );
    if (response.statusCode >= 400) {
      throw Exception(
        _extractError(response, 'Failed to create charity donation'),
      );
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    await loadCharities();
    return data;
  }

  Future<void> donateToCharity(String charityId, double amount) async {
    await createIndependentDonation(
      charityId: charityId,
      amountUsd: amount,
    );
  }

  Future<void> updateCharityFunds(String charityId, double amount) async {
    await donateToCharity(charityId, amount);
  }

  Future<Map<String, dynamic>> seedDefaultCharities() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final token = await _authToken();
      final uri =
          Uri.parse('$_apiBaseUrl/api/golf/admin/charities/seed-defaults');
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      if (response.statusCode >= 400) {
        throw Exception(_extractError(response, 'Seed charities failed'));
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      await loadCharities();
      await loadAdminDonationLedger();
      return data;
    } catch (e) {
      _error = e.toString();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadAdminDonationLedger({String? charityId}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final token = await _authToken();
      final uri =
          Uri.parse('$_apiBaseUrl/api/golf/admin/charities/donations').replace(
        queryParameters: {
          if ((charityId ?? '').trim().isNotEmpty)
            'charity_id': charityId!.trim(),
          'limit': '150',
        },
      );
      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode >= 400) {
        throw Exception(
          _extractError(response, 'Failed to load donations ledger'),
        );
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      _adminDonationSummary = _mapList(data['summary']);
      _adminDonationEntries = _mapList(data['donations']);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
