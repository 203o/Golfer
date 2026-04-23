import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_provider.dart';
import '../services/tournament_provider.dart';
import '../widgets/top_navigation_bar.dart';
import 'landing_screen.dart';
import 'profile_sessions_screen.dart';
import 'tournament_player_screen.dart';
import 'user_dashboard_screen.dart';

class TournamentInboxScreen extends StatefulWidget {
  const TournamentInboxScreen({super.key});

  @override
  State<TournamentInboxScreen> createState() => _TournamentInboxScreenState();
}

class _TournamentInboxScreenState extends State<TournamentInboxScreen> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _reload();
    });
  }

  Future<void> _reload() async {
    setState(() => _busy = true);
    try {
      final provider = context.read<TournamentProvider>();
      try {
        await provider.markInboxSeen();
      } catch (_) {
        await provider.loadInbox();
      }
      await provider.loadIncomingFriendRequests();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _actionInvite(String messageId, String action) async {
    setState(() => _busy = true);
    try {
      await context.read<TournamentProvider>().actionInboxMessage(
            messageId: messageId,
            action: action,
          );
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invite $action')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Action failed: $e')),
      );
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
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            action == 'accept'
                ? 'Friend request accepted'
                : 'Friend request declined',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Friend request action failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onNavTap(TopNavItem item) {
    final auth = context.read<AuthProvider>();
    if (!auth.isAuthenticated && item != TopNavItem.jackpot) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to continue.')),
      );
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
        screen = const UserDashboardScreen(initialView: DashboardView.dashboard);
    }

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => screen),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TournamentProvider>();
    final messages = provider.inboxMessages;
    final friendRequests = provider.incomingFriendRequests;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F7),
      body: SafeArea(
        child: Column(
          children: [
            TopNavigationBar(
              activeItem: TopNavItem.charityTournaments,
              onNavigate: _onNavTap,
              onOpenInbox: _reload,
              onOpenMySessions: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ProfileSessionsScreen(),
                  ),
                );
              },
              trailing: IconButton(
                onPressed: _busy ? null : _reload,
                icon: const Icon(Icons.refresh),
              ),
            ),
            Expanded(
              child: (messages.isEmpty && friendRequests.isEmpty)
                  ? const Center(
                      child: Text(
                        'No messages',
                        style: TextStyle(color: Color(0xFF607289)),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.all(12),
                      children: [
                        ...friendRequests.map(
                          (r) => Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Friend request from ${r['sender_username'] ?? 'Player'}',
                                    style: const TextStyle(
                                      color: Color(0xFF0F172A),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    (r['sender_email'] ?? '').toString(),
                                    style: const TextStyle(color: Color(0xFF607289)),
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
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
                                ],
                              ),
                            ),
                          ),
                        ),
                        ...messages.map((m) {
                          final type = (m['message_type'] ?? '').toString();
                          final status = (m['status'] ?? '').toString();
                          final scoreId = (m['related_score_id'] ?? '').toString();
                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          m['title']?.toString() ?? 'Message',
                                          style: const TextStyle(
                                            color: Color(0xFF0F172A),
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      if (status == 'unread')
                                        const Icon(
                                          Icons.circle,
                                          color: Colors.orangeAccent,
                                          size: 10,
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    m['body']?.toString() ?? '',
                                    style: const TextStyle(color: Color(0xFF607289)),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '${m['created_at'] ?? ''}',
                                    style: const TextStyle(
                                      color: Color(0xFF74859A),
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  if (type == 'invite' && status == 'unread')
                                    Wrap(
                                      spacing: 8,
                                      children: [
                                        TextButton(
                                          onPressed: _busy
                                              ? null
                                              : () => _actionInvite(
                                                    m['id'].toString(),
                                                    'accept',
                                                  ),
                                          child: const Text('Accept'),
                                        ),
                                        TextButton(
                                          onPressed: _busy
                                              ? null
                                              : () => _actionInvite(
                                                    m['id'].toString(),
                                                    'decline',
                                                  ),
                                          child: const Text('Decline'),
                                        ),
                                      ],
                                    ),
                                  if (type == 'score_confirmation_request' &&
                                      status == 'unread' &&
                                      scoreId.isNotEmpty)
                                    const Text(
                                      'No action needed',
                                      style: TextStyle(
                                        color: Color(0xFF607289),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: _busy
          ? const FloatingActionButton(
              onPressed: null,
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : null,
    );
  }
}
