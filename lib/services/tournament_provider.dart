import 'dart:convert';
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';

class TournamentProvider with ChangeNotifier {
  bool _isLoading = false;
  String? _error;
  List<Map<String, dynamic>> _courses = [];
  Map<String, dynamic>? _activeRound;
  Map<String, dynamic>? _latestRating;
  Map<String, dynamic>? _latestMetrics;
  Map<String, dynamic>? _latestTeamDraw;
  List<Map<String, dynamic>> _fraudFlags = [];
  List<Map<String, dynamic>> _events = [];
  Map<String, dynamic>? _eventAccess;
  List<Map<String, dynamic>> _availablePlayers = [];
  List<Map<String, dynamic>> _sessions = [];
  List<Map<String, dynamic>> _inboxMessages = [];
  List<Map<String, dynamic>> _incomingFriendRequests = [];
  Map<String, dynamic>? _scoreboard;
  List<Map<String, dynamic>> _dashboardMyScores = [];
  List<Map<String, dynamic>> _dashboardLeaderboard = [];
  List<Map<String, dynamic>> _dashboardLiveEvents = [];
  List<Map<String, dynamic>> _dashboardJackpotWinners = [];
  List<Map<String, dynamic>> _dashboardWeeklyDrawWinners = [];
  DateTime? _dashboardGeneratedAt;

  bool get isLoading => _isLoading;
  String? get error => _error;
  List<Map<String, dynamic>> get courses => _courses;
  Map<String, dynamic>? get activeRound => _activeRound;
  Map<String, dynamic>? get latestRating => _latestRating;
  Map<String, dynamic>? get latestMetrics => _latestMetrics;
  Map<String, dynamic>? get latestTeamDraw => _latestTeamDraw;
  List<Map<String, dynamic>> get fraudFlags => _fraudFlags;
  List<Map<String, dynamic>> get events => _events;
  Map<String, dynamic>? get eventAccess => _eventAccess;
  List<Map<String, dynamic>> get availablePlayers => _availablePlayers;
  List<Map<String, dynamic>> get sessions => _sessions;
  List<Map<String, dynamic>> get inboxMessages => _inboxMessages;
  List<Map<String, dynamic>> get incomingFriendRequests =>
      _incomingFriendRequests;
  Map<String, dynamic>? get scoreboard => _scoreboard;
  List<Map<String, dynamic>> get dashboardMyScores => _dashboardMyScores;
  List<Map<String, dynamic>> get dashboardLeaderboard => _dashboardLeaderboard;
  List<Map<String, dynamic>> get dashboardLiveEvents => _dashboardLiveEvents;
  List<Map<String, dynamic>> get dashboardJackpotWinners =>
      _dashboardJackpotWinners;
  List<Map<String, dynamic>> get dashboardWeeklyDrawWinners =>
      _dashboardWeeklyDrawWinners;
  DateTime? get dashboardGeneratedAt => _dashboardGeneratedAt;
  int get unreadInboxCount => _inboxMessages
      .where((m) => (m['status'] ?? '').toString() == 'unread')
      .length;

  void clearError() {
    _error = null;
    notifyListeners();
  }

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

