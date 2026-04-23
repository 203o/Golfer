import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_provider.dart';
import '../services/tournament_provider.dart';
import '../widgets/top_navigation_bar.dart';
import 'landing_screen.dart';
import 'tournament_inbox_screen.dart';
import 'tournament_player_screen.dart';
import 'user_dashboard_screen.dart';

class ProfileSessionsScreen extends StatefulWidget {
  const ProfileSessionsScreen({super.key});

  @override
  State<ProfileSessionsScreen> createState() => _ProfileSessionsScreenState();
}

class _ProfileSessionsScreenState extends State<ProfileSessionsScreen> {
  final TextEditingController _scoreController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  String? _selectedSessionId;
  bool _busy = false;
  bool _didLoad = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didLoad) return;
    _didLoad = true;
    _load();
  }

  @override
  void dispose() {
    _scoreController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final tournamentProvider = context.read<TournamentProvider>();
      await tournamentProvider.loadMySessions();
      await tournamentProvider.loadInbox();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
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

  Future<void> _submitScore() async {
    final sessionId = _selectedSessionId;
    final score = int.tryParse(_scoreController.text.trim());
    if (sessionId == null) return _snack('Select a session');
    if (score == null) return _snack('Enter a valid score');

    setState(() => _busy = true);
    try {
      await context.read<TournamentProvider>().submitSessionScore(
            sessionId: sessionId,
            totalScore: score,
            notes: _notesController.text.trim(),
          );
      _scoreController.clear();
      _notesController.clear();
      await _load();
      _snack('Score recorded');
    } catch (e) {
      _snack('Submit failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadScoreboard() async {
    final sessionId = _selectedSessionId;
    if (sessionId == null) return _snack('Select a session');
    setState(() => _busy = true);
    try {
      await context.read<TournamentProvider>().loadScoreboard(sessionId);
    } catch (e) {
      _snack('Load scoreboard failed: $e');
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
      await _load();
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
      await _load();
      _snack('Session ended.');
    } catch (e) {
      _snack('End failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TournamentProvider>();
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
    final scoreboardEntries =
        (provider.scoreboard?['entries'] as List<dynamic>? ?? const [])
            .cast<Map<String, dynamic>>();

    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F7),
      body: SafeArea(
        child: Column(
          children: [
            TopNavigationBar(
              activeItem: TopNavItem.charityTournaments,
              onNavigate: _onNavTap,
              onOpenInbox: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const TournamentInboxScreen(),
                  ),
                );
              },
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Text(
                      'My Sessions',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (sessions.isEmpty)
                      const Card(
                        child: ListTile(
                          title: Text('No sessions yet'),
                          subtitle:
                              Text('Create or accept an invite to start.'),
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
                        onChanged: (v) =>
                            setState(() => _selectedSessionId = v),
                        decoration:
                            const InputDecoration(labelText: 'Select Session'),
                      ),
                      const SizedBox(height: 10),
                      if (_selectedSessionId != null &&
                          playableSessions.any(
                            (s) => s['id'].toString() == _selectedSessionId,
                          )) ...[
                        TextField(
                          controller: _scoreController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Total Score',
                            helperText: 'Enter a positive whole-number score.',
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
                          onPressed: _busy ? null : _submitScore,
                          child: const Text('Submit Score'),
                        ),
                      ] else
                        const Text(
                          'Score submission is available only for in-progress sessions.',
                          style: TextStyle(color: Color(0xFF607289)),
                        ),
                      const SizedBox(height: 10),
                      if (_selectedSessionId != null &&
                          selectedStatus == 'ready_to_start')
                        ElevatedButton.icon(
                          onPressed: _busy ? null : _startSession,
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Start Session'),
                        ),
                      if (_selectedSessionId != null &&
                          selectedStatus == 'in_progress') ...[
                        if (selectedAutoCloseAt != null)
                          Text(
                            'Auto-closes at: $selectedAutoCloseAt',
                            style: const TextStyle(color: Color(0xFF607289)),
                          ),
                        const SizedBox(height: 6),
                        ElevatedButton.icon(
                          onPressed: _busy ? null : _endSession,
                          icon: const Icon(Icons.stop),
                          label: const Text('End Session'),
                        ),
                      ],
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: (_busy || _selectedSessionId == null)
                            ? null
                            : _loadScoreboard,
                        child: const Text('Load Scoreboard'),
                      ),
                      const SizedBox(height: 8),
                      ...scoreboardEntries.map(
                        (e) => Card(
                          child: ListTile(
                            title: Text('Player ${e['player_user_id']}'),
                            subtitle: Text('Recorded at ${e['confirmed_at']}'),
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
                    if (_busy)
                      const Padding(
                        padding: EdgeInsets.only(top: 10),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    if (provider.error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          provider.error!,
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
