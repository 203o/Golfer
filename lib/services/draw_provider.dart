import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';

class DrawProvider with ChangeNotifier {
  bool _isLoading = false;
  String? _error;
  List<Map<String, dynamic>> _draws = [];
  Map<String, dynamic>? _currentDraw;
  Map<String, dynamic>? _lastRunResult;
  Map<String, dynamic>? _drawSettings;
  List<Map<String, dynamic>> _myDrawResults = [];
  Map<String, dynamic>? _latestWeekly;
  Map<String, dynamic>? _latestMonthly;
  List<Map<String, dynamic>> _adminWinnerClaims = [];
  List<Map<String, dynamic>> _adminWinners = [];
  Map<String, dynamic>? _adminReportSummary;

  bool get isLoading => _isLoading;
  String? get error => _error;
  List<Map<String, dynamic>> get draws => _draws;
  Map<String, dynamic>? get currentDraw => _currentDraw;
  Map<String, dynamic>? get lastRunResult => _lastRunResult;
  Map<String, dynamic>? get drawSettings => _drawSettings;
  List<Map<String, dynamic>> get myDrawResults => _myDrawResults;
  Map<String, dynamic>? get latestWeekly => _latestWeekly;
  Map<String, dynamic>? get latestMonthly => _latestMonthly;
  List<Map<String, dynamic>> get adminWinnerClaims => _adminWinnerClaims;
  List<Map<String, dynamic>> get adminWinners => _adminWinners;
  Map<String, dynamic>? get adminReportSummary => _adminReportSummary;