  Future<Map<String, dynamic>> _get(
    String path, {
    Map<String, String>? query,
  }) async {
    final token = await _authToken();
    final uri = Uri.parse('$_apiBaseUrl$path').replace(queryParameters: query);
    final response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode >= 400) {
      throw Exception(
          'Request failed (${response.statusCode}): ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _getPublic(
    String path, {
    Map<String, String>? query,
  }) async {
    final uri = Uri.parse('$_apiBaseUrl$path').replace(queryParameters: query);
    final response = await http.get(uri);
    if (response.statusCode >= 400) {
      throw Exception(
          'Request failed (${response.statusCode}): ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _post(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    final token = await _authToken();
    final uri = Uri.parse('$_apiBaseUrl$path').replace(queryParameters: query);
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(body ?? <String, dynamic>{}),
    );
    if (response.statusCode >= 400) {
      throw Exception(
          'Request failed (${response.statusCode}): ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _put(
    String path, {
    required Map<String, dynamic> body,
  }) async {
    final token = await _authToken();
    final uri = Uri.parse('$_apiBaseUrl$path');
    final response = await http.put(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(body),
    );
    if (response.statusCode >= 400) {
      throw Exception(
          'Request failed (${response.statusCode}): ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<void> loadCourses() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final body = await _get('/api/tournament/courses');
      _courses = List<Map<String, dynamic>>.from(body['courses'] ?? []);
    } catch (e) {
      _error = e.toString();
      _courses = [];
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> createCourse({
    required String name,
    required String location,
    required double courseRating,
    required int slopeRating,
    required int holesCount,
    int defaultPar = 4,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final body = await _post(
        '/api/tournament/courses',
        body: {
          'name': name,
          'location': location,
          'course_rating': courseRating,
          'slope_rating': slopeRating,
          'holes_count': holesCount,
          'default_par': defaultPar,
        },
      );
      await loadCourses();
      return body;
    } catch (e) {
      _error = e.toString();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> createEvent({
    required String title,
    required String eventType,
    required int minDonationCents,
    required DateTime startAt,
    required DateTime endAt,
    String description = '',
    String unlockMode = 'window_access',
    int? maxParticipants,
  }) async {
    final body = await _post(
      '/api/tournament/admin/events',
      body: {
        'title': title,
        'event_type': eventType,
        'description': description,
        'min_donation_cents': minDonationCents,
        'currency': 'USD',
        'unlock_mode': unlockMode,
        'start_at': startAt.toIso8601String(),
        'end_at': endAt.toIso8601String(),
        'max_participants': maxParticipants,
      },
    );
    await loadEvents();
    return body;
  }

  Future<void> loadEvents() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      Map<String, dynamic> body;
      if (FirebaseAuth.instance.currentUser == null) {
        body = await _getPublic('/api/tournament/public/events');
      } else {
        try {
          body = await _get('/api/tournament/events');
        } catch (_) {
          body = await _getPublic('/api/tournament/public/events');
        }
      }
      _events = List<Map<String, dynamic>>.from(body['events'] ?? []);
    } catch (e) {
      _error = e.toString();
      _events = [];
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadBootstrap({
    bool includePlayers = true,
    bool silent = false,
  }) async {
    if (!silent) {
      _isLoading = true;
      _error = null;
      notifyListeners();
    }
    try {
      Map<String, dynamic> body;
      try {
        body = await _get(
          '/api/tournament/bootstrap',
          query: {'include_players': includePlayers ? 'true' : 'false'},
        );
      } catch (e) {
        final message = e.toString().toLowerCase();
        final shouldRetry = message.contains('failed to fetch') ||
            message.contains('connection') ||
            message.contains('socket');
        if (!shouldRetry) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 650));
        body = await _get(
          '/api/tournament/bootstrap',
          query: {'include_players': includePlayers ? 'true' : 'false'},
        );
      }
      _events = List<Map<String, dynamic>>.from(body['events'] ?? []);
      _sessions = List<Map<String, dynamic>>.from(body['sessions'] ?? []);
      _inboxMessages = List<Map<String, dynamic>>.from(body['messages'] ?? []);
      _incomingFriendRequests = List<Map<String, dynamic>>.from(
        body['incoming_friend_requests'] ?? [],
      );
      if (includePlayers) {
        _availablePlayers =
            List<Map<String, dynamic>>.from(body['players'] ?? []);
      }
      _error = null;
    } catch (e) {
      final message = e.toString().toLowerCase();
      final shouldFallback = message.contains('failed to fetch') ||
          message.contains('connection') ||
          message.contains('socket') ||
          message.contains('401') ||
          message.contains('403');
      if (shouldFallback) {
        try {
          final publicBody = await _getPublic('/api/tournament/public/events');
          _events = List<Map<String, dynamic>>.from(publicBody['events'] ?? []);
          _sessions = [];
          _inboxMessages = [];
          _incomingFriendRequests = [];
          if (includePlayers) {
            _availablePlayers = [];
          }
          _error = null;
          return;
        } catch (_) {
          // Fall through to the existing error handling below.
        }
      }
      if (!silent) {
        _error = e.toString();
        rethrow;
      }
    } finally {
      if (!silent) {
        _isLoading = false;
      }
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> loadMyEventAccess(String eventId) async {
    final body = await _get('/api/tournament/events/$eventId/my-access');
    _eventAccess = body;
    notifyListeners();
    return body;
  }

  Future<Map<String, dynamic>> initiateEventDonation({
    required String eventId,
    required String phoneNumber,
    required int amountCents,
  }) async {
    return _post(
      '/api/tournament/events/$eventId/donate/initiate',
      body: {
        'phone_number': phoneNumber,
        'amount_cents': amountCents,
      },
    );
  }

  Future<Map<String, dynamic>> confirmEventDonation({
    required String eventId,
    required String checkoutRequestId,
  }) async {
    final body = await _post(
      '/api/tournament/events/$eventId/donate/confirm',
      body: {'checkout_request_id': checkoutRequestId},
    );
    await loadEvents();
    await loadMyEventAccess(eventId);
    return body;
  }

  Future<Map<String, dynamic>> joinEvent(String eventId) async {
    final body = await _post('/api/tournament/events/$eventId/join');
    await loadEvents();
    await loadMyEventAccess(eventId);
    return body;
  }

  Future<Map<String, dynamic>> manualStripeUnlock({
    required String eventId,
    required int amountCents,
    required String providerRef,
  }) async {
    final body = await _post(
      '/api/tournament/events/$eventId/unlock/manual',
      body: {
        'amount_cents': amountCents,
        'provider_ref': providerRef,
      },
    );
    await loadEvents();
    await loadMyEventAccess(eventId);
    return body;
  }

  Future<Map<String, dynamic>> walletUnlockEvent({
    required String eventId,
    required int amountCents,
    String? charityId,
  }) async {
    final body = await _post(
      '/api/tournament/events/$eventId/unlock/wallet',
      body: {
        'amount_cents': amountCents,
        if ((charityId ?? '').trim().isNotEmpty) 'charity_id': charityId,
      },
    );
    await loadEvents();
    await loadMyEventAccess(eventId);
    return body;
  }

  Future<Map<String, dynamic>> mockStripeCheckout({
    required String eventId,
    required int amountCents,
    required String charityId,
    required String email,
    required String cardNumber,
    required String exp,
    required String cvc,
  }) async {
    final normalizedCard = cardNumber.replaceAll(RegExp(r'\s+'), '');
    if (!email.contains('@')) {
      throw Exception('Invalid email.');
    }
    if (normalizedCard.length < 12) {
      throw Exception('Invalid card number.');
    }
    if (exp.trim().length < 4) {
      throw Exception('Invalid expiry date.');
    }
    if (cvc.trim().length < 3) {
      throw Exception('Invalid CVC.');
    }

    // Deterministic mock behavior for testing failure flows.
    // Any card ending in 0002 will simulate a declined card.
    if (normalizedCard.endsWith('0002')) {
      throw Exception('Card declined (mock).');
    }

    // Simulate a network payment gateway delay.
    await Future.delayed(const Duration(milliseconds: 850));

    return walletUnlockEvent(
      eventId: eventId,
      amountCents: amountCents,
      charityId: charityId,
    );
  }

  Future<void> loadAvailablePlayers() async {
    final body = await _get('/api/tournament/players/available');
    _availablePlayers = List<Map<String, dynamic>>.from(body['players'] ?? []);
    notifyListeners();
  }

  Future<Map<String, dynamic>> createSession({
    required String eventId,
    required DateTime scheduledAt,
    required List<int> invitedUserIds,
  }) async {
    final body = await _post(
      '/api/tournament/sessions',
      body: {
        'event_id': eventId,
        'scheduled_at': scheduledAt.toIso8601String(),
        'invited_user_ids': invitedUserIds,
      },
    );
    await loadMySessions();
    await loadInbox();
    return body;
  }

  Future<Map<String, dynamic>> startSession(String sessionId) async {
    final body = await _post('/api/tournament/sessions/$sessionId/start');
    await loadMySessions();
    return body;
  }

  Future<Map<String, dynamic>> endSession(String sessionId) async {
    final body = await _post('/api/tournament/sessions/$sessionId/end');
    await loadMySessions();
    return body;
  }

  Future<void> loadMySessions() async {
    final body = await _get('/api/tournament/sessions/mine');
    _sessions = List<Map<String, dynamic>>.from(body['sessions'] ?? []);
    notifyListeners();
  }

  Future<void> loadInbox() async {
    final body = await _get('/api/tournament/inbox');
    _inboxMessages = List<Map<String, dynamic>>.from(body['messages'] ?? []);
    notifyListeners();
  }

  Future<Map<String, dynamic>> markInboxSeen() async {
    final body = await _post('/api/tournament/inbox/mark-seen');
    await loadInbox();
    return body;
  }

  Future<Map<String, dynamic>> clearInbox() async {
    final body = await _post('/api/tournament/inbox/clear');
    await loadInbox();
    return body;
  }

  Future<void> loadIncomingFriendRequests() async {
    final body = await _get('/api/tournament/friends/requests/incoming');
    _incomingFriendRequests =
        List<Map<String, dynamic>>.from(body['requests'] ?? []);
    notifyListeners();
  }

  Future<Map<String, dynamic>> sendFriendRequest({
    required int receiverUserId,
  }) async {
    final body = await _post(
      '/api/tournament/friends/requests',
      body: {'receiver_user_id': receiverUserId},
    );
    await loadAvailablePlayers();
    await loadIncomingFriendRequests();
    return body;
  }

  Future<Map<String, dynamic>> actionFriendRequest({
    required String requestId,
    required String action,
  }) async {
    final body = await _post(
      '/api/tournament/friends/requests/$requestId/action',
      body: {'action': action},
    );
    await loadAvailablePlayers();
    await loadIncomingFriendRequests();
    return body;
  }

  Future<Map<String, dynamic>> actionInboxMessage({
    required String messageId,
    required String action,
  }) async {
    final body = await _post(
      '/api/tournament/inbox/$messageId/action',
      body: {'action': action},
    );
    await loadInbox();
    await loadMySessions();
    return body;
  }

  Future<Map<String, dynamic>> submitSessionScore({
    required String sessionId,
    required int totalScore,
    int? holesPlayed,
    List<int> holeScores = const [],
    int? totalPutts,
    int? girCount,
    int? fairwaysHitCount,
    int? penaltiesTotal,
    String? notes,
    int? markerUserId,
  }) async {
    final body = await _post(
      '/api/tournament/sessions/$sessionId/scores',
      body: {
        'total_score': totalScore,
        'holes_played': holesPlayed,
        'hole_scores': holeScores,
        'total_putts': totalPutts,
        'gir_count': girCount,
        'fairways_hit_count': fairwaysHitCount,
        'penalties_total': penaltiesTotal,
        'notes': notes,
        'marker_user_id': markerUserId,
      },
    );
    await loadInbox();
    return body;
  }

  Future<Map<String, dynamic>> confirmScore(String scoreId) async {
    final body = await _post('/api/tournament/scores/$scoreId/confirm');
    await loadInbox();
    return body;
  }

  Future<Map<String, dynamic>> rejectScore({
    required String scoreId,
    String? reason,
  }) async {
    final body = await _post(
      '/api/tournament/scores/$scoreId/reject',
      body: {'reason': reason},
    );
    await loadInbox();
    return body;
  }

  Future<Map<String, dynamic>> loadScoreboard(String sessionId) async {
    final body = await _get('/api/tournament/sessions/$sessionId/scoreboard');
    _scoreboard = body;
    notifyListeners();
    return body;
  }

  Future<Map<String, dynamic>> createRound({
    required String courseId,
    required DateTime playedAt,
    required String roundType,
    int? markerUserId,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final body = await _post(
        '/api/tournament/rounds',
        body: {
          'course_id': courseId,
          'played_at': playedAt.toIso8601String(),
          'round_type': roundType,
          'marker_user_id': markerUserId,
          'source': 'manual',
        },
      );
      await getRoundDetail(body['id'].toString());
      return body;
    } catch (e) {
      _error = e.toString();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> upsertRoundHole({
    required String roundId,
    required int holeNumber,
    required int par,
    required int strokes,
    required int putts,
    required bool gir,
    required bool sandSave,
    bool? fairwayHit,
    int penalties = 0,
  }) async {
    await _put(
      '/api/tournament/rounds/$roundId/holes/$holeNumber',
      body: {
        'par': par,
        'strokes': strokes,
        'putts': putts,
        'fairway_hit': fairwayHit,
        'gir': gir,
        'sand_save': sandSave,
        'penalties': penalties,
      },
    );
  }

  Future<Map<String, dynamic>> getRoundDetail(String roundId) async {
    final body = await _get('/api/tournament/rounds/$roundId');
    _activeRound = body;
    notifyListeners();
    return body;
  }

  Future<Map<String, dynamic>> submitRound({
    required String roundId,
    required int markerUserId,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final body = await _post(
        '/api/tournament/rounds/$roundId/submit',
        body: {'marker_user_id': markerUserId},
      );
      await getRoundDetail(roundId);
      return body;
    } catch (e) {
      _error = e.toString();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> markerConfirmRound(String roundId) async {
    final body = await _post('/api/tournament/rounds/$roundId/marker-confirm');
    await getRoundDetail(roundId);
    return body;
  }

  Future<Map<String, dynamic>> rejectRound({
    required String roundId,
    required String reason,
  }) async {
    final body = await _post(
      '/api/tournament/rounds/$roundId/reject',
      body: {'reason': reason},
    );
    await getRoundDetail(roundId);
    return body;
  }

  Future<Map<String, dynamic>> lockRound({
    required String roundId,
    String reason = 'admin_lock',
  }) async {
    final body = await _post(
      '/api/tournament/rounds/$roundId/lock',
      body: {'reason': reason},
    );
    await getRoundDetail(roundId);
    return body;
  }

  Future<Map<String, dynamic>> recomputeRating({int? userId}) async {
    final query = userId == null ? null : {'user_id': '$userId'};
    final body = await _post('/api/tournament/ratings/recompute', query: query);
    return body;
  }

  Future<Map<String, dynamic>> loadMyRating(int userId) async {
    final body = await _get('/api/tournament/players/$userId/rating');
    _latestRating = body;
    notifyListeners();
    return body;
  }

  Future<Map<String, dynamic>> loadCurrentUserRating() async {
    final body = await _get('/api/tournament/me/rating');
    _latestRating = body;
    notifyListeners();
    return body;
  }

  Future<Map<String, dynamic>> loadMyMetrics(int userId) async {
    final body = await _get('/api/tournament/players/$userId/metrics');
    _latestMetrics = body;
    notifyListeners();
    return body;
  }

  Future<Map<String, dynamic>> loadCurrentUserMetrics() async {
    final body = await _get('/api/tournament/me/metrics');
    _latestMetrics = body;
    notifyListeners();
    return body;
  }

  Future<Map<String, dynamic>> loadTrustScore(int userId) async {
    final body = await _get('/api/tournament/players/$userId/trust-score');
    return body;
  }

  Future<Map<String, dynamic>> loadCurrentUserTrustScore() async {
    return _get('/api/tournament/me/trust-score');
  }

  Future<Map<String, dynamic>> loadFraudFlags({String? statusFilter}) async {
    final query = statusFilter == null ? null : {'status': statusFilter};
    final body = await _get('/api/tournament/fraud-flags', query: query);
    _fraudFlags = List<Map<String, dynamic>>.from(body['flags'] ?? []);
    notifyListeners();
    return body;
  }

  Future<Map<String, dynamic>> generateTeamDraw({
    required String eventKey,
    required int teamSize,
    required List<int> userIds,
  }) async {
    final body = await _post(
      '/api/tournament/team-draw/generate',
      body: {
        'event_key': eventKey,
        'team_size': teamSize,
        'user_ids': userIds,
        'algorithm': 'balanced_sum',
      },
    );
    _latestTeamDraw = body;
    notifyListeners();
    return body;
  }

  Future<Map<String, dynamic>> loadTeamDraw(String runId) async {
    final body = await _get('/api/tournament/team-draw/$runId');
    _latestTeamDraw = body;
    notifyListeners();
    return body;
  }

  Future<void> loadDashboardBootstrap({bool silent = false}) async {
    if (!silent) {
      _isLoading = true;
      _error = null;
      notifyListeners();
    }
    try {
      Map<String, dynamic> body;
      try {
        body = await _get('/api/tournament/dashboard/bootstrap');
      } catch (e) {
        final message = e.toString().toLowerCase();
        final shouldRetry = message.contains('failed to fetch') ||
            message.contains('connection') ||
            message.contains('socket');
        if (!shouldRetry) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 500));
        body = await _get('/api/tournament/dashboard/bootstrap');
      }
      _dashboardMyScores =
          List<Map<String, dynamic>>.from(body['my_scores'] ?? []);
      _dashboardLeaderboard =
          List<Map<String, dynamic>>.from(body['leaderboard'] ?? []);
      _dashboardLiveEvents =
          List<Map<String, dynamic>>.from(body['live_events'] ?? []);
      _dashboardJackpotWinners =
          List<Map<String, dynamic>>.from(body['jackpot_winners'] ?? []);
      _dashboardWeeklyDrawWinners =
          List<Map<String, dynamic>>.from(body['weekly_draw_winners'] ?? []);
      final generatedRaw = body['generated_at']?.toString();
      _dashboardGeneratedAt =
          generatedRaw == null ? null : DateTime.tryParse(generatedRaw);
      _error = null;
    } catch (e) {
      if (!silent) {
        _error = e.toString();
        rethrow;
      }
    } finally {
      if (!silent) {
        _isLoading = false;
      }
      notifyListeners();
    }
  }
}
