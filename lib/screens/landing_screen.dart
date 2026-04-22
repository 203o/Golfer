import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../services/auth_provider.dart';
import '../services/charity_provider.dart';
import '../services/draw_provider.dart';
import '../services/tournament_provider.dart';
import '../widgets/top_navigation_bar.dart';
import 'charity_directory_screen.dart';
import 'charity_profile_screen.dart';
import 'onboarding_gate_screen.dart';
import 'tournament_inbox_screen.dart';
import 'tournament_player_screen.dart';
import 'user_dashboard_screen.dart';

class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  static const double _maxContentWidth = 1120;
  static const Color _gold = Color(0xFFD4AF37);
  static const Color _green = Color(0xFF1CA36B);
  static const Color _sun = Color(0xFFF4C542);

  bool _didLoadCharities = false;
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _charitiesKey = GlobalKey();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didLoadCharities) return;
    _didLoadCharities = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<CharityProvider>().loadCharities();
      context.read<DrawProvider>().loadCurrentDraw();
      if (context.read<AuthProvider>().isAuthenticated) {
        context.read<TournamentProvider>().loadInbox().catchError((_) {});
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onNavTap(BuildContext context, TopNavItem item) {
    final auth = context.read<AuthProvider>();
    if (item == TopNavItem.jackpot) return;

    if (!auth.isAuthenticated) {
      _showLoginDialog(context);
      return;
    }

    Widget screen;
    switch (item) {
      case TopNavItem.jackpot:
        return;
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

  void _showLoginDialog(BuildContext context) {
    var isSignup = false;
    final emailController = TextEditingController();
    final nameController = TextEditingController();
    final passwordController = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: Text(isSignup ? 'Create Account' : 'Sign In'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => setModalState(() => isSignup = false),
                      child: Text(
                        'Login',
                        style: TextStyle(
                          color: isSignup
                              ? const Color(0xFF6A7B8D)
                              : const Color(0xFF1993D1),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: TextButton(
                      onPressed: () => setModalState(() => isSignup = true),
                      child: Text(
                        'Signup',
                        style: TextStyle(
                          color: isSignup
                              ? const Color(0xFF1993D1)
                              : const Color(0xFF6A7B8D),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (isSignup) ...[
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Display Name'),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password'),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final auth = context.read<AuthProvider>();
                    try {
                      await auth.signInWithGoogle();
                      if (!context.mounted) return;
                      Navigator.pop(context);
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Google login failed: $e')),
                      );
                    }
                  },
                  icon: const Icon(Icons.g_mobiledata),
                  label: const Text('Continue with Google'),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final auth = context.read<AuthProvider>();
                try {
                  if (isSignup) {
                    await auth.createUserWithEmailAndPassword(
                      emailController.text.trim(),
                      passwordController.text,
                      nameController.text.trim(),
                    );
                  } else {
                    await auth.signInWithEmailAndPassword(
                      emailController.text.trim(),
                      passwordController.text,
                    );
                  }
                  if (!context.mounted) return;
                  if (Navigator.of(context, rootNavigator: true).canPop()) {
                    Navigator.of(context, rootNavigator: true).pop();
                  }
                } catch (e) {
                  if (auth.isAuthenticated) {
                    if (!context.mounted) return;
                    if (Navigator.of(context, rootNavigator: true).canPop()) {
                      Navigator.of(context, rootNavigator: true).pop();
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Signed in, but backend sync needs a moment. Please retry if a feature fails.',
                        ),
                      ),
                    );
                    return;
                  }
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '${isSignup ? 'Signup' : 'Login'} failed: $e',
                      ),
                    ),
                  );
                }
              },
              child: Text(isSignup ? 'Create Account' : 'Sign In'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openOnboardingGate(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    if (!auth.isAuthenticated) {
      _showLoginDialog(context);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const OnboardingGateScreen()),
    );
  }

  Future<void> _openWebsite(String? url) async {
    final value = (url ?? '').trim();
    if (value.isEmpty) return;
    final ok =
        await launchUrlString(value, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open charity link')),
      );
    }
  }

  void _openCharityDirectory() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CharityDirectoryScreen()),
    );
  }

  void _openCharityProfile(Map<String, dynamic> charity) {
    final charityId = (charity['id'] ?? '').toString();
    if (charityId.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CharityProfileScreen(
          charityId: charityId,
          initialCharity: charity,
        ),
      ),
    );
  }

  Color _charityAccentColor(String name) {
    final lowered = name.toLowerCase().trim();

    if (lowered.contains('red cross')) return const Color(0xFFD7263D);
    if (lowered.contains('charity: water') ||
        lowered.contains('charity water')) {
      return const Color(0xFF1F8EF1);
    }
    if (lowered.contains('feeding america')) return const Color(0xFFFF8C42);
    if (lowered.contains('st. jude') || lowered.contains('st jude')) {
      return const Color(0xFFDC5D7A);
    }
    if (lowered.contains('habitat for humanity')) {
      return const Color(0xFF2CBF6D);
    }
    if (lowered.contains('doctors without borders')) {
      return const Color(0xFFE53935);
    }
    if (lowered.contains('salvation army')) return const Color(0xFFB71C1C);
    if (lowered.contains('united way')) return const Color(0xFFED7D31);
    if (lowered.contains('direct relief')) return const Color(0xFF5A67D8);
    if (lowered.contains('world wildlife fund') || lowered.contains('wwf')) {
      return const Color(0xFF2F855A);
    }

    if (lowered.contains('water')) return const Color(0xFF1F8EF1);
    if (lowered.contains('wildlife') || lowered.contains('environment')) {
      return const Color(0xFF2F855A);
    }
    if (lowered.contains('children') || lowered.contains('health')) {
      return const Color(0xFFDC5D7A);
    }
    if (lowered.contains('hunger') || lowered.contains('food')) {
      return const Color(0xFFFF8C42);
    }
    if (lowered.contains('disaster') || lowered.contains('relief')) {
      return const Color(0xFFB91C1C);
    }

    return const Color(0xFF1993D1);
  }

  Widget _charityCard(Map<String, dynamic> charity) {
    final name = (charity['name'] ?? 'Charity').toString();
    final snippet = (charity['description'] ?? '').toString().trim();
    final website = (charity['website_url'] ?? '').toString().trim();
    final accent = _charityAccentColor(name);
    final cause = (charity['cause'] ?? 'Community Impact').toString();
    final heroImage = (charity['hero_image_url'] ?? '').toString().trim();
    return Card(
      color: accent.withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: accent.withValues(alpha: 0.35), width: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (heroImage.isNotEmpty) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  heroImage,
                  height: 150,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
              const SizedBox(height: 14),
            ],
            Container(
              width: 30,
              height: 4,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              cause,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: accent.withValues(alpha: 0.9),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              name,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 17,
                color: accent,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              snippet.isEmpty ? 'Trusted partner charity.' : snippet,
              style: const TextStyle(color: Color(0xFF5D6E82)),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _openCharityProfile(charity),
                  icon:
                      Icon(Icons.visibility_outlined, size: 16, color: accent),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: accent,
                    side: BorderSide(color: accent.withValues(alpha: 0.5)),
                  ),
                  label: const Text('View Profile'),
                ),
                OutlinedButton.icon(
                  onPressed:
                      website.isEmpty ? null : () => _openWebsite(website),
                  icon: Icon(Icons.open_in_new, size: 16, color: accent),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: accent,
                    side: BorderSide(color: accent.withValues(alpha: 0.5)),
                  ),
                  label: const Text('Visit Charity'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _spotlightCard(Map<String, dynamic> charity) {
    final imageUrl = (charity['hero_image_url'] ?? '').toString().trim();
    final name = (charity['name'] ?? 'Spotlight Charity').toString();
    final cause = (charity['cause'] ?? 'Community Impact').toString();
    final spotlight =
        (charity['spotlight_text'] ?? charity['description'] ?? '')
            .toString()
            .trim();
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        image: imageUrl.isEmpty
            ? null
            : DecorationImage(
                image: NetworkImage(imageUrl),
                fit: BoxFit.cover,
                colorFilter: ColorFilter.mode(
                  Colors.black.withValues(alpha: 0.32),
                  BlendMode.darken,
                ),
              ),
        gradient: imageUrl.isEmpty
            ? const LinearGradient(
                colors: [Color(0xFF0F766E), Color(0xFFD4AF37)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white.withValues(alpha: 0.32)),
              ),
              child: const Text(
                'Spotlight Charity',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              name,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              cause,
              style: const TextStyle(
                color: Color(0xFFFFE083),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              spotlight.isEmpty
                  ? 'Discover this month\'s featured charity and support it through your subscription or an independent gift.'
                  : spotlight,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                ElevatedButton.icon(
                  onPressed: () => _openCharityProfile(charity),
                  icon: const Icon(Icons.visibility_outlined),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF0F172A),
                  ),
                  label: const Text('Open Profile'),
                ),
                OutlinedButton.icon(
                  onPressed: _openCharityDirectory,
                  icon: const Icon(Icons.travel_explore_outlined),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side:
                        BorderSide(color: Colors.white.withValues(alpha: 0.55)),
                  ),
                  label: const Text('Browse Directory'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _accentPill({
    required String text,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final charityProvider = context.watch<CharityProvider>();
    final drawProvider = context.watch<DrawProvider>();
    final charities = charityProvider.charities;
    final featuredCharity = charityProvider.featuredCharity ??
        charities.cast<Map<String, dynamic>?>().firstWhere(
              (c) => c?['is_featured'] == true,
              orElse: () => charities.isEmpty ? null : charities.first,
            );
    final charityPreview = featuredCharity == null
        ? charities.take(4).toList()
        : <Map<String, dynamic>>[
            featuredCharity,
            ...charities
                .where((c) =>
                    (c['id'] ?? '').toString() !=
                    (featuredCharity['id'] ?? '').toString())
                .take(3),
          ];
    final drawPoolBreakdown =
        (drawProvider.currentDraw?['pool_breakdown'] as Map?)
                ?.cast<String, dynamic>() ??
            const <String, dynamic>{};
    final drawTierSummary =
        (drawPoolBreakdown['tier_summary'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
    final drawPoolCents =
        ((drawProvider.currentDraw?['pool_total_cents'] ?? 0) as num).toInt();
    final drawPoolUsd = (drawPoolCents / 100).round();
    final liveDrawPoolDisplay = drawPoolUsd > 0 ? drawPoolUsd : 299;
    final match4PoolUsd =
        ((((drawTierSummary['match_4'] as Map?)?['pool_cents'] ?? 0) as num)
                    .toInt() /
                100)
            .round();
    final match5BaseUsd =
        ((((drawTierSummary['match_5'] as Map?)?['base_pool_cents'] ?? 0)
                        as num)
                    .toInt() /
                100)
            .round();

    final counters = <Map<String, dynamic>>[
      {
        'label': 'Active Charities',
        'value': charities.length,
        'color': _green,
        'prefix': '',
        'maxValue': 20,
      },
      {
        'label': 'Live Draw Pool',
        'value': liveDrawPoolDisplay,
        'color': _gold,
        'prefix': '\$',
        'maxValue': 999,
        'displayCap': 999,
      },
      {
        'label': '4-Match Pool',
        'value': match4PoolUsd > 0 ? match4PoolUsd : 15,
        'color': _sun,
        'prefix': '\$',
        'maxValue': 500,
      },
      {
        'label': '5-Match Base',
        'value': match5BaseUsd > 0 ? match5BaseUsd : 20,
        'color': _gold,
        'prefix': '\$',
        'maxValue': 750,
        'displayCap': 750,
      },
    ];

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            TopNavigationBar(
              activeItem: TopNavItem.jackpot,
              onNavigate: (item) => _onNavTap(context, item),
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
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: EdgeInsets.zero,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final horizontalPadding =
                        constraints.maxWidth < 640 ? 12.0 : 18.0;
                    final heroTitleSize =
                        constraints.maxWidth < 640 ? 28.0 : 34.0;
                    return Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints:
                            const BoxConstraints(maxWidth: _maxContentWidth),
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            horizontalPadding,
                            18,
                            horizontalPadding,
                            30,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(22),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(18),
                                  color: const Color(0xFFF8FBFE),
                                  border: Border.all(
                                      color: const Color(0xFFD7E4EF)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Play golf. Change lives. Win fairly.',
                                      style: TextStyle(
                                        fontSize: heroTitleSize,
                                        fontWeight: FontWeight.w800,
                                        color: const Color(0xFF0F172A),
                                        height: 1.1,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    const Text(
                                      'Track verified scores, support trusted charities, and win through transparent monthly 5-number draws.',
                                      style: TextStyle(
                                        color: Color(0xFF55677D),
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 18),
                                    Wrap(
                                      spacing: 10,
                                      runSpacing: 10,
                                      children: [
                                        _accentPill(
                                          text: 'Verified Rounds',
                                          color: _green,
                                          icon: Icons.verified_outlined,
                                        ),
                                        _accentPill(
                                          text: 'Fair Draw Engine',
                                          color: _gold,
                                          icon: Icons.emoji_events_outlined,
                                        ),
                                        _accentPill(
                                          text: 'Charity Impact',
                                          color: _sun,
                                          icon:
                                              Icons.volunteer_activism_outlined,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    Wrap(
                                      spacing: 10,
                                      runSpacing: 10,
                                      children: [
                                        SizedBox(
                                          height: 48,
                                          child: ElevatedButton.icon(
                                            onPressed: () =>
                                                _openOnboardingGate(context),
                                            icon: const Icon(
                                                Icons.rocket_launch_outlined),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: _green,
                                              foregroundColor: Colors.white,
                                            ),
                                            label: Text(
                                              auth.isAuthenticated
                                                  ? 'Continue Setup'
                                                  : 'Start Free',
                                            ),
                                          ),
                                        ),
                                        SizedBox(
                                          height: 48,
                                          child: OutlinedButton.icon(
                                            onPressed: _openCharityDirectory,
                                            icon: const Icon(
                                                Icons.travel_explore_outlined),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor:
                                                  const Color(0xFF1B5D86),
                                              side: BorderSide(
                                                color: _gold.withValues(
                                                    alpha: 0.55),
                                              ),
                                            ),
                                            label: const Text('Open Directory'),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 14),
                              LayoutBuilder(
                                builder: (context, counterConstraints) {
                                  final viewportHeight =
                                      MediaQuery.of(context).size.height;
                                  final counterGridHeight =
                                      (viewportHeight * 0.5)
                                          .clamp(300.0, 520.0)
                                          .toDouble();
                                  final childAspectRatio =
                                      counterConstraints.maxWidth < 430
                                          ? 0.9
                                          : 1.25;
                                  return SizedBox(
                                    height: counterGridHeight,
                                    child: GridView.builder(
                                      physics:
                                          const NeverScrollableScrollPhysics(),
                                      padding: EdgeInsets.zero,
                                      itemCount: counters.length,
                                      gridDelegate:
                                          SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: 2,
                                        mainAxisSpacing: 12,
                                        crossAxisSpacing: 12,
                                        childAspectRatio: childAspectRatio,
                                      ),
                                      itemBuilder: (context, index) {
                                        final counter = counters[index];
                                        return _LandingCounterCard(
                                          label: (counter['label'] ?? '')
                                              .toString(),
                                          value: (counter['value'] ?? 0) as int,
                                          color: (counter['color'] as Color?) ??
                                              const Color(0xFF1993D1),
                                          prefix: (counter['prefix'] ?? '')
                                              .toString(),
                                          maxValue:
                                              (counter['maxValue'] ?? 1) as int,
                                          displayCap:
                                              counter['displayCap'] as int?,
                                        );
                                      },
                                    ),
                                  );
                                },
                              ),
                              if (featuredCharity != null) ...[
                                const SizedBox(height: 28),
                                _spotlightCard(featuredCharity),
                              ],
                              const SizedBox(height: 28),
                              Container(
                                key: _charitiesKey,
                                child: Row(
                                  children: [
                                    const Expanded(
                                      child: Text(
                                        'Supported Charities',
                                        style: TextStyle(
                                          fontSize: 26,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF0F172A),
                                        ),
                                      ),
                                    ),
                                    OutlinedButton.icon(
                                      onPressed: _openCharityDirectory,
                                      icon: const Icon(Icons.search),
                                      label: const Text('Search & Filter'),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Browse the directory to filter by cause, open full charity profiles, and donate independently outside gameplay.',
                                style: TextStyle(
                                  color: Color(0xFF607289),
                                  height: 1.35,
                                ),
                              ),
                              const SizedBox(height: 14),
                              if (charityProvider.isLoading &&
                                  charities.isEmpty)
                                const Center(child: CircularProgressIndicator())
                              else if (charities.isEmpty)
                                const Card(
                                  child: ListTile(
                                    title: Text('No charities available yet'),
                                    subtitle: Text(
                                      'Admin can add charities from dashboard.',
                                    ),
                                  ),
                                )
                              else
                                LayoutBuilder(
                                  builder: (context, charityConstraints) {
                                    final isWide =
                                        charityConstraints.maxWidth > 900;
                                    if (isWide) {
                                      return Wrap(
                                        spacing: 12,
                                        runSpacing: 12,
                                        children: charityPreview
                                            .map(
                                              (c) => SizedBox(
                                                width: (charityConstraints
                                                            .maxWidth -
                                                        12) /
                                                    2,
                                                child: _charityCard(c),
                                              ),
                                            )
                                            .toList(),
                                      );
                                    }
                                    return Column(
                                      children: charityPreview
                                          .map(
                                            (c) => Padding(
                                              padding: const EdgeInsets.only(
                                                  bottom: 12),
                                              child: _charityCard(c),
                                            ),
                                          )
                                          .toList(),
                                    );
                                  },
                                ),
                              if (charities.isNotEmpty) ...[
                                const SizedBox(height: 14),
                                Center(
                                  child: TextButton.icon(
                                    onPressed: _openCharityDirectory,
                                    icon: const Icon(Icons.arrow_forward),
                                    label: const Text(
                                      'Browse the full charity directory',
                                    ),
                                  ),
                                ),
                              ],
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
}

class _LandingCounterCard extends StatefulWidget {
  const _LandingCounterCard({
    required this.label,
    required this.value,
    required this.color,
    required this.maxValue,
    this.prefix = '',
    this.displayCap,
  });

  final String label;
  final int value;
  final Color color;
  final String prefix;
  final int maxValue;
  final int? displayCap;

  @override
  State<_LandingCounterCard> createState() => _LandingCounterCardState();
}

class _LandingCounterCardState extends State<_LandingCounterCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Animation<double> _valueAnimation = const AlwaysStoppedAnimation(0);
  Animation<double> _progressAnimation = const AlwaysStoppedAnimation(0);

  bool _didAnimate = false;
  double _targetValue = 0;
  double _targetProgress = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );
    _updateTargets(widget.value);
    if (widget.value > 0) {
      _startAnimation();
    }
  }

  @override
  void didUpdateWidget(covariant _LandingCounterCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value == widget.value &&
        oldWidget.maxValue == widget.maxValue) {
      return;
    }

    _updateTargets(widget.value);
    if (!_didAnimate && widget.value > 0) {
      _startAnimation();
      return;
    }

    if (_didAnimate) {
      _valueAnimation = AlwaysStoppedAnimation(_targetValue);
      _progressAnimation = AlwaysStoppedAnimation(_targetProgress);
      setState(() {});
    }
  }

  void _updateTargets(int value) {
    final cappedByDisplay =
        widget.displayCap != null && value > widget.displayCap!;
    final displayValue = cappedByDisplay ? widget.displayCap! : value;

    _targetValue = displayValue.toDouble();

    final normalizer =
        widget.maxValue <= 0 ? math.max(value, 1) : widget.maxValue;
    _targetProgress = (value / normalizer).clamp(0.0, 1.0).toDouble();
  }

  void _startAnimation() {
    if (_didAnimate) return;
    _didAnimate = true;

    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _valueAnimation =
        Tween<double>(begin: 0, end: _targetValue).animate(curved);
    _progressAnimation =
        Tween<double>(begin: 0, end: _targetProgress).animate(curved);
    _controller.forward(from: 0);
  }

  String _formatValue(double value) {
    final whole = value.floor();
    return '${widget.prefix}$whole+';
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.label,
              style: TextStyle(
                color: widget.color,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            const Spacer(),
            Center(
              child: SizedBox(
                width: 94,
                height: 94,
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) {
                    final animatedProgress = _progressAnimation.value;
                    final animatedValue = _valueAnimation.value;
                    return CustomPaint(
                      painter: _GradientRingPainter(
                        progress: animatedProgress,
                      ),
                      child: Center(
                        child: Text(
                          _formatValue(animatedValue),
                          style: const TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}

class _GradientRingPainter extends CustomPainter {
  const _GradientRingPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final strokeWidth = size.width * 0.12;
    final radius = (size.width - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = const Color(0xFFE6EEF5);
    canvas.drawCircle(center, radius, trackPaint);

    if (progress <= 0) return;

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth
      ..shader = const SweepGradient(
        colors: [
          Color(0xFF1CA36B),
          Color(0xFFF4C542),
          Color(0xFFD4AF37),
          Color(0xFF1CA36B),
        ],
        stops: [0.0, 0.45, 0.82, 1.0],
        transform: GradientRotation(-math.pi / 2),
      ).createShader(rect);

    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * progress.clamp(0.0, 1.0),
      false,
      ringPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _GradientRingPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