  int get totalEntries => _draws.fold(
      0, (sum, draw) => sum + ((draw['entries_count'] ?? 0) as int));

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
    } catch (_) {
      // Fallback to generic message if response body is not JSON.
    }
    return '$fallback (${response.statusCode})';
  }

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

  Future<void> loadDraws() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await Future.wait([
        loadCurrentDraw(),
        loadMyDrawSummary(),
      ]);
      _draws = _currentDraw == null ? [] : [_currentDraw!];
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadAdminDraws() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final token = await _authToken();
      final uri = Uri.parse('$_apiBaseUrl/api/golf/admin/draws');
      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode >= 400) {
        throw Exception(_extractError(response, 'Failed to load admin draws'));
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      _draws = List<Map<String, dynamic>>.from(body['draws'] ?? const []);
      _drawSettings = body['settings'] as Map<String, dynamic>?;
      await Future.wait([
        loadWinnerClaims(),
        loadFullWinners(),
        loadAdminReportSummary(),
      ]);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadWinnerClaims({
    String? reviewStatus,
    String? payoutState,
  }) async {
    final token = await _authToken();
    final params = <String, String>{};
    if ((reviewStatus ?? '').trim().isNotEmpty) {
      params['review_status'] = reviewStatus!.trim();
    }
    if ((payoutState ?? '').trim().isNotEmpty) {
      params['payout_state'] = payoutState!.trim();
    }
    final uri = Uri.parse('$_apiBaseUrl/api/golf/admin/winner-claims')
        .replace(queryParameters: params.isEmpty ? null : params);
    final response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode >= 400) {
      throw Exception(_extractError(response, 'Failed to load winner claims'));
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    _adminWinnerClaims =
        List<Map<String, dynamic>>.from(body['claims'] ?? const []);
    notifyListeners();
  }

  Future<void> loadFullWinners({int limit = 400}) async {
    final token = await _authToken();
    final uri = Uri.parse('$_apiBaseUrl/api/golf/admin/winners')
        .replace(queryParameters: {'limit': '$limit'});
    final response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode >= 400) {
      throw Exception(_extractError(response, 'Failed to load winners list'));
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    _adminWinners = List<Map<String, dynamic>>.from(body['items'] ?? const []);
    notifyListeners();
  }

  Future<void> loadAdminReportSummary() async {
    final token = await _authToken();
    final uri = Uri.parse('$_apiBaseUrl/api/golf/admin/reports/summary');
    final response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode >= 400) {
      throw Exception(_extractError(response, 'Failed to load report summary'));
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    _adminReportSummary = body;
    notifyListeners();
  }

  Future<void> reviewWinnerClaim({
    required String claimId,
    required String action,
    String? reviewNotes,
  }) async {
    final token = await _authToken();
    final uri =
        Uri.parse('$_apiBaseUrl/api/golf/admin/winner-claims/$claimId/review');
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'action': action,
        if ((reviewNotes ?? '').trim().isNotEmpty)
          'review_notes': reviewNotes!.trim(),
      }),
    );
    if (response.statusCode >= 400) {
      throw Exception(_extractError(response, 'Failed to review winner claim'));
    }
    await loadWinnerClaims();
    await loadFullWinners();
    await loadAdminReportSummary();
  }

  Future<void> markClaimPaid({
    required String claimId,
    required String payoutReference,
  }) async {
    final token = await _authToken();
    final uri = Uri.parse(
        '$_apiBaseUrl/api/golf/admin/winner-claims/$claimId/mark-paid');
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'payout_reference': payoutReference.trim()}),
    );
    if (response.statusCode >= 400) {
      throw Exception(
          _extractError(response, 'Failed to mark payout completed'));
    }
    await loadWinnerClaims();
    await loadFullWinners();
    await loadAdminReportSummary();
  }

  Future<void> loadMyDrawSummary() async {
    try {
      final token = await _authToken();
      final uri = Uri.parse('$_apiBaseUrl/api/golf/me/draws/summary');
      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode >= 400) {
        throw Exception('Failed to load draw summary (${response.statusCode})');
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      _myDrawResults =
          List<Map<String, dynamic>>.from(body['items'] ?? const []);
      _latestWeekly = body['latest_weekly'] as Map<String, dynamic>?;
      _latestMonthly = body['latest_monthly'] as Map<String, dynamic>?;
    } catch (_) {
      _myDrawResults = [];
      _latestWeekly = null;
      _latestMonthly = null;
    } finally {
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> submitWinnerClaim({
    required String entryId,
    required String proofUrl,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final token = await _authToken();
      final uri = Uri.parse('$_apiBaseUrl/api/golf/me/winner-claims/$entryId');
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'proof_url': proofUrl.trim()}),
      );
      if (response.statusCode >= 400) {
        throw Exception(_extractError(response, 'Failed to submit proof'));
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      await loadMyDrawSummary();
      return body;
    } catch (e) {
      _error = e.toString();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadCurrentDraw() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final uri = Uri.parse('$_apiBaseUrl/api/golf/public/overview');
      final response = await http.get(uri);

      if (response.statusCode >= 400) {
        throw Exception('Failed to load draw (${response.statusCode})');
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      _currentDraw = body['current_draw'] as Map<String, dynamic>?;
    } catch (e) {
      _error = e.toString();
      _currentDraw = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> enterDraw({
    required int score,
    required String courseName,
    required DateTime playedOn,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final token = await _authToken();
      final uri = Uri.parse('$_apiBaseUrl/api/golf/me/scores');
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'course_name': courseName,
          'score': score,
          'played_on': playedOn.toIso8601String().split('T').first,
        }),
      );

      if (response.statusCode >= 400) {
        throw Exception('Score submission failed (${response.statusCode})');
      }

      await loadCurrentDraw();
    } catch (e) {
      _error = e.toString();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> createDraw(String _, String __, DateTime drawDate) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final token = await _authToken();
      final monthKey =
          '${drawDate.year.toString().padLeft(4, '0')}-${drawDate.month.toString().padLeft(2, '0')}';
      final uri = Uri.parse('$_apiBaseUrl/api/golf/admin/draws');
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'month_key': monthKey, 'jackpot_carry_in_cents': 0}),
      );

      if (response.statusCode >= 400) {
        throw Exception(_extractError(response, 'Create draw failed'));
      }

      await loadAdminDraws();
    } catch (e) {
      _error = e.toString();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadDrawSettings() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final token = await _authToken();
      final uri = Uri.parse('$_apiBaseUrl/api/golf/admin/draw-settings');
      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode >= 400) {
        throw Exception(
            _extractError(response, 'Failed to load draw settings'));
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      _drawSettings = body['settings'] as Map<String, dynamic>?;
    } catch (e) {
      _error = e.toString();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> updateDrawSettings({
    required int weeklyPrizeCents,
    required int monthlyFirstPrizeCents,
    required int monthlySecondPrizeCents,
    required int monthlyThirdPrizeCents,
    required int monthlyMinEventsRequired,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final token = await _authToken();
      final uri = Uri.parse('$_apiBaseUrl/api/golf/admin/draw-settings');
      final response = await http.put(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'weekly_prize_cents': weeklyPrizeCents,
          'monthly_first_prize_cents': monthlyFirstPrizeCents,
          'monthly_second_prize_cents': monthlySecondPrizeCents,
          'monthly_third_prize_cents': monthlyThirdPrizeCents,
          'monthly_min_events_required': monthlyMinEventsRequired,
        }),
      );

      if (response.statusCode >= 400) {
        throw Exception(_extractError(response, 'Update draw settings failed'));
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      _drawSettings = body['settings'] as Map<String, dynamic>?;
      await loadAdminDraws();
      return body;
    } catch (e) {
      _error = e.toString();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> selectWinner(String drawId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final token = await _authToken();
      final uri = Uri.parse('$_apiBaseUrl/api/golf/admin/draws/$drawId/run');
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({}),
      );

      if (response.statusCode >= 400) {
        throw Exception(_extractError(response, 'Run draw failed'));
      }

      _lastRunResult = jsonDecode(response.body) as Map<String, dynamic>;
      await loadAdminDraws();
    } catch (e) {
      _error = e.toString();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> simulateDraw({
    required String drawId,
    required String logicMode,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final token = await _authToken();
      final uri =
          Uri.parse('$_apiBaseUrl/api/golf/admin/draws/$drawId/simulate');
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'logic_mode': logicMode}),
      );

      if (response.statusCode >= 400) {
        throw Exception(_extractError(response, 'Draw simulation failed'));
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      _lastRunResult = body;
      await loadAdminDraws();
      return body;
    } catch (e) {
      _error = e.toString();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> publishDraw(String drawId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final token = await _authToken();
      final uri =
          Uri.parse('$_apiBaseUrl/api/golf/admin/draws/$drawId/publish');
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode >= 400) {
        throw Exception(_extractError(response, 'Draw publish failed'));
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      _lastRunResult = body;
      await loadAdminDraws();
      return body;
    } catch (e) {
      _error = e.toString();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> runFairDraw({
    required String drawKind,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final token = await _authToken();
      final uri = Uri.parse('$_apiBaseUrl/api/golf/admin/draws/run-fair');
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'draw_kind': drawKind}),
      );

      if (response.statusCode >= 400) {
        throw Exception(_extractError(response, 'Run fair draw failed'));
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      _lastRunResult = body;
      await loadAdminDraws();
      return body;
    } catch (e) {
      _error = e.toString();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
