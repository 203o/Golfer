// ignore_for_file: use_build_context_synchronously

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_provider.dart';
import '../services/charity_provider.dart';
import '../services/tournament_provider.dart';
import '../widgets/app_skeleton.dart';
import '../widgets/top_navigation_bar.dart';
import 'landing_screen.dart';
import 'user_dashboard_screen.dart';

class TournamentPlayerScreen extends StatefulWidget {
  const TournamentPlayerScreen({super.key});

  @override
  State<TournamentPlayerScreen> createState() => _TournamentPlayerScreenState();
}

class _TournamentPlayerScreenState extends State<TournamentPlayerScreen> {
  static const double _maxContentWidth = 1120;
  DateTime _scheduledAt = DateTime.now().add(const Duration(days: 1));
  String? _selectedUnlockedEventId;
  String? _selectedCharityId;
  String? _selectedSessionId;
  String _playerQuery = '';
  final TextEditingController _scoreController = TextEditingController();
  final TextEditingController _holesPlayedController = TextEditingController(
    text: '18',
  );
  final TextEditingController _puttsController = TextEditingController();
  final TextEditingController _girController = TextEditingController();
  final TextEditingController _fairwaysController = TextEditingController();
  final TextEditingController _penaltiesController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final Set<int> _selectedInvitees = <int>{};
  bool _busy = false;
  int _tabIndex = 0; // 0 Events, 1 Setup Challenge, 2 My Sessions, 3 Inbox
  bool _silentRefreshing = false;
  bool _hardBootstrapLoading = false;
  Timer? _inboxPollTimer;
  bool _markingInboxSeen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _reloadAll();
    });
    _inboxPollTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      _refreshInboxSilent();
    });
  }

  @override
  void dispose() {
    _inboxPollTimer?.cancel();
    _scoreController.dispose();
    _holesPlayedController.dispose();
    _puttsController.dispose();
    _girController.dispose();
    _fairwaysController.dispose();
    _penaltiesController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _reloadAll() async {
    final provider = context.read<TournamentProvider>();
    final charityProvider = context.read<CharityProvider>();
    if (mounted && !_busy) {
      setState(() => _hardBootstrapLoading = true);
    }
    try {
      await Future.wait([
        provider.loadBootstrap(includePlayers: true),
        charityProvider.loadCharities(),
      ]);
      final charities = charityProvider.charities
          .where((c) => c['is_active'] != false)
          .toList();
      String? selectedCharity = _selectedCharityId;
      if ((selectedCharity ?? '').isEmpty && charities.isNotEmpty) {
        selectedCharity = await charityProvider.getMyCharitySelectionId();
        selectedCharity ??= charities.first['id']?.toString();
      }
      final availableEvents = provider.events;
      if (availableEvents.isNotEmpty && mounted) {
        setState(() {
          _selectedUnlockedEventId ??= availableEvents.first['id']?.toString();
          _selectedCharityId = charities.any(
            (c) => c['id']?.toString() == selectedCharity,
          )
              ? selectedCharity
              : (charities.isNotEmpty
                  ? charities.first['id']?.toString()
                  : null);
        });
      } else if (mounted) {
        setState(() {
          _selectedCharityId = charities.any(
            (c) => c['id']?.toString() == selectedCharity,
          )
              ? selectedCharity
              : (charities.isNotEmpty
                  ? charities.first['id']?.toString()
                  : null);
        });
      }
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() => _hardBootstrapLoading = false);
      }
    }
  }

  Future<void> _refreshInboxSilent() async {
    if (!mounted || _silentRefreshing) return;
    final auth = context.read<AuthProvider>();
    if (!auth.isAuthenticated) return;
    _silentRefreshing = true;
    try {
      final provider = context.read<TournamentProvider>();
      await provider.loadBootstrap(includePlayers: false, silent: true);
    } catch (_) {
      // Ignore polling failures; user can still manual refresh.
    } finally {
      _silentRefreshing = false;
    }
  }

  Future<void> _refreshPlayers() async {
    setState(() => _busy = true);
    try {
      await context.read<TournamentProvider>().loadBootstrap(
            includePlayers: true,
            silent: true,
          );
      _snack('Players list refreshed');
    } catch (_) {
      _snack('Unable to refresh players right now.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onOpenInboxTab() async {
    if (!mounted || _markingInboxSeen) return;
    _markingInboxSeen = true;
    try {
      await context.read<TournamentProvider>().markInboxSeen();
    } catch (_) {
      // Ignore transient errors.
    } finally {
      _markingInboxSeen = false;
    }
  }

  Future<void> _clearInbox() async {
    setState(() => _busy = true);
    try {
      final body = await context.read<TournamentProvider>().clearInbox();
      final cleared = (body['cleared_count'] ?? 0).toString();
      _snack('Inbox cleared ($cleared)');
    } catch (e) {
      _snack('Clear inbox failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _onNavTap(TopNavItem item) {
    final auth = context.read<AuthProvider>();
    if (!auth.isAuthenticated && item != TopNavItem.jackpot) {
      _snack('Please sign in to continue.');
      return;
    }

    Widget screen;
    switch (item) {
      case TopNavItem.jackpot:
        screen = const LandingScreen();
      case TopNavItem.draw:
        screen = const UserDashboardScreen(initialView: DashboardView.draw);
      case TopNavItem.charityTournaments:
        screen = const TournamentPlayerScreen();
      case TopNavItem.dashboard:
        screen =
            const UserDashboardScreen(initialView: DashboardView.dashboard);
    }

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => screen),
      (route) => false,
    );
  }

  Future<void> _openStripePopup({
    required String eventId,
    required int amountCents,
    required String eventTitle,
    required String charityId,
    required String charityName,
  }) async {
    var processing = false;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) => AlertDialog(
            backgroundColor: Colors.white,
            title: const Text('Optional Event Donation'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$eventTitle • Donate \$${(amountCents / 100).toStringAsFixed(2)} from wallet',
                    style: const TextStyle(color: Color(0xFF607289)),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Charity: $charityName',
                    style: const TextStyle(
                      color: Color(0xFF1B5D86),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'This donation is optional and supports the selected charity.',
                    style: TextStyle(color: Color(0xFF607289)),
                  ),
                  if (processing) ...[
                    const SizedBox(height: 14),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 10),
                        Text(
                          'Sending donation...',
                          style: TextStyle(color: Color(0xFF607289)),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: processing ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: processing
                    ? null
                    : () async {
                        setModalState(() => processing = true);
                        try {
                          await context
                              .read<TournamentProvider>()
                              .mockStripeCheckout(
                                eventId: eventId,
                                amountCents: amountCents,
                                charityId: charityId,
                                email: 'wallet@local.mock',
                                cardNumber: '4242424242424242',
                                exp: '12/34',
                                cvc: '123',
                              );
                          if (!mounted) return;
                          Navigator.pop(context);
                          await _reloadAll();
                          if (!mounted) return;
                          setState(() => _tabIndex = 1);
                          _snack(
                            'Donation received. Continue in Setup Challenge.',
                          );
                        } catch (e) {
                          if (!mounted) return;
                          setModalState(() => processing = false);
                          _snack('Payment failed: $e');
                        }
                      },
                child: Text(
                  processing
                      ? 'Processing...'
                      : 'Donate \$${(amountCents / 100).toStringAsFixed(2)}',
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _createSession() async {
    final eventId = _selectedUnlockedEventId;
    final provider = context.read<TournamentProvider>();
    final selectedEvent = provider.events.cast<Map<String, dynamic>>().firstWhere(
          (e) => e['id']?.toString() == eventId,
          orElse: () => <String, dynamic>{},
        );
    final selectedEventType =
        (selectedEvent['event_type'] ?? '').toString().toLowerCase();
    if (eventId == null) {
      _snack('Choose an event first');
      return;
    }
    if (selectedEventType == 'solo' && _selectedInvitees.isNotEmpty) {
      _snack('Solo events do not need invited players');
      return;
    }
    if (selectedEventType == 'one_on_one' && _selectedInvitees.length != 1) {
      _snack('1v1 requires exactly one invited player');
      return;
    }
    setState(() => _busy = true);
    try {
      await provider.createSession(
            eventId: eventId,
            scheduledAt: _scheduledAt.toUtc(),
            invitedUserIds:
                selectedEventType == 'solo' ? const [] : _selectedInvitees.toList(),
          );
      _selectedInvitees.clear();
      await _reloadAll();
      _snack(
        selectedEventType == 'solo' ? 'Solo session created' : 'Challenge created',
      );
    } catch (e) {
      _snack('Create challenge failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _actionMessage(String messageId, String action) async {
    setState(() => _busy = true);
    try {
      await context
          .read<TournamentProvider>()
          .actionInboxMessage(messageId: messageId, action: action);
      await _reloadAll();
      if (action == 'accept') {
        setState(() => _tabIndex = 2);
        _snack('Invite accepted. Continue in My Sessions.');
      } else {
        _snack('Invite $action');
      }
    } catch (e) {
      _snack('Action failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _actionFriendRequest(String requestId, String action) async {
    setState(() => _busy = true);
    try {
      await context.read<TournamentProvider>().actionFriendRequest(
            requestId: requestId,
            action: action,
          );
      await _reloadAll();
      _snack(action == "accept"
          ? 'Friend request accepted'
          : 'Friend request declined');
    } catch (e) {
      _snack('Friend request action failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendFriendRequest(int receiverUserId) async {
    setState(() => _busy = true);
    try {
      await context
          .read<TournamentProvider>()
          .sendFriendRequest(receiverUserId: receiverUserId);
      await _reloadAll();
      _snack('Friend request sent');
    } catch (e) {
      _snack('Unable to send friend request: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmScore(String scoreId) async {
    setState(() => _busy = true);
    try {
      await context.read<TournamentProvider>().confirmScore(scoreId);
      await _reloadAll();
      _snack('Score confirmed');
    } catch (e) {
      _snack('Confirm failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startSession() async {
    final sessionId = _selectedSessionId;
    if (sessionId == null) return;
    setState(() => _busy = true);
    try {
      await context.read<TournamentProvider>().startSession(sessionId);
      await _reloadAll();
      _snack('Session started. Auto-close set to 48 hours.');
    } catch (e) {
      _snack('Start failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _endSession() async {
    final sessionId = _selectedSessionId;
    if (sessionId == null) return;
    setState(() => _busy = true);
    try {
      await context.read<TournamentProvider>().endSession(sessionId);
      await _reloadAll();
      _snack('Session ended.');
    } catch (e) {
      _snack('End failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitSessionScore() async {
    final sessionId = _selectedSessionId;
    final score = int.tryParse(_scoreController.text.trim());
    final holesPlayed = int.tryParse(_holesPlayedController.text.trim());
    final totalPutts = int.tryParse(_puttsController.text.trim());
    final girCount = int.tryParse(_girController.text.trim());
    final fairwaysHitCount = int.tryParse(_fairwaysController.text.trim());
    final penaltiesTotal = int.tryParse(_penaltiesController.text.trim());
    if (sessionId == null) {
      _snack('Select a session');
      return;
    }
    if (score == null) {
      _snack('Enter a valid score');
      return;
    }
    if (holesPlayed != null && holesPlayed != 9 && holesPlayed != 18) {
      _snack('Holes played must be 9 or 18');
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<TournamentProvider>().submitSessionScore(
            sessionId: sessionId,
            totalScore: score,
            holesPlayed: holesPlayed,
            totalPutts: totalPutts,
            girCount: girCount,
            fairwaysHitCount: fairwaysHitCount,
            penaltiesTotal: penaltiesTotal,
            notes: _notesController.text.trim(),
          );
      _scoreController.clear();
      _puttsController.clear();
      _girController.clear();
      _fairwaysController.clear();
      _penaltiesController.clear();
      _notesController.clear();
      await _reloadAll();
      _snack('Score recorded');
    } catch (e) {
      _snack('Submit failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadSessionScoreboard() async {
    final sessionId = _selectedSessionId;
    if (sessionId == null) {
      _snack('Select a session');
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<TournamentProvider>().loadScoreboard(sessionId);
    } catch (e) {
      _snack('Load scoreboard failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rejectScore(String scoreId) async {
    final reasonController = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject Score'),
        content: TextField(
          controller: reasonController,
          decoration: const InputDecoration(labelText: 'Reason'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              setState(() => _busy = true);
              try {
                await context.read<TournamentProvider>().rejectScore(
                      scoreId: scoreId,
                      reason: reasonController.text.trim(),
                    );
                await _reloadAll();
                _snack('Score rejected');
              } catch (e) {
                _snack('Reject failed: $e');
              } finally {
                if (mounted) setState(() => _busy = false);
              }
            },
            child: const Text('Reject'),
          ),
        ],
      ),
    );
  }

  Widget _localNavBar() {
    final provider = context.watch<TournamentProvider>();
    final inboxUnread = provider.unreadInboxCount;
    final inboxCount = inboxUnread;
    final items = [
      (label: 'Events', icon: Icons.event_available_outlined, count: 0),
      (label: 'Setup Challenge', icon: Icons.build_circle_outlined, count: 0),
      (label: 'My Sessions', icon: Icons.event_note_outlined, count: 0),
      (label: 'Inbox', icon: Icons.mail_outline, count: inboxCount),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: List.generate(items.length, (index) {
            final item = items[index];
            final selected = _tabIndex == index;
            return InkWell(
              onTap: () {
                setState(() => _tabIndex = index);
                if (index == 3) {
                  _onOpenInboxTab();
                }
              },
              borderRadius: BorderRadius.circular(999),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: selected
                      ? const Color(0xFFE1F1FB)
                      : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: selected
                        ? const Color(0xFF9CC8E0)
                        : const Color(0xFFD7E0EA),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      item.icon,
                      size: 16,
                      color: const Color(0xFFD4AF37),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      item.label,
                      style: TextStyle(
                        color: selected
                            ? const Color(0xFF1B5D86)
                            : const Color(0xFF607289),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (item.count > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1B5D86),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${item.count}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  bool get _showSetupSkeleton => _tabIndex == 1 && _hardBootstrapLoading;
  bool get _showMySessionsSkeleton => _tabIndex == 2 && _hardBootstrapLoading;
  bool get _showInboxSkeleton => _tabIndex == 3 && _hardBootstrapLoading;
  bool get _showEventsSkeleton => _tabIndex == 0 && _hardBootstrapLoading;

  Widget _skeletonLine({
    required double height,
    double? width,
    double radius = 10,
  }) {
    return AppShimmer(
      child: AppSkeletonBox(
        width: width,
        height: height,
        radius: radius,
      ),
    );
  }

  Widget _skeletonField() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _skeletonLine(height: 12, width: 160, radius: 6),
          const SizedBox(height: 6),
          _skeletonLine(height: 54, radius: 12),
        ],
      ),
    );
  }

  Widget _setupChallengeSkeleton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _skeletonField(),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(child: _skeletonLine(height: 16, width: 210, radius: 6)),
            const SizedBox(width: 8),
            _skeletonLine(height: 34, width: 140, radius: 999),
          ],
        ),
        const SizedBox(height: 10),
        _skeletonField(),
        const SizedBox(height: 4),
        _skeletonLine(height: 16, width: 120, radius: 6),
        const SizedBox(height: 8),
        ...List.generate(3, (_) {
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                children: [
                  _skeletonLine(height: 18, width: 18, radius: 4),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _skeletonLine(height: 12, width: 130, radius: 6),
                        const SizedBox(height: 6),
                        _skeletonLine(height: 10, width: 200, radius: 6),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _skeletonLine(height: 24, width: 64, radius: 999),
                  const SizedBox(width: 8),
                  _skeletonLine(height: 28, width: 28, radius: 999),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 6),
        _skeletonLine(height: 42, width: 140, radius: 12),
      ],
    );
  }

  Widget _eventsSkeleton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _skeletonLine(height: 12, width: 210, radius: 6),
                const SizedBox(height: 6),
                _skeletonLine(height: 54, radius: 12),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        ...List.generate(
          4,
          (_) => SizedBox(
            width: double.infinity,
            child: Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _skeletonLine(height: 16, width: 170, radius: 6),
                    const SizedBox(height: 6),
                    _skeletonLine(height: 12, width: 260, radius: 6),
                    const SizedBox(height: 6),
                    _skeletonLine(height: 12, width: 160, radius: 6),
                    const SizedBox(height: 8),
                    _skeletonLine(height: 12, width: 70, radius: 6),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      children: [
                        _skeletonLine(height: 36, width: 148, radius: 10),
                        _skeletonLine(height: 36, width: 120, radius: 10),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _mySessionsSkeleton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _skeletonField(),
        const SizedBox(height: 2),
        ...[
          'Total Score',
          'Holes Played (9 or 18)',
          'Total Putts (optional)',
          'GIR Count (optional)',
          'Fairways Hit (optional)',
          'Penalties Total (optional)',
          'Notes (optional)',
        ].map((_) => _skeletonField()),
        const SizedBox(height: 2),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _skeletonLine(height: 40, width: 120, radius: 12),
            _skeletonLine(height: 40, width: 120, radius: 12),
            _skeletonLine(height: 40, width: 120, radius: 12),
            _skeletonLine(height: 40, width: 140, radius: 12),
          ],
        ),
        const SizedBox(height: 10),
        ...List.generate(
          2,
          (_) => Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              title: _skeletonLine(height: 12, width: 160, radius: 6),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _skeletonLine(height: 10, width: 200, radius: 6),
              ),
              trailing: _skeletonLine(height: 12, width: 70, radius: 6),
            ),
          ),
        ),
      ],
    );
  }

  Widget _inboxSkeleton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: _skeletonLine(height: 36, width: 120, radius: 12),
        ),
        const SizedBox(height: 8),
        ...List.generate(
          4,
          (_) => Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _skeletonLine(height: 12, width: 180, radius: 6),
                  const SizedBox(height: 8),
                  _skeletonLine(height: 10, width: 240, radius: 6),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _skeletonLine(height: 32, width: 78, radius: 10),
                      const SizedBox(width: 8),
                      _skeletonLine(height: 32, width: 78, radius: 10),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final charityProvider = context.watch<CharityProvider>();
    final provider = context.watch<TournamentProvider>();
    final events = provider.events;
    final readOnlyGuest = !auth.isAuthenticated;
    final charities = charityProvider.charities
        .where((c) => c['is_active'] != false)
        .toList();
    String? effectiveCharityId = _selectedCharityId;
    if ((effectiveCharityId ?? '').isEmpty ||
        !charities.any((c) => c['id']?.toString() == effectiveCharityId)) {
      effectiveCharityId =
          charities.isNotEmpty ? charities.first['id']?.toString() : null;
    }
    final selectedCharity = charities.cast<Map<String, dynamic>>().where(
          (c) => c['id']?.toString() == effectiveCharityId,
        );
    final selectedCharityName = selectedCharity.isNotEmpty
        ? (selectedCharity.first['name']?.toString() ?? 'Charity')
        : 'Charity';
    final availableEvents = events;
    final selectedEvent = availableEvents.cast<Map<String, dynamic>>().firstWhere(
          (e) => e['id']?.toString() == _selectedUnlockedEventId,
          orElse: () => <String, dynamic>{},
        );
    final selectedEventType =
        (selectedEvent['event_type'] ?? '').toString().toLowerCase();
    final isSoloEvent = selectedEventType == 'solo';
    final allKnownPlayers = provider.availablePlayers;
    final onlinePlayers =
        allKnownPlayers.where((p) => p['is_online'] == true).toList();
    final query = _playerQuery.trim().toLowerCase();
    final hasQuery = query.isNotEmpty;
    final searchedPlayers = allKnownPlayers.where((p) {
      final username = (p['username'] ?? '').toString().toLowerCase();
      final email = (p['email'] ?? '').toString().toLowerCase();
      return username.contains(query) || email.contains(query);
    }).toList();
    final fallbackPlayers = onlinePlayers.isEmpty
        ? allKnownPlayers.take(24).toList()
        : onlinePlayers;
    final visiblePlayers = hasQuery ? searchedPlayers : fallbackPlayers;
    final inbox = provider.inboxMessages;
    final sessions = provider.sessions;
    final playableSessions =
        sessions.where((s) => s['status'] == 'in_progress').toList();
    Map<String, dynamic>? selectedSession;
    if (_selectedSessionId != null) {
      for (final s in sessions) {
        if (s['id'].toString() == _selectedSessionId) {
          selectedSession = s;
          break;
        }
      }
    }
    final selectedStatus = (selectedSession?['status'] ?? '').toString();
    final selectedAutoCloseAt = selectedSession?['auto_close_at']?.toString();
    final canControlSelected = selectedSession?['can_control_session'] == true;
    final scoreboardEntries =
        (provider.scoreboard?['entries'] as List<dynamic>? ?? const [])
            .cast<Map<String, dynamic>>();
    final inviteMessages = inbox
        .where((m) => m['message_type'] == 'invite' && m['status'] == 'unread')
        .toList();
    final scoreRequests = inbox
        .where((m) =>
            m['message_type'] == 'score_confirmation_request' &&
            m['status'] == 'unread')
        .toList();
    final friendRequests = provider.incomingFriendRequests;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F7),
      body: SafeArea(
        child: Column(
          children: [
            TopNavigationBar(
              activeItem: TopNavItem.charityTournaments,
              onNavigate: _onNavTap,
              onOpenInbox: () async {
                if (!mounted) return;
                setState(() => _tabIndex = 3);
                await _onOpenInboxTab();
              },
              trailing: IconButton(
                onPressed: _busy ? null : _reloadAll,
                icon: const Icon(Icons.refresh),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.zero,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final horizontalPadding =
                        constraints.maxWidth < 640 ? 12.0 : 16.0;
                    return Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints:
                            const BoxConstraints(maxWidth: _maxContentWidth),
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            horizontalPadding,
                            16,
                            horizontalPadding,
                            20,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _localNavBar(),
                              const SizedBox(height: 12),
                              if (_tabIndex == 0) ...[
                                if (_showEventsSkeleton)
                                  _eventsSkeleton()
                                else ...[
                                  if (readOnlyGuest)
                                    const Padding(
                                      padding: EdgeInsets.only(bottom: 8),
                                      child: Text(
                                        'Read-only mode: login to join events and setup challenges.',
                                        style: TextStyle(
                                            color: Colors.orangeAccent),
                                      ),
                                    ),
                                  if (!readOnlyGuest) ...[
                                    if (charities.isEmpty)
                                      const Card(
                                        child: ListTile(
                                          title: Text(
                                              'No active charities available'),
                                          subtitle: Text(
                                            'Ask admin to add or activate charities before collecting event donations.',
                                            style: TextStyle(
                                                color: Color(0xFF607289)),
                                          ),
                                        ),
                                      )
                                    else
                                      Card(
                                        child: Padding(
                                          padding: const EdgeInsets.all(12),
                                          child:
                                              DropdownButtonFormField<String>(
                                            initialValue: effectiveCharityId,
                                            items: charities
                                                .map(
                                                  (c) => DropdownMenuItem(
                                                    value: c['id']?.toString(),
                                                    child: Text(
                                                        c['name']?.toString() ??
                                                            'Charity'),
                                                  ),
                                                )
                                                .toList(),
                                            onChanged: _busy
                                                ? null
                                                : (v) => setState(() =>
                                                    _selectedCharityId = v),
                                            decoration: const InputDecoration(
                                              labelText:
                                                  'Select Charity For Event Donation',
                                            ),
                                          ),
                                        ),
                                      ),
                                    const SizedBox(height: 8),
                                  ],
                                  ...events.map((event) {
                                    final id = event['id']?.toString() ?? '';
                                    final title =
                                        event['title']?.toString() ?? 'Event';
                                    final description =
                                        event['description']?.toString() ?? '';
                                    final amountCents =
                                        (event['min_donation_cents'] as num?)
                                                ?.toInt() ??
                                            0;
                                    return SizedBox(
                                      width: double.infinity,
                                      child: Card(
                                        margin:
                                            const EdgeInsets.only(bottom: 8),
                                        child: Padding(
                                          padding: const EdgeInsets.all(12),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                title,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16,
                                                  color: Color(0xFF0F172A),
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                description,
                                                style: const TextStyle(
                                                    color: Color(0xFF607289)),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                'Optional donation: \$${(amountCents / 100).toStringAsFixed(2)}',
                                                style: const TextStyle(
                                                    color: Color(0xFF607289)),
                                              ),
                                              const SizedBox(height: 6),
                                              const Text(
                                                'Available',
                                                style: TextStyle(
                                                  color: Color(0xFF2FB67A),
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              Wrap(
                                                spacing: 8,
                                                children: [
                                                  OutlinedButton(
                                                    onPressed: (readOnlyGuest ||
                                                            _busy ||
                                                            id.isEmpty ||
                                                            effectiveCharityId ==
                                                                null)
                                                        ? null
                                                        : () =>
                                                            _openStripePopup(
                                                              eventId: id,
                                                              amountCents:
                                                                  amountCents,
                                                              eventTitle: title,
                                                              charityId:
                                                                  effectiveCharityId!,
                                                              charityName:
                                                                  selectedCharityName,
                                                            ),
                                                    child: const Text(
                                                        'Donate From Wallet'),
                                                  ),
                                                  ElevatedButton(
                                                    onPressed:
                                                        (readOnlyGuest || _busy)
                                                            ? null
                                                            : () => setState(
                                                                  () =>
                                                                      _selectedUnlockedEventId =
                                                                          id,
                                                                ),
                                                    child: Text(
                                                      _selectedUnlockedEventId ==
                                                              id
                                                          ? 'Selected'
                                                          : 'Use This Event',
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  }),
                                ],
                              ],
                              if (_tabIndex == 1) ...[
                                if (_showSetupSkeleton)
                                  _setupChallengeSkeleton()
                                else ...[
                                  if (readOnlyGuest)
                                    const Text(
                                      'Login required for challenge setup.',
                                      style:
                                          TextStyle(color: Color(0xFF607289)),
                                    )
                                  else if (availableEvents.isEmpty)
                                    const Text(
                                      'Choose an event to setup a challenge or solo session.',
                                      style:
                                          TextStyle(color: Color(0xFF607289)),
                                    ),
                                  if (!readOnlyGuest &&
                                      availableEvents.isNotEmpty) ...[
                                    DropdownButtonFormField<String>(
                                      initialValue: _selectedUnlockedEventId,
                                      items: availableEvents
                                          .map(
                                            (e) => DropdownMenuItem(
                                              value: e['id'].toString(),
                                              child:
                                                  Text(e['title'].toString()),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (v) => setState(
                                          () => _selectedUnlockedEventId = v),
                                      decoration: const InputDecoration(
                                          labelText: 'Event'),
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            'Play Date/Time: ${_scheduledAt.toLocal().toString().substring(0, 16)}',
                                            style: const TextStyle(
                                                color: Color(0xFF607289)),
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: _busy
                                              ? null
                                              : () async {
                                                  final pickedDate =
                                                      await showDatePicker(
                                                    context: context,
                                                    initialDate: _scheduledAt,
                                                    firstDate: DateTime.now(),
                                                    lastDate: DateTime.now()
                                                        .add(const Duration(
                                                            days: 365)),
                                                  );
                                                  if (pickedDate == null) {
                                                    return;
                                                  }
                                                  if (!mounted) return;
                                                  final pickedTime =
                                                      await showTimePicker(
                                                    context: context,
                                                    initialTime:
                                                        TimeOfDay.fromDateTime(
                                                            _scheduledAt),
                                                  );
                                                  if (pickedTime == null) {
                                                    return;
                                                  }
                                                  setState(() {
                                                    _scheduledAt = DateTime(
                                                      pickedDate.year,
                                                      pickedDate.month,
                                                      pickedDate.day,
                                                      pickedTime.hour,
                                                      pickedTime.minute,
                                                    );
                                                  });
                                                },
                                          child:
                                              const Text('Select Date & Time'),
                                        ),
                                      ],
                                    ),
                                    if (isSoloEvent) ...[
                                      const SizedBox(height: 10),
                                      const Card(
                                        child: ListTile(
                                          title: Text('Solo event selected'),
                                          subtitle: Text(
                                            'No invitees or marker confirmation are required for this session.',
                                            style: TextStyle(
                                                color: Color(0xFF607289)),
                                          ),
                                        ),
                                      ),
                                    ] else ...[
                                      const SizedBox(height: 10),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: TextField(
                                              onChanged: (v) => setState(
                                                  () => _playerQuery = v),
                                              decoration: const InputDecoration(
                                                labelText:
                                                    'Search known players',
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          OutlinedButton.icon(
                                            onPressed:
                                                _busy ? null : _refreshPlayers,
                                            icon: const Icon(Icons.refresh),
                                            label:
                                                const Text('Refresh Players'),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        hasQuery
                                            ? 'Search Results'
                                            : (onlinePlayers.isEmpty
                                                ? 'Recently Active Players'
                                                : 'Players Online'),
                                        style: const TextStyle(
                                          color: Color(0xFF1B5D86),
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      if (visiblePlayers.isEmpty)
                                        Card(
                                          child: ListTile(
                                            title: Text(
                                              hasQuery
                                                  ? 'No matching players found'
                                                  : 'No players online right now',
                                            ),
                                            subtitle: Text(
                                              hasQuery
                                                  ? 'Try username or email.'
                                                  : 'Use search to find a known player.',
                                              style: const TextStyle(
                                                  color: Color(0xFF607289)),
                                            ),
                                          ),
                                        )
                                      else
                                        SizedBox(
                                          height: 220,
                                          child: ListView.builder(
                                            itemCount: visiblePlayers.length,
                                            itemBuilder: (context, index) {
                                              final p = visiblePlayers[index];
                                              final id = (p['id'] as num).toInt();
                                              final selected =
                                                  _selectedInvitees.contains(id);
                                              final isOnline =
                                                  p['is_online'] == true;
                                              final friendStatus =
                                                  (p['friend_status'] ?? 'none')
                                                      .toString();
                                              final clubAffiliation =
                                                  (p['club_affiliation'] ?? '')
                                                      .toString()
                                                      .trim();
                                              final profilePic =
                                                  (p['profile_pic'] ?? '')
                                                      .toString()
                                                      .trim();

                                              return Card(
                                                child: Padding(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                          horizontal: 8),
                                                  child: Row(
                                                    children: [
                                                      Checkbox(
                                                        value: selected,
                                                        onChanged: _busy
                                                            ? null
                                                            : (v) {
                                                                setState(() {
                                                                  if (v == true) {
                                                                    _selectedInvitees
                                                                        .add(id);
                                                                  } else {
                                                                    _selectedInvitees
                                                                        .remove(
                                                                            id);
                                                                  }
                                                                });
                                                              },
                                                      ),
                                                      Expanded(
                                                        child: ListTile(
                                                          contentPadding:
                                                              EdgeInsets.zero,
                                                          title: Text(p[
                                                                      'username']
                                                                  ?.toString() ??
                                                              'Player'),
                                                          subtitle: Text(
                                                            clubAffiliation
                                                                    .isNotEmpty
                                                                ? clubAffiliation
                                                                : 'No club affiliation',
                                                            style: const TextStyle(
                                                                color: Color(
                                                                    0xFF607289)),
                                                          ),
                                                        ),
                                                      ),
                                                      Container(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                          horizontal: 8,
                                                          vertical: 3,
                                                        ),
                                                        decoration: BoxDecoration(
                                                          color: isOnline
                                                              ? const Color(
                                                                  0xFFE7F8EF)
                                                              : const Color(
                                                                  0xFFF1F4F8),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(999),
                                                        ),
                                                        child: Text(
                                                          isOnline
                                                              ? 'Online'
                                                              : 'Offline',
                                                          style: TextStyle(
                                                            color: isOnline
                                                                ? const Color(
                                                                    0xFF2A8B5A)
                                                                : const Color(
                                                                    0xFF607289),
                                                            fontSize: 11,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      _friendAvatarAction(
                                                        playerId: id,
                                                        username: p['username']
                                                                ?.toString() ??
                                                            'Player',
                                                        profilePicUrl:
                                                            profilePic,
                                                        friendStatus:
                                                            friendStatus,
                                                        disabled: _busy,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                    ],
                                    const SizedBox(height: 10),
                                    ElevatedButton.icon(
                                      onPressed: _busy ? null : _createSession,
                                      icon: const Icon(Icons.send),
                                      label: Text(
                                        isSoloEvent
                                            ? 'Create Solo Session'
                                            : 'Create Challenge',
                                      ),
                                    ),
                                  ],
                                ],
                              ],
                              if (_tabIndex == 2) ...[
                                if (_showMySessionsSkeleton)
                                  _mySessionsSkeleton()
                                else ...[
                                  if (sessions.isEmpty)
                                    const Card(
                                      child: ListTile(
                                        title: Text('No sessions yet'),
                                        subtitle: Text(
                                            'Create or accept an invite to start.'),
                                      ),
                                    )
                                  else ...[
                                    DropdownButtonFormField<String>(
                                      initialValue: _selectedSessionId,
                                      items: sessions
                                          .map(
                                            (s) => DropdownMenuItem(
                                              value: s['id'].toString(),
                                              child: Text(
                                                '${(s['event_title'] ?? s['event_type']).toString()} • ${s['status']} • ${s['scheduled_at'].toString().substring(0, 16)}',
                                              ),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (v) => setState(
                                          () => _selectedSessionId = v),
                                      decoration: const InputDecoration(
                                          labelText: 'Select Session'),
                                    ),
                                    const SizedBox(height: 10),
                                    if (_selectedSessionId != null &&
                                        playableSessions.any(
                                          (s) =>
                                              s['id'].toString() ==
                                              _selectedSessionId,
                                        )) ...[
                                      TextField(
                                        controller: _scoreController,
                                        keyboardType: TextInputType.number,
                                        decoration: const InputDecoration(
                                            labelText: 'Total Score'),
                                      ),
                                      const SizedBox(height: 8),
                                      TextField(
                                        controller: _holesPlayedController,
                                        keyboardType: TextInputType.number,
                                        decoration: const InputDecoration(
                                          labelText: 'Holes Played (9 or 18)',
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      TextField(
                                        controller: _puttsController,
                                        keyboardType: TextInputType.number,
                                        decoration: const InputDecoration(
                                          labelText: 'Total Putts (optional)',
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      TextField(
                                        controller: _girController,
                                        keyboardType: TextInputType.number,
                                        decoration: const InputDecoration(
                                          labelText: 'GIR Count (optional)',
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      TextField(
                                        controller: _fairwaysController,
                                        keyboardType: TextInputType.number,
                                        decoration: const InputDecoration(
                                          labelText: 'Fairways Hit (optional)',
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      TextField(
                                        controller: _penaltiesController,
                                        keyboardType: TextInputType.number,
                                        decoration: const InputDecoration(
                                          labelText:
                                              'Penalties Total (optional)',
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      TextField(
                                        controller: _notesController,
                                        decoration: const InputDecoration(
                                          labelText: 'Notes (optional)',
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      ElevatedButton(
                                        onPressed:
                                            _busy ? null : _submitSessionScore,
                                        child: const Text('Submit Score'),
                                      ),
                                    ] else
                                      const Text(
                                        'Score submission is available only for in-progress sessions.',
                                        style:
                                            TextStyle(color: Color(0xFF607289)),
                                      ),
                                    const SizedBox(height: 10),
                                    if (_selectedSessionId != null &&
                                        selectedStatus == 'ready_to_start')
                                      ElevatedButton.icon(
                                        onPressed:
                                            (_busy || !canControlSelected)
                                                ? null
                                                : _startSession,
                                        icon: const Icon(Icons.play_arrow),
                                        label: const Text('Start Session'),
                                      ),
                                    if (_selectedSessionId != null &&
                                        selectedStatus == 'in_progress') ...[
                                      if (selectedAutoCloseAt != null)
                                        Text(
                                          'Auto-closes at: $selectedAutoCloseAt',
                                          style: const TextStyle(
                                              color: Color(0xFF607289)),
                                        ),
                                      const SizedBox(height: 6),
                                      ElevatedButton.icon(
                                        onPressed:
                                            (_busy || !canControlSelected)
                                                ? null
                                                : _endSession,
                                        icon: const Icon(Icons.stop),
                                        label: const Text('End Session'),
                                      ),
                                      if (!canControlSelected)
                                        const Padding(
                                          padding: EdgeInsets.only(top: 6),
                                          child: Text(
                                            'Only the session creator can end the session.',
                                            style: TextStyle(
                                                color: Color(0xFF607289)),
                                          ),
                                        ),
                                    ],
                                    const SizedBox(height: 12),
                                    OutlinedButton(
                                      onPressed:
                                          (_busy || _selectedSessionId == null)
                                              ? null
                                              : _loadSessionScoreboard,
                                      child: const Text('Load Scoreboard'),
                                    ),
                                    const SizedBox(height: 8),
                                    ...scoreboardEntries.map(
                                      (e) => Card(
                                        child: ListTile(
                                          title: Text(
                                              'Player ${e['player_user_id']}'),
                                          subtitle: Text(
                                              'Recorded at ${e['confirmed_at']}'),
                                          trailing: Text(
                                            'Score ${e['total_score']}',
                                            style: const TextStyle(
                                              color: Color(0xFF1993D1),
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ],
                              if (_tabIndex == 3) ...[
                                if (_showInboxSkeleton)
                                  _inboxSkeleton()
                                else ...[
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: OutlinedButton.icon(
                                      onPressed: _busy ? null : _clearInbox,
                                      icon: const Icon(Icons.clear_all),
                                      label: const Text('Clear Inbox'),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  if (inviteMessages.isEmpty &&
                                      scoreRequests.isEmpty &&
                                      friendRequests.isEmpty)
                                    const Text(
                                      'No pending messages',
                                      style:
                                          TextStyle(color: Color(0xFF607289)),
                                    ),
                                  ...friendRequests.map(
                                    (r) => Card(
                                      child: ListTile(
                                        title: Text(
                                            'Friend request from ${r['sender_username'] ?? 'Player'}'),
                                        subtitle: Text(
                                          (r['sender_email'] ?? '').toString(),
                                          style: const TextStyle(
                                              color: Color(0xFF607289)),
                                        ),
                                        trailing: Wrap(
                                          spacing: 6,
                                          children: [
                                            TextButton(
                                              onPressed: _busy
                                                  ? null
                                                  : () => _actionFriendRequest(
                                                        r['id'].toString(),
                                                        'accept',
                                                      ),
                                              child: const Text('Accept'),
                                            ),
                                            TextButton(
                                              onPressed: _busy
                                                  ? null
                                                  : () => _actionFriendRequest(
                                                        r['id'].toString(),
                                                        'decline',
                                                      ),
                                              child: const Text('Decline'),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  ...inviteMessages.map(
                                    (m) => Card(
                                      child: ListTile(
                                        title: Text(
                                            m['title']?.toString() ?? 'Invite'),
                                        subtitle: Text(
                                          m['body']?.toString() ?? '',
                                          style: const TextStyle(
                                              color: Color(0xFF607289)),
                                        ),
                                        trailing: Wrap(
                                          spacing: 6,
                                          children: [
                                            TextButton(
                                              onPressed: _busy
                                                  ? null
                                                  : () => _actionMessage(
                                                        m['id'].toString(),
                                                        'accept',
                                                      ),
                                              child: const Text('Accept'),
                                            ),
                                            TextButton(
                                              onPressed: _busy
                                                  ? null
                                                  : () => _actionMessage(
                                                        m['id'].toString(),
                                                        'decline',
                                                      ),
                                              child: const Text('Decline'),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  ...scoreRequests.map(
                                    (m) => Card(
                                      child: ListTile(
                                        title: Text(m['title']?.toString() ??
                                            'Score Update'),
                                        subtitle: Text(
                                          'Legacy score review message: ${m['body']?.toString() ?? ''}',
                                          style: const TextStyle(
                                              color: Color(0xFF607289)),
                                        ),
                                        trailing: const Text(
                                          'No action needed',
                                          style: TextStyle(
                                            color: Color(0xFF607289),
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                              if (_busy)
                                const Padding(
                                  padding: EdgeInsets.only(top: 10),
                                  child: Center(
                                      child: CircularProgressIndicator()),
                                ),
                              if (provider.error != null &&
                                  events.isEmpty &&
                                  sessions.isEmpty &&
                                  inbox.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    provider.error!,
                                    style: const TextStyle(
                                        color: Colors.redAccent),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isRemoteImageUrl(String url) {
    if (url.trim().isEmpty) return false;
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return false;
    final scheme = uri.scheme.toLowerCase();
    return scheme == 'http' || scheme == 'https';
  }

  String _initialForName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'P';
    return trimmed[0].toUpperCase();
  }

  Widget _friendAvatarAction({
    required int playerId,
    required String username,
    required String profilePicUrl,
    required String friendStatus,
    required bool disabled,
  }) {
    final isRemote = _isRemoteImageUrl(profilePicUrl);
    final avatar = Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFD4DEE8)),
        color: const Color(0xFFEAF4FB),
      ),
      clipBehavior: Clip.antiAlias,
      child: isRemote
          ? Image.network(
              profilePicUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Center(
                child: Text(
                  _initialForName(username),
                  style: const TextStyle(
                    color: Color(0xFF1B5D86),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            )
          : Center(
              child: Text(
                _initialForName(username),
                style: const TextStyle(
                  color: Color(0xFF1B5D86),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
    );

    IconData badgeIcon = Icons.add;
    Color badgeColor = const Color(0xFF1993D1);
    String tooltip = 'Add friend';
    VoidCallback? onTap;

    if (friendStatus == 'friend') {
      badgeIcon = Icons.check;
      badgeColor = const Color(0xFF2FB67A);
      tooltip = 'Already friends';
      onTap = null;
    } else if (friendStatus == 'outgoing_pending') {
      badgeIcon = Icons.schedule;
      badgeColor = const Color(0xFF607289);
      tooltip = 'Friend request sent';
      onTap = null;
    } else if (friendStatus == 'incoming_pending') {
      badgeIcon = Icons.mark_email_unread_outlined;
      badgeColor = const Color(0xFF1B5D86);
      tooltip = 'Incoming friend request in Inbox';
      onTap = null;
    } else {
      onTap = disabled ? null : () => _sendFriendRequest(playerId);
    }

    final body = Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: badgeColor,
              border: Border.all(color: Colors.white, width: 1.5),
            ),
            child: Icon(
              badgeIcon,
              size: 10,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: body,
        ),
      ),
    );
  }
}
