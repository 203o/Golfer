import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher_string.dart';
import '../services/auth_provider.dart';
import '../services/draw_provider.dart';
import '../services/charity_provider.dart';
import '../services/admin_analytics_provider.dart';
import '../services/admin_user_management_provider.dart';
import '../services/subscription_provider.dart';
import '../widgets/top_navigation_bar.dart';
import 'landing_screen.dart';

const double _kAdminMaxContentWidth = 1180;

Widget _adminContentFrame({
  required Widget child,
  EdgeInsetsGeometry? padding,
}) {
  return LayoutBuilder(
    builder: (context, constraints) {
      final horizontalPadding = constraints.maxWidth < 640 ? 12.0 : 16.0;
      return Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _kAdminMaxContentWidth),
          child: Padding(
            padding: padding ??
                EdgeInsets.fromLTRB(
                  horizontalPadding,
                  16,
                  horizontalPadding,
                  24,
                ),
            child: child,
          ),
        ),
      );
    },
  );
}

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen>
    with SingleTickerProviderStateMixin {
  static const Color _bg = Color(0xFF080B12);
  static const Color _panelBorder = Color(0xFF252D3D);
  static const Color _accent = Color(0xFFFF4FA3);
  static const Color _textPrimary = Color(0xFFF3F6FF);
  static const Color _textMuted = Color(0xFF9CA8C2);

  late final TabController _tabController;
  bool _didLoad = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didLoad) return;
    _didLoad = true;
    _loadData();
  }

  Future<void> _loadData() async {
    final drawProvider = context.read<DrawProvider>();
    final charityProvider = context.read<CharityProvider>();
    final analyticsProvider = context.read<AdminAnalyticsProvider>();
    final subscriptionProvider = context.read<SubscriptionProvider>();

    await Future.wait([
      drawProvider.loadAdminDraws(),
      charityProvider.loadCharities(),
      charityProvider.loadAdminDonationLedger(),
      analyticsProvider.loadAnalytics(days: 30),
      subscriptionProvider.loadSubscriptions(),
      context.read<AdminUserManagementProvider>().loadUsers(),
    ]);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _onAdminNavigate(TopNavItem item) {
    if (item != TopNavItem.jackpot) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LandingScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            TopNavigationBar(
              activeItem: TopNavItem.dashboard,
              onNavigate: _onAdminNavigate,
              restrictedMode: true,
              isDark: true,
              trailing: IconButton(
                tooltip: 'Logout',
                onPressed: () async {
                  await context.read<AuthProvider>().signOut();
                  if (!context.mounted) return;
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const LandingScreen()),
                    (route) => false,
                  );
                },
                icon: const Icon(Icons.logout, color: _textPrimary),
              ),
            ),
            Container(
              color: _bg,
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: _kAdminMaxContentWidth,
                  ),
                  child: TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    indicatorColor: _accent,
                    indicatorWeight: 3,
                    labelColor: _accent,
                    unselectedLabelColor: _textMuted,
                    dividerColor: _panelBorder,
                    tabs: const [
                      Tab(text: 'Overview'),
                      Tab(text: 'Draws'),
                      Tab(text: 'Charities'),
                      Tab(text: 'Users'),
                      Tab(text: 'Analytics'),
                      Tab(text: 'Trends'),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: const [
                  _OverviewTab(),
                  _DrawsTab(),
                  _CharitiesTab(),
                  _UsersTab(),
                  _AnalyticsTab(),
                  _TrendsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab();

  static const Color _bg = Color(0xFF080B12);
  static const Color _panel = Color(0xFF121722);
  static const Color _panelBorder = Color(0xFF252D3D);
  static const Color _textPrimary = Color(0xFFF3F6FF);
  static const Color _textMuted = Color(0xFF9CA8C2);
  static const Color _accent = Color(0xFFFF4FA3);

  Color _semanticColor(String key) {
    final v = key.toLowerCase();
    if (v.contains('high') ||
        v.contains('failed') ||
        v.contains('rejected') ||
        v.contains('fraud')) {
      return const Color(0xFFDC2626);
    }
    if (v.contains('pending') || v.contains('open') || v.contains('medium')) {
      return const Color(0xFFD97706);
    }
    if (v.contains('active') ||
        v.contains('completed') ||
        v.contains('paid') ||
        v.contains('accepted') ||
        v.contains('subscriber')) {
      return const Color(0xFF15803D);
    }
    if (v.contains('admin')) {
      return const Color(0xFF2563EB);
    }
    if (v.contains('guest') ||
        v.contains('declined') ||
        v.contains('cancelled') ||
        v.contains('expired') ||
        v.contains('revoked')) {
      return const Color(0xFF64748B);
    }
    return const Color(0xFF1D4ED8);
  }

  Widget _metricGrid(List<_AnalyticsMetricCardData> cards) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns =
            width >= 1080 ? 4 : (width >= 760 ? 3 : (width >= 480 ? 2 : 1));
        final ratio = columns >= 4
            ? 2.35
            : (columns == 3
                ? 2.05
                : (columns == 2 ? 1.75 : (width >= 360 ? 1.95 : 1.65)));
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: cards.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: ratio,
          ),
          itemBuilder: (context, index) {
            final card = cards[index];
            return Container(
              decoration: BoxDecoration(
                color: _panel,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: _panelBorder),
              ),
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (card.icon != null)
                        Icon(
                          card.icon,
                          size: 16,
                          color: card.dotColor,
                        ),
                      if (card.icon != null) const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          card.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _textMuted,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    card.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _textPrimary,
                      fontSize: 28,
                      height: 1.0,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: card.dotColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          card.caption,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: card.dotColor,
                            fontWeight: FontWeight.w600,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _sessionStatusBlock(Map<String, dynamic> map) {
    final rows = map.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    return Container(
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _panelBorder),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Session Status',
            style: TextStyle(
              color: _textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 10),
          if (rows.isEmpty)
            const Text('No data', style: TextStyle(color: _textMuted))
          else
            ...rows.map((e) {
              final color = _semanticColor(e.key);
              return Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        e.key,
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      '${e.value}',
                      style: const TextStyle(
                        color: _textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AdminAnalyticsProvider>();
    final data = provider.analytics;

    if (provider.isLoading && data == null) {
      return const ColoredBox(
        color: _bg,
        child: Center(child: CircularProgressIndicator(color: _accent)),
      );
    }

    if (provider.error != null && data == null) {
      return ColoredBox(
        color: _bg,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                provider.error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.redAccent),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => context
                    .read<AdminAnalyticsProvider>()
                    .loadAnalytics(days: 30),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (data == null) {
      return const ColoredBox(
        color: _bg,
        child: Center(
          child: Text(
            'No overview data yet',
            style: TextStyle(color: _textMuted),
          ),
        ),
      );
    }

    final kpis = Map<String, dynamic>.from(data['kpis'] ?? const {});
    final financial = Map<String, dynamic>.from(kpis['financial'] ?? const {});
    final engagement =
        Map<String, dynamic>.from(kpis['engagement'] ?? const {});
    final integrity = Map<String, dynamic>.from(kpis['integrity'] ?? const {});
    final breakdowns =
        Map<String, dynamic>.from(data['breakdowns'] ?? const {});
    final sessionStatus =
        Map<String, dynamic>.from(breakdowns['session_status'] ?? const {});

    final performanceCards = [
      _AnalyticsMetricCardData(
        title: 'Active Subscribers',
        value: '${financial['active_subscribers'] ?? 0}',
        caption: 'paying users',
        dotColor: const Color(0xFF2FD8A3),
        icon: Icons.groups_outlined,
      ),
      _AnalyticsMetricCardData(
        title: 'Sessions In Progress',
        value: '${engagement['sessions_in_progress'] ?? 0}',
        caption: 'live gameplay',
        dotColor: const Color(0xFF47B6FF),
        icon: Icons.sports_golf_outlined,
      ),
      _AnalyticsMetricCardData(
        title: 'Open Fraud Flags',
        value: '${integrity['open_fraud_flags'] ?? 0}',
        caption: 'needs review',
        dotColor: const Color(0xFFFF6E67),
        icon: Icons.shield_outlined,
      ),
      _AnalyticsMetricCardData(
        title: 'Unread Inbox',
        value: '${engagement['unread_inbox_messages'] ?? 0}',
        caption: 'system + invites',
        dotColor: const Color(0xFFFFC35A),
        icon: Icons.mail_outline,
      ),
    ];

    return ColoredBox(
      color: _bg,
      child: RefreshIndicator(
        color: _accent,
        backgroundColor: _panel,
        onRefresh: () =>
            context.read<AdminAnalyticsProvider>().loadAnalytics(days: 30),
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            _adminContentFrame(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Overview',
                    style: TextStyle(
                      color: _textPrimary,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Performance',
                    style: TextStyle(
                      color: _textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _metricGrid(performanceCards),
                  const SizedBox(height: 14),
                  _sessionStatusBlock(sessionStatus),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawsTab extends StatelessWidget {
  const _DrawsTab();

  static const Color _bg = Color(0xFF080B12);
  static const Color _panel = Color(0xFF121722);
  static const Color _panelBorder = Color(0xFF252D3D);
  static const Color _textPrimary = Color(0xFFF3F6FF);
  static const Color _textMuted = Color(0xFF9CA8C2);
  static const Color _accent = Color(0xFFFF4FA3);

  ButtonStyle _outlinedStyle() {
    return OutlinedButton.styleFrom(
      foregroundColor: _textPrimary,
      backgroundColor: _panel,
      side: const BorderSide(color: _panelBorder),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    );
  }

  ButtonStyle _filledStyle() {
    return ElevatedButton.styleFrom(
      foregroundColor: Colors.white,
      backgroundColor: _accent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    );
  }

  Widget _panelCard({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(14),
    EdgeInsetsGeometry margin = EdgeInsets.zero,
  }) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _panelBorder),
      ),
      child: child,
    );
  }

  Widget _smallSectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1420),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _panelBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: _accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: _textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Widget _scoreChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _ruleLine({
    required IconData icon,
    required String title,
    required String detail,
    Color iconColor = const Color(0xFF64B3FF),
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 16, color: iconColor),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$title: ',
                    style: const TextStyle(
                      color: _textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  TextSpan(
                    text: detail,
                    style: const TextStyle(
                      color: _textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _drawRewardSystemCard() {
    return _panelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Draw & Reward System',
            style: TextStyle(
              color: _textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Monthly draw rules, prize tiers, and release controls.',
            style: TextStyle(
              color: _textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final columns = width >= 960 ? 3 : (width >= 680 ? 2 : 1);
              final cardWidth = columns == 3
                  ? (width - 16) / 3
                  : columns == 2
                      ? (width - 8) / 2
                      : width;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  SizedBox(
                    width: cardWidth,
                    child: _smallSectionCard(
                      title: 'Draw Types',
                      icon: Icons.confirmation_number_outlined,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _scoreChip(
                                '5-Number Match', const Color(0xFFFFB454)),
                            _scoreChip(
                                '4-Number Match', const Color(0xFF64B3FF)),
                            _scoreChip(
                                '3-Number Match', const Color(0xFF2FD8A3)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: _smallSectionCard(
                      title: 'Draw Logic Options',
                      icon: Icons.auto_graph_outlined,
                      children: [
                        _ruleLine(
                          icon: Icons.casino_outlined,
                          title: 'Random generation',
                          detail: 'standard lottery-style draw',
                          iconColor: const Color(0xFFFFB454),
                        ),
                        _ruleLine(
                          icon: Icons.insights_outlined,
                          title: 'Algorithmic',
                          detail: 'weighted by most/least frequent user scores',
                          iconColor: const Color(0xFF64B3FF),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: _smallSectionCard(
                      title: 'Operational Requirements',
                      icon: Icons.schedule_outlined,
                      children: [
                        _ruleLine(
                          icon: Icons.calendar_month_outlined,
                          title: 'Monthly cadence',
                          detail: 'draws executed once per month',
                          iconColor: const Color(0xFF2FD8A3),
                        ),
                        _ruleLine(
                          icon: Icons.lock_outline,
                          title: 'Publishing control',
                          detail: 'admin controls publishing of draw results',
                          iconColor: const Color(0xFFFF4FA3),
                        ),
                        _ruleLine(
                          icon: Icons.science_outlined,
                          title: 'Simulation mode',
                          detail:
                              'pre-analysis before official publish is supported',
                          iconColor: const Color(0xFF64B3FF),
                        ),
                        _ruleLine(
                          icon: Icons.rotate_right_outlined,
                          title: 'Jackpot rollover',
                          detail:
                              'rolls to the next month if no 5-match winner',
                          iconColor: const Color(0xFFFFB454),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Map<String, dynamic>? _preferredDraw(List<dynamic> draws) {
    Map<String, dynamic>? firstDraw;
    Map<String, dynamic>? actionableDraw;
    for (final raw in draws) {
      if (raw is! Map) continue;
      final draw = raw.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      firstDraw ??= draw;
      final status = (draw['status'] ?? '').toString().toLowerCase();
      if (status != 'completed') {
        actionableDraw = draw;
        break;
      }
    }
    return actionableDraw ?? firstDraw;
  }

  String _drawSummary(Map<String, dynamic>? draw) {
    if (draw == null) return 'No draw selected';
    final monthKey = (draw['month_key'] ?? 'Draw').toString();
    final status = (draw['status'] ?? 'unknown').toString();
    final entries = _asInt(draw['entries_count'], 0);
    final winners = _asInt(draw['winner_count'], 0);
    return '$monthKey • $status • Entries: $entries • Winners: $winners';
  }

  Future<Map<String, dynamic>?> _ensureOpenDraw(BuildContext context) async {
    final provider = context.read<DrawProvider>();
    final candidate = _preferredDraw(provider.draws);
    final candidateStatus =
        (candidate?['status'] ?? '').toString().toLowerCase();
    if (candidate != null && candidateStatus != 'completed') {
      return candidate;
    }

    final now = DateTime.now();
    final drawDate = DateTime(now.year, now.month, 1);
    try {
      await provider.createDraw('', '', drawDate);
    } catch (_) {
      await provider.loadAdminDraws();
    }
    final refreshed = _preferredDraw(provider.draws);
    final refreshedStatus =
        (refreshed?['status'] ?? '').toString().toLowerCase();
    return refreshedStatus == 'completed' ? null : refreshed;
  }

  int _asInt(dynamic value, int fallback) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse((value ?? '').toString()) ?? fallback;
  }

  String _usdFromCents(int cents) {
    return '\$${(cents / 100).toStringAsFixed(2)}';
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map(
        (key, item) => MapEntry(key.toString(), item),
      );
    }
    return const <String, dynamic>{};
  }

  String _previewTierSummary(Map<String, dynamic> preview) {
    final tiers = _asMap(preview['tier_summary']);
    final match5 = _asMap(tiers['match_5']);
    final match4 = _asMap(tiers['match_4']);
    final match3 = _asMap(tiers['match_3']);
    return '5-match: ${match5['winner_count'] ?? 0} • 4-match: ${match4['winner_count'] ?? 0} • 3-match: ${match3['winner_count'] ?? 0}';
  }

  List<dynamic> _asList(dynamic value) {
    if (value is List) return value;
    return const [];
  }

  String _claimReviewLabel(String rawStatus) {
    switch (rawStatus.trim().toLowerCase()) {
      case 'approved':
        return 'Approved';
      case 'rejected':
        return 'Rejected';
      default:
        return 'Pending Review';
    }
  }

  String _claimPayoutLabel(String rawStatus) {
    switch (rawStatus.trim().toLowerCase()) {
      case 'paid':
        return 'Paid';
      default:
        return 'Pending';
    }
  }

  Color _claimReviewColor(String rawStatus) {
    switch (rawStatus.trim().toLowerCase()) {
      case 'approved':
        return const Color(0xFF2FD8A3);
      case 'rejected':
        return const Color(0xFFFFA94A);
      default:
        return const Color(0xFF64B3FF);
    }
  }

  Color _claimPayoutColor(String rawStatus) {
    switch (rawStatus.trim().toLowerCase()) {
      case 'paid':
        return const Color(0xFF2FD8A3);
      default:
        return const Color(0xFFFFB454);
    }
  }

  String _formatTimestamp(dynamic value) {
    final raw = (value ?? '').toString().trim();
    if (raw.isEmpty) return 'Not recorded';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    final local = parsed.toLocal();
    String twoDigits(int input) => input.toString().padLeft(2, '0');
    return '${local.year}-${twoDigits(local.month)}-${twoDigits(local.day)} ${twoDigits(local.hour)}:${twoDigits(local.minute)}';
  }

  Widget _statusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }

  Future<void> _openExternalUrl(
    BuildContext context,
    String? url,
  ) async {
    final value = (url ?? '').trim();
    if (value.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final opened = await launchUrlString(
        value,
        mode: LaunchMode.externalApplication,
      );
      if (!opened && context.mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Could not open proof link')),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Could not open proof link: $e')),
      );
    }
  }

  Future<void> _reviewClaimDialog(
    BuildContext context, {
    required String claimId,
    required String action,
  }) async {
    final notesController = TextEditingController();
    final approve = action.trim().toLowerCase() == 'approve';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF111725),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: _panelBorder),
        ),
        title: Text(
          approve ? 'Approve Winner Proof' : 'Reject Winner Proof',
          style: const TextStyle(
            color: _textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: TextField(
          controller: notesController,
          minLines: 3,
          maxLines: 5,
          style: const TextStyle(color: _textPrimary),
          decoration: InputDecoration(
            labelText: approve ? 'Approval note (optional)' : 'Rejection note',
            hintText: approve
                ? 'Optional context for the winner'
                : 'Explain why the proof was rejected',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: approve
                ? _filledStyle()
                : ElevatedButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.orangeAccent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                  ),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final navigator = Navigator.of(dialogContext);
              final drawProvider = context.read<DrawProvider>();
              try {
                await drawProvider.reviewWinnerClaim(
                  claimId: claimId,
                  action: action,
                  reviewNotes: notesController.text.trim(),
                );
                navigator.pop();
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      approve
                          ? 'Winner proof approved'
                          : 'Winner proof rejected',
                    ),
                  ),
                );
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(content: Text('Review action failed: $e')),
                );
              }
            },
            child: Text(approve ? 'Approve' : 'Reject'),
          ),
        ],
      ),
    );
  }

  Future<void> _openPrizeSettingsDialog(
    BuildContext context,
    Map<String, dynamic>? settings,
  ) async {
    final minEventsController = TextEditingController(
      text: _asInt(settings?['monthly_min_events_required'], 5).toString(),
    );

    bool saving = false;
    String? inlineError;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setModalState) => AlertDialog(
          backgroundColor: const Color(0xFF111725),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: _panelBorder),
          ),
          title: const Text(
            'Draw Controls',
            style: TextStyle(color: _textPrimary, fontWeight: FontWeight.w800),
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0E1420),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _panelBorder),
                  ),
                  child: const Text(
                    '30% of each active subscription funds the monthly prize pool. Distribution is fixed and enforced automatically: 5-match 40%, 4-match 35%, and 3-match 25%. Only the 5-match tier rolls over.',
                    style: TextStyle(
                      color: _textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                _settingsInput(
                  controller: minEventsController,
                  label: 'Minimum entries before simulation',
                  isInteger: true,
                ),
                if ((inlineError ?? '').isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      inlineError!,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                if (saving) ...[
                  const SizedBox(height: 12),
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text(
                'Cancel',
                style: TextStyle(color: _textMuted),
              ),
            ),
            ElevatedButton(
              style: _filledStyle(),
              onPressed: saving
                  ? null
                  : () async {
                      final minEvents =
                          int.tryParse(minEventsController.text.trim()) ?? -1;
                      if (minEvents < 0) {
                        setModalState(() {
                          inlineError = 'Use a valid non-negative value.';
                        });
                        return;
                      }
                      if (minEvents < 1) {
                        setModalState(() {
                          inlineError = 'Minimum events must be at least 1.';
                        });
                        return;
                      }
                      setModalState(() {
                        inlineError = null;
                        saving = true;
                      });
                      try {
                        await context.read<DrawProvider>().updateDrawSettings(
                              weeklyPrizeCents: _asInt(
                                  settings?['weekly_prize_cents'], 50000),
                              monthlyFirstPrizeCents: _asInt(
                                settings?['monthly_first_prize_cents'],
                                200000,
                              ),
                              monthlySecondPrizeCents: _asInt(
                                settings?['monthly_second_prize_cents'],
                                150000,
                              ),
                              monthlyThirdPrizeCents: _asInt(
                                settings?['monthly_third_prize_cents'],
                                100000,
                              ),
                              monthlyMinEventsRequired: minEvents,
                            );
                        if (!context.mounted) return;
                        Navigator.pop(dialogContext);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Monthly draw settings updated'),
                          ),
                        );
                      } catch (e) {
                        setModalState(() {
                          saving = false;
                          inlineError = e.toString();
                        });
                      }
                    },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _settingsInput({
    required TextEditingController controller,
    required String label,
    bool isInteger = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType: isInteger
          ? TextInputType.number
          : const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(color: _textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: _textMuted),
        filled: true,
        fillColor: const Color(0xFF0E1420),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _panelBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _accent),
        ),
      ),
    );
  }

  Widget _summaryMetric({
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1420),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _panelBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: _textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _markClaimPaidDialog(
    BuildContext context,
    String claimId,
  ) async {
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Mark Payout Completed'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Payout reference',
            hintText: 'e.g. BANK-TRX-2026-001',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final reference = controller.text.trim();
              if (reference.isEmpty) return;
              final messenger = ScaffoldMessenger.of(context);
              final navigator = Navigator.of(dialogContext);
              final drawProvider = context.read<DrawProvider>();
              try {
                await drawProvider.markClaimPaid(
                  claimId: claimId,
                  payoutReference: reference,
                );
                navigator.pop();
                messenger.showSnackBar(
                  const SnackBar(content: Text('Payout marked as completed')),
                );
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(content: Text('Mark paid failed: $e')),
                );
              }
            },
            child: const Text('Mark Paid'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final drawProvider = context.watch<DrawProvider>();
    final latestRun = drawProvider.lastRunResult;
    final latestRunPool = latestRun == null
        ? const <String, dynamic>{}
        : (latestRun.containsKey('preview')
            ? _asMap(_asMap(latestRun['preview'])['pool_breakdown'])
            : _asMap(latestRun['pool_breakdown']));
    final settings = drawProvider.drawSettings ?? const <String, dynamic>{};
    final monthlyMinEvents = _asInt(settings['monthly_min_events_required'], 5);
    final contributionPct =
        ((_asInt(settings['subscription_contribution_bps'], 3000)) / 100)
            .toStringAsFixed(0);
    final winnerClaims = drawProvider.adminWinnerClaims;
    final winners = drawProvider.adminWinners;
    final report = drawProvider.adminReportSummary ?? const <String, dynamic>{};
    final drawStats = (report['draw_statistics'] as Map<String, dynamic>?) ??
        const <String, dynamic>{};
    final quickDrawTarget = _preferredDraw(drawProvider.draws);
    final quickDrawId = quickDrawTarget?['id']?.toString() ?? '';
    final quickDrawReady = quickDrawId.isNotEmpty &&
        (quickDrawTarget?['status'] ?? '').toString().toLowerCase() !=
            'completed';

    return ColoredBox(
      color: _bg,
      child: Column(
        children: [
          _adminContentFrame(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Text(
                      'Draw Operations',
                      style: TextStyle(
                        color: _textPrimary,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _drawRewardSystemCard(),
                const SizedBox(height: 10),
                _panelCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Prize Pool Policy',
                        style: TextStyle(
                          color: _textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '$contributionPct% of active subscription value funds each monthly draw.',
                        style: const TextStyle(
                          color: _textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Distribution is fixed: 5-match 40%, 4-match 35%, 3-match 25%. Simulate only after at least $monthlyMinEvents entries are in the draw.',
                        style: const TextStyle(
                          color: _textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        style: _outlinedStyle(),
                        onPressed: () =>
                            _openPrizeSettingsDialog(context, settings),
                        icon: const Icon(Icons.tune),
                        label: const Text('Edit Draw Controls'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      style: _outlinedStyle(),
                      onPressed: () async {
                        await context.read<DrawProvider>().loadAdminDraws();
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Refresh'),
                    ),
                    ElevatedButton.icon(
                      style: _filledStyle(),
                      onPressed: () async {
                        final now = DateTime.now();
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: now,
                          firstDate: DateTime(now.year - 2, 1, 1),
                          lastDate: DateTime(now.year + 3, 12, 31),
                          helpText: 'Select Draw Month',
                        );
                        if (picked == null || !context.mounted) return;
                        try {
                          await context.read<DrawProvider>().createDraw(
                              '', '', DateTime(picked.year, picked.month, 1));
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Draw created for ${picked.year}-${picked.month.toString().padLeft(2, '0')}',
                              ),
                            ),
                          );
                        } catch (e) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Create draw failed: $e')),
                          );
                        }
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Create Draw'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _panelCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Simulation / Run Draw',
                        style: TextStyle(
                          color: _textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        quickDrawReady
                            ? 'Target: ${_drawSummary(quickDrawTarget)}'
                            : 'No open draw is available. Create the current month draw or let a control create it for you.',
                        style: const TextStyle(
                          color: _textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ElevatedButton.icon(
                            style: _filledStyle(),
                            onPressed: () async {
                              final drawProvider = context.read<DrawProvider>();
                              final messenger = ScaffoldMessenger.of(context);
                              try {
                                await drawProvider.createDraw(
                                  '',
                                  '',
                                  DateTime(DateTime.now().year,
                                      DateTime.now().month, 1),
                                );
                                if (!context.mounted) return;
                                messenger.showSnackBar(
                                  const SnackBar(
                                    content: Text('Current month draw created'),
                                  ),
                                );
                              } catch (e) {
                                if (!context.mounted) return;
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text('Create draw failed: $e'),
                                  ),
                                );
                              }
                            },
                            icon: const Icon(Icons.add),
                            label: const Text('Create Current Month Draw'),
                          ),
                          OutlinedButton.icon(
                            style: _outlinedStyle(),
                            onPressed: () async {
                              final drawProvider = context.read<DrawProvider>();
                              final messenger = ScaffoldMessenger.of(context);
                              try {
                                final target = await _ensureOpenDraw(context);
                                if (target == null) {
                                  if (!context.mounted) return;
                                  messenger.showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Create an open draw first to simulate it.',
                                      ),
                                    ),
                                  );
                                  return;
                                }
                                final result = await drawProvider.simulateDraw(
                                  drawId: target['id'].toString(),
                                  logicMode: 'random',
                                );
                                if (!context.mounted) return;
                                final preview = _asMap(result['preview']);
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Random simulation ready. ${_previewTierSummary(preview)}',
                                    ),
                                  ),
                                );
                              } catch (e) {
                                if (!context.mounted) return;
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Random simulation failed: $e',
                                    ),
                                  ),
                                );
                              }
                            },
                            icon: const Icon(Icons.casino_outlined),
                            label: const Text('Simulate Random'),
                          ),
                          OutlinedButton.icon(
                            style: _outlinedStyle(),
                            onPressed: () async {
                              final drawProvider = context.read<DrawProvider>();
                              final messenger = ScaffoldMessenger.of(context);
                              try {
                                final target = await _ensureOpenDraw(context);
                                if (target == null) {
                                  if (!context.mounted) return;
                                  messenger.showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Create an open draw first to simulate it.',
                                      ),
                                    ),
                                  );
                                  return;
                                }
                                final result = await drawProvider.simulateDraw(
                                  drawId: target['id'].toString(),
                                  logicMode: 'algorithmic',
                                );
                                if (!context.mounted) return;
                                final preview = _asMap(result['preview']);
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Algorithmic simulation ready. ${_previewTierSummary(preview)}',
                                    ),
                                  ),
                                );
                              } catch (e) {
                                if (!context.mounted) return;
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Algorithmic simulation failed: $e',
                                    ),
                                  ),
                                );
                              }
                            },
                            icon: const Icon(Icons.auto_graph_outlined),
                            label: const Text('Simulate Algorithmic'),
                          ),
                          ElevatedButton.icon(
                            style: _filledStyle(),
                            onPressed: () async {
                              final drawProvider = context.read<DrawProvider>();
                              final messenger = ScaffoldMessenger.of(context);
                              try {
                                final target = await _ensureOpenDraw(context);
                                if (target == null) {
                                  if (!context.mounted) return;
                                  messenger.showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Create an open draw first to run it.',
                                      ),
                                    ),
                                  );
                                  return;
                                }
                                await drawProvider
                                    .selectWinner(target['id'].toString());
                                if (!context.mounted) return;
                                messenger.showSnackBar(
                                  const SnackBar(
                                    content: Text('Draw run submitted'),
                                  ),
                                );
                              } catch (e) {
                                if (!context.mounted) return;
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text('Run draw failed: $e'),
                                  ),
                                );
                              }
                            },
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('Run & Publish'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (latestRun != null)
            _adminContentFrame(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: _panelCard(
                child: Row(
                  children: [
                    const Icon(
                      Icons.emoji_events_outlined,
                      color: Color(0xFFFFB454),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            latestRun.containsKey('preview')
                                ? 'Simulation ready for review'
                                : 'Monthly draw published',
                            style: const TextStyle(
                              color: _textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            latestRun.containsKey('preview')
                                ? 'Logic: ${_asMap(latestRun['preview'])['logic_mode'] ?? 'random'} • ${_previewTierSummary(_asMap(latestRun['preview']))}'
                                : 'Numbers: ${((latestRun['numbers'] as List?) ?? const []).join(', ')} • 5-match rollover: ${_usdFromCents(_asInt(latestRun['rollover_cents'], 0))}',
                            style: const TextStyle(
                              color: _textMuted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (latestRunPool.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              'Active subscribers: ${latestRunPool['active_subscriber_count'] ?? 0} • Pool: ${_usdFromCents(_asInt(latestRunPool['pool_total_cents'], 0))}',
                              style: const TextStyle(
                                color: _textMuted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          _adminContentFrame(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: _panelCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Reports & Analytics',
                          style: TextStyle(
                            color: _textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      OutlinedButton.icon(
                        style: _outlinedStyle(),
                        onPressed: () async {
                          await context
                              .read<DrawProvider>()
                              .loadAdminReportSummary();
                        },
                        icon: const Icon(Icons.refresh),
                        label: const Text('Refresh'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth;
                      final columns = width >= 920
                          ? 4
                          : (width >= 640 ? 3 : (width >= 420 ? 2 : 1));
                      final metrics = [
                        _summaryMetric(
                          label: 'Total Users',
                          value: '${report['total_users'] ?? 0}',
                          color: const Color(0xFF64B3FF),
                        ),
                        _summaryMetric(
                          label: 'Total Prize Pool',
                          value: _usdFromCents(
                              _asInt(report['total_prize_pool_cents'], 0)),
                          color: const Color(0xFFFFB454),
                        ),
                        _summaryMetric(
                          label: 'Total Draws',
                          value: '${drawStats['total_draws'] ?? 0}',
                          color: const Color(0xFF2FD8A3),
                        ),
                        _summaryMetric(
                          label: 'Winner Entries',
                          value: '${drawStats['winner_entries'] ?? 0}',
                          color: const Color(0xFFFF4FA3),
                        ),
                      ];
                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: metrics.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          childAspectRatio: 2.3,
                        ),
                        itemBuilder: (_, idx) => metrics[idx],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Scrollbar(
              thumbVisibility: true,
              trackVisibility: true,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
                child: Column(
                children: [
                  if (drawProvider.draws.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        'No draws yet. Create one to begin.',
                        style: TextStyle(color: _textMuted),
                      ),
                    )
                  else
                    ...drawProvider.draws.map((draw) {
                      final drawId = (draw['id'] ?? '').toString();
                      final status = (draw['status'] ?? 'unknown').toString();
                      final preview = _asMap(draw['preview']);
                      final poolBreakdown = _asMap(draw['pool_breakdown']);
                      final poolTiers = _asMap(poolBreakdown['tier_summary']);
                      final match5Pool =
                          _asInt(_asMap(poolTiers['match_5'])['pool_cents'], 0);
                      final match4Pool =
                          _asInt(_asMap(poolTiers['match_4'])['pool_cents'], 0);
                      final match3Pool =
                          _asInt(_asMap(poolTiers['match_3'])['pool_cents'], 0);
                      final previewNumbers =
                          ((preview['numbers'] as List?) ?? const [])
                              .map((item) => item.toString())
                              .join(', ');
                      final logicMode =
                          (preview['logic_mode'] ?? 'random').toString();
                      final activeSubscribers =
                          _asInt(draw['active_subscriber_count'], 0);
                      final canSimulate =
                          drawId.isNotEmpty && status != 'completed';
                      final canPublish =
                          drawId.isNotEmpty && status == 'closed';
                      final statusColor = status == 'completed'
                          ? const Color(0xFF2FD8A3)
                          : const Color(0xFFFFB454);
                      return _adminContentFrame(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                        child: _panelCard(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                draw['month_key']?.toString() ?? 'Draw',
                                style: const TextStyle(
                                  color: _textPrimary,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: statusColor,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Status: $status • Entries: ${draw['entries_count'] ?? 0} • Published winners: ${draw['winner_count'] ?? 0}',
                                      style: const TextStyle(
                                        color: _textMuted,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Carry-in jackpot: ${_usdFromCents(_asInt(draw['jackpot_carry_in_cents'], 0))}',
                                style: const TextStyle(
                                  color: _textMuted,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Active subscribers: $activeSubscribers • Monthly pool: ${_usdFromCents(_asInt(draw['pool_total_cents'], 0))}',
                                style: const TextStyle(
                                  color: _textMuted,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Tier pools → 5-match: ${_usdFromCents(match5Pool)} • 4-match: ${_usdFromCents(match4Pool)} • 3-match: ${_usdFromCents(match3Pool)}',
                                style: const TextStyle(
                                  color: _textMuted,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (preview.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  'Logic: $logicMode • ${_previewTierSummary(preview)}',
                                  style: const TextStyle(
                                    color: _textMuted,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (previewNumbers.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    status == 'completed'
                                        ? 'Published numbers: $previewNumbers'
                                        : 'Preview numbers: $previewNumbers',
                                    style: const TextStyle(
                                      color: _textPrimary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                                if (_asInt(preview['rollover_cents'], 0) >
                                    0) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    '5-match rollover if published: ${_usdFromCents(_asInt(preview['rollover_cents'], 0))}',
                                    style: const TextStyle(
                                      color: Color(0xFFFFB454),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ],
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  if (canSimulate)
                                    OutlinedButton.icon(
                                      style: _outlinedStyle(),
                                      onPressed: () async {
                                        try {
                                          final result = await context
                                              .read<DrawProvider>()
                                              .simulateDraw(
                                                drawId: drawId,
                                                logicMode: 'random',
                                              );
                                          if (!context.mounted) return;
                                          final preview =
                                              _asMap(result['preview']);
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                'Random simulation ready. ${_previewTierSummary(preview)}',
                                              ),
                                            ),
                                          );
                                        } catch (e) {
                                          if (!context.mounted) return;
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                'Random simulation failed: $e',
                                              ),
                                            ),
                                          );
                                        }
                                      },
                                      icon: const Icon(Icons.casino_outlined),
                                      label: const Text('Simulate Random'),
                                    ),
                                  if (canSimulate)
                                    OutlinedButton.icon(
                                      style: _outlinedStyle(),
                                      onPressed: () async {
                                        try {
                                          final result = await context
                                              .read<DrawProvider>()
                                              .simulateDraw(
                                                drawId: drawId,
                                                logicMode: 'algorithmic',
                                              );
                                          if (!context.mounted) return;
                                          final preview =
                                              _asMap(result['preview']);
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                'Algorithmic simulation ready. ${_previewTierSummary(preview)}',
                                              ),
                                            ),
                                          );
                                        } catch (e) {
                                          if (!context.mounted) return;
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                'Algorithmic simulation failed: $e',
                                              ),
                                            ),
                                          );
                                        }
                                      },
                                      icon: const Icon(Icons.insights_outlined),
                                      label: const Text('Simulate Algorithmic'),
                                    ),
                                  if (canPublish)
                                    ElevatedButton.icon(
                                      style: _filledStyle(),
                                      onPressed: () async {
                                        try {
                                          final result = await context
                                              .read<DrawProvider>()
                                              .publishDraw(drawId);
                                          if (!context.mounted) return;
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                'Published ${result['month_key'] ?? 'draw'} with ${((result['numbers'] as List?) ?? const []).join(', ')}',
                                              ),
                                            ),
                                          );
                                        } catch (e) {
                                          if (!context.mounted) return;
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                'Publish failed: $e',
                                              ),
                                            ),
                                          );
                                        }
                                      },
                                      icon: const Icon(Icons.publish_outlined),
                                      label: const Text('Publish Results'),
                                    ),
                                  if (status == 'completed')
                                    const Icon(
                                      Icons.check_circle,
                                      color: Color(0xFF2FD8A3),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  _adminContentFrame(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: _panelCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'Winner Verification System',
                                  style: TextStyle(
                                    color: _textPrimary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              OutlinedButton.icon(
                                style: _outlinedStyle(),
                                onPressed: () async {
                                  await context
                                      .read<DrawProvider>()
                                      .loadWinnerClaims();
                                },
                                icon: const Icon(Icons.refresh),
                                label: const Text('Refresh'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Winners only. Review screenshot proof from the golf platform, approve or reject the submission, then move payment from Pending to Paid.',
                            style: TextStyle(
                              color: _textMuted,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 10),
                          if (winnerClaims.isEmpty)
                            const Text(
                              'No winner claims yet.',
                              style: TextStyle(color: _textMuted),
                            )
                          else
                            ...winnerClaims.map((claim) {
                              final claimId = (claim['id'] ?? '').toString();
                              final username =
                                  (claim['username'] ?? 'Winner').toString();
                              final email = (claim['email'] ?? '').toString();
                              final drawKey =
                                  (claim['draw_key'] ?? 'Monthly Draw')
                                      .toString();
                              final tierLabel =
                                  (claim['tier_label'] ?? 'Match').toString();
                              final payoutCents =
                                  _asInt(claim['payout_cents'], 0);
                              final proofUrl =
                                  (claim['proof_url'] ?? '').toString().trim();
                              final reviewNotes = (claim['review_notes'] ?? '')
                                  .toString()
                                  .trim();
                              final payoutReference =
                                  (claim['payout_reference'] ?? '')
                                      .toString()
                                      .trim();
                              final entryNumbers = _asList(
                                claim['entry_numbers'],
                              ).map((item) => item.toString()).join(', ');
                              final reviewStatus =
                                  (claim['review_status'] ?? 'pending')
                                      .toString();
                              final payoutState =
                                  (claim['payout_state'] ?? 'pending')
                                      .toString();
                              final winnerLabel = email.isEmpty
                                  ? username
                                  : '$username ($email)';
                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0E1420),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: _panelBorder),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if ((claim['show_legacy_summary'] ??
                                            false) ==
                                        true) ...[
                                      Text(
                                        'Claim $claimId • User ${claim['user_id']}',
                                        style: const TextStyle(
                                          color: _textPrimary,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Review: $reviewStatus • Payout: $payoutState',
                                        style: const TextStyle(
                                          color: _textMuted,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                    ],
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        _statusChip(
                                          'Verification: ${_claimReviewLabel(reviewStatus)}',
                                          _claimReviewColor(reviewStatus),
                                        ),
                                        _statusChip(
                                          'Payment: ${_claimPayoutLabel(payoutState)}',
                                          _claimPayoutColor(payoutState),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      winnerLabel,
                                      style: const TextStyle(
                                        color: _textPrimary,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '$drawKey | $tierLabel | ${_usdFromCents(payoutCents)}',
                                      style: const TextStyle(
                                        color: _textMuted,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Claim ID: $claimId',
                                      style: const TextStyle(
                                        color: _textMuted,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Proof Upload: Screenshot of scores from the golf platform',
                                      style: const TextStyle(
                                        color: _textPrimary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (entryNumbers.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        'Winning numbers: $entryNumbers',
                                        style: const TextStyle(
                                          color: _textMuted,
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 4),
                                    Text(
                                      'Last submission: ${_formatTimestamp(claim['updated_at'] ?? claim['created_at'])}',
                                      style: const TextStyle(
                                        color: _textMuted,
                                      ),
                                    ),
                                    if (reviewNotes.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Text(
                                        'Admin note: $reviewNotes',
                                        style: const TextStyle(
                                          color: _textPrimary,
                                        ),
                                      ),
                                    ],
                                    if (payoutReference.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Text(
                                        'Payout reference: $payoutReference',
                                        style: const TextStyle(
                                          color: _textPrimary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 10),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        if (proofUrl.isNotEmpty)
                                          OutlinedButton.icon(
                                            style: _outlinedStyle(),
                                            onPressed: () => _openExternalUrl(
                                              context,
                                              proofUrl,
                                            ),
                                            icon: const Icon(
                                              Icons.open_in_new_outlined,
                                            ),
                                            label: const Text('Open Proof'),
                                          ),
                                        OutlinedButton(
                                          style: _outlinedStyle(),
                                          onPressed: reviewStatus == 'pending'
                                              ? () => _reviewClaimDialog(
                                                    context,
                                                    claimId: claimId,
                                                    action: 'approve',
                                                  )
                                              : null,
                                          child: const Text('Approve'),
                                        ),
                                        OutlinedButton(
                                          style: _outlinedStyle().copyWith(
                                            foregroundColor:
                                                WidgetStateProperty.all(
                                                    Colors.orangeAccent),
                                          ),
                                          onPressed: reviewStatus == 'pending'
                                              ? () => _reviewClaimDialog(
                                                    context,
                                                    claimId: claimId,
                                                    action: 'reject',
                                                  )
                                              : null,
                                          child: const Text('Reject'),
                                        ),
                                        ElevatedButton(
                                          style: _filledStyle(),
                                          onPressed:
                                              reviewStatus == 'approved' &&
                                                      payoutState != 'paid'
                                                  ? () => _markClaimPaidDialog(
                                                      context, claimId)
                                                  : null,
                                          child: const Text('Mark Paid'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            }),
                        ],
                      ),
                    ),
                  ),
                  _adminContentFrame(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                    child: _panelCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'Full Winners List',
                                  style: TextStyle(
                                    color: _textPrimary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              OutlinedButton.icon(
                                style: _outlinedStyle(),
                                onPressed: () async {
                                  await context
                                      .read<DrawProvider>()
                                      .loadFullWinners();
                                },
                                icon: const Icon(Icons.refresh),
                                label: const Text('Refresh'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (winners.isEmpty)
                            const Text(
                              'No winners yet.',
                              style: TextStyle(color: _textMuted),
                            )
                          else
                            ...winners.map((w) => Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0E1420),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: _panelBorder),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '${w['draw_key']} • ${w['username']} (${w['email']}) • ${(w['tier_label'] ?? 'Match')} • ${_usdFromCents(_asInt(w['payout_cents'], 0))}',
                                          style: const TextStyle(
                                            color: _textMuted,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        ((w['payout_state'] ?? 'pending')
                                                .toString())
                                            .toUpperCase(),
                                        style: TextStyle(
                                          color: (w['payout_state'] == 'paid')
                                              ? const Color(0xFF2FD8A3)
                                              : const Color(0xFFFFB454),
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                )),
                        ],
                      ),
                    ),
                  ),
                ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CharitiesTab extends StatelessWidget {
  const _CharitiesTab();

  static const Color _bg = Color(0xFF080B12);
  static const Color _panel = Color(0xFF121722);
  static const Color _panelBorder = Color(0xFF252D3D);
  static const Color _textPrimary = Color(0xFFF3F6FF);
  static const Color _textMuted = Color(0xFF9CA8C2);
  static const Color _accent = Color(0xFFFF4FA3);

  ButtonStyle _outlinedStyle() {
    return OutlinedButton.styleFrom(
      foregroundColor: _textPrimary,
      backgroundColor: _panel,
      side: const BorderSide(color: _panelBorder),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    );
  }

  ButtonStyle _filledStyle() {
    return ElevatedButton.styleFrom(
      foregroundColor: Colors.white,
      backgroundColor: _accent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    );
  }

  Widget _panelCard({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(14),
    EdgeInsetsGeometry margin = EdgeInsets.zero,
  }) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _panelBorder),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final charityProvider = context.watch<CharityProvider>();
    final ledgerSummary = charityProvider.adminDonationSummary;
    final donationEntries = charityProvider.adminDonationEntries;

    return ColoredBox(
      color: _bg,
      child: Column(
        children: [
          _adminContentFrame(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Charity Management',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: _textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      style: _outlinedStyle(),
                      onPressed: () async {
                        await context
                            .read<CharityProvider>()
                            .loadAdminDonationLedger();
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Refresh Ledger'),
                    ),
                    ElevatedButton.icon(
                      style: _filledStyle(),
                      onPressed: () async {
                        final nameController = TextEditingController();
                        final descriptionController = TextEditingController();
                        final websiteController = TextEditingController();
                        final formKey = GlobalKey<FormState>();
                        await showDialog<void>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Add Charity'),
                            content: Form(
                              key: formKey,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextFormField(
                                    controller: nameController,
                                    decoration: const InputDecoration(
                                        labelText: 'Charity Name'),
                                    validator: (v) =>
                                        (v == null || v.trim().length < 2)
                                            ? 'Enter charity name'
                                            : null,
                                  ),
                                  const SizedBox(height: 8),
                                  TextFormField(
                                    controller: descriptionController,
                                    decoration: const InputDecoration(
                                        labelText: 'Description'),
                                  ),
                                  const SizedBox(height: 8),
                                  TextFormField(
                                    controller: websiteController,
                                    decoration: const InputDecoration(
                                        labelText: 'Website URL'),
                                  ),
                                ],
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Cancel'),
                              ),
                              ElevatedButton(
                                onPressed: () async {
                                  if (!formKey.currentState!.validate()) return;
                                  try {
                                    await context
                                        .read<CharityProvider>()
                                        .createCharity(
                                          nameController.text.trim(),
                                          descriptionController.text.trim(),
                                          websiteController.text.trim(),
                                        );
                                    if (!context.mounted) return;
                                    Navigator.pop(context);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text('Charity created')),
                                    );
                                  } catch (e) {
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                          content: Text('Create failed: $e')),
                                    );
                                  }
                                },
                                child: const Text('Create'),
                              ),
                            ],
                          ),
                        );
                      },
                      icon: const Icon(Icons.add_business),
                      label: const Text('Add Charity'),
                    ),
                    OutlinedButton.icon(
                      style: _outlinedStyle(),
                      onPressed: () async {
                        try {
                          final result = await context
                              .read<CharityProvider>()
                              .seedDefaultCharities();
                          if (!context.mounted) return;
                          final created =
                              (result['created'] as List<dynamic>? ?? const [])
                                  .length;
                          final skipped =
                              (result['skipped'] as List<dynamic>? ?? const [])
                                  .length;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text(
                                    'Seeded charities. Created: $created, skipped: $skipped')),
                          );
                        } catch (e) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Seed failed: $e')),
                          );
                        }
                      },
                      icon:
                          const Icon(Icons.playlist_add_check_circle_outlined),
                      label: const Text('Add Provided List'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.zero,
              child: _adminContentFrame(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ...charityProvider.charities.map((charity) {
                      final charityId = (charity['id'] ?? '').toString();
                      final initialName =
                          (charity['name'] ?? 'Charity').toString();
                      final initialDescription =
                          (charity['description'] ?? '').toString();
                      final initialWebsite =
                          (charity['website_url'] ?? '').toString();
                      final initialSlug = (charity['slug'] ?? '')
                          .toString()
                          .trim()
                          .toLowerCase();
                      final initialIsActive = charity['is_active'] == true;

                      return _panelCard(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            const Icon(Icons.favorite,
                                color: Color(0xFFFF4FA3)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    charity['name']?.toString() ?? 'Charity',
                                    style: const TextStyle(
                                      color: _textPrimary,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    (charity['description'] ?? '')
                                            .toString()
                                            .trim()
                                            .isEmpty
                                        ? 'No description provided'
                                        : (charity['description'] ?? '')
                                            .toString(),
                                    style: const TextStyle(
                                      color: _textMuted,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Link: ${(charity['website_url'] ?? '-').toString()}',
                                    style: const TextStyle(
                                      color: Color(0xFF64B3FF),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '\$${(((charity['total_raised_cents'] ?? 0) as num).toDouble() / 100.0).toStringAsFixed(2)} donated',
                                    style: const TextStyle(
                                      color: Color(0xFF2FD8A3),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                OutlinedButton.icon(
                                  style: _outlinedStyle(),
                                  onPressed: () async {
                                    final rootContext = context;
                                    final nameController =
                                        TextEditingController(
                                            text: initialName);
                                    final slugController =
                                        TextEditingController(
                                            text: initialSlug);
                                    final descriptionController =
                                        TextEditingController(
                                            text: initialDescription);
                                    final websiteController =
                                        TextEditingController(
                                            text: initialWebsite);
                                    bool isActive = initialIsActive;
                                    final formKey = GlobalKey<FormState>();

                                    await showDialog<void>(
                                      context: context,
                                      builder: (context) => StatefulBuilder(
                                        builder: (context, setModalState) =>
                                            AlertDialog(
                                          title: const Text('Edit Charity'),
                                          content: Form(
                                            key: formKey,
                                            child: SingleChildScrollView(
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  TextFormField(
                                                    controller: nameController,
                                                    decoration:
                                                        const InputDecoration(
                                                            labelText:
                                                                'Charity Name'),
                                                    validator: (v) => (v ==
                                                                null ||
                                                            v.trim().length < 2)
                                                        ? 'Enter charity name'
                                                        : null,
                                                  ),
                                                  const SizedBox(height: 8),
                                                  TextFormField(
                                                    controller: slugController,
                                                    decoration:
                                                        const InputDecoration(
                                                            labelText: 'Slug'),
                                                    validator: (v) {
                                                      final value =
                                                          (v ?? '').trim();
                                                      if (value.length < 2) {
                                                        return 'Enter slug';
                                                      }
                                                      if (!RegExp(
                                                              r'^[a-z0-9-]+$')
                                                          .hasMatch(value)) {
                                                        return 'Use lowercase letters, numbers, hyphen';
                                                      }
                                                      return null;
                                                    },
                                                  ),
                                                  const SizedBox(height: 8),
                                                  TextFormField(
                                                    controller:
                                                        descriptionController,
                                                    decoration:
                                                        const InputDecoration(
                                                            labelText:
                                                                'Description'),
                                                  ),
                                                  const SizedBox(height: 8),
                                                  TextFormField(
                                                    controller:
                                                        websiteController,
                                                    decoration:
                                                        const InputDecoration(
                                                            labelText:
                                                                'Website URL'),
                                                  ),
                                                  const SizedBox(height: 8),
                                                  SwitchListTile(
                                                    value: isActive,
                                                    onChanged: (v) =>
                                                        setModalState(
                                                            () => isActive = v),
                                                    contentPadding:
                                                        EdgeInsets.zero,
                                                    title: const Text('Active'),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(context),
                                              child: const Text('Cancel'),
                                            ),
                                            ElevatedButton(
                                              onPressed: () async {
                                                if (!formKey.currentState!
                                                    .validate()) {
                                                  return;
                                                }
                                                try {
                                                  await rootContext
                                                      .read<CharityProvider>()
                                                      .updateCharity(
                                                        charityId: charityId,
                                                        name:
                                                            nameController.text,
                                                        slug:
                                                            slugController.text,
                                                        description:
                                                            descriptionController
                                                                .text,
                                                        website:
                                                            websiteController
                                                                .text,
                                                        isActive: isActive,
                                                      );
                                                  if (!rootContext.mounted) {
                                                    return;
                                                  }
                                                  Navigator.of(rootContext)
                                                      .pop();
                                                  ScaffoldMessenger.of(
                                                          rootContext)
                                                      .showSnackBar(
                                                    const SnackBar(
                                                        content: Text(
                                                            'Charity updated')),
                                                  );
                                                } catch (e) {
                                                  if (!rootContext.mounted) {
                                                    return;
                                                  }
                                                  ScaffoldMessenger.of(
                                                          rootContext)
                                                      .showSnackBar(
                                                    SnackBar(
                                                        content: Text(
                                                            'Update failed: $e')),
                                                  );
                                                }
                                              },
                                              child: const Text('Save'),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.edit_outlined),
                                  label: const Text('Edit'),
                                ),
                                OutlinedButton.icon(
                                  style: _outlinedStyle().copyWith(
                                    foregroundColor: WidgetStateProperty.all(
                                        Colors.redAccent),
                                  ),
                                  onPressed: () async {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: const Text('Delete Charity'),
                                        content: const Text(
                                          'This will archive and hide the charity from active lists.',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context, false),
                                            child: const Text('Cancel'),
                                          ),
                                          ElevatedButton(
                                            onPressed: () =>
                                                Navigator.pop(context, true),
                                            child: const Text('Delete'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirm != true) {
                                      return;
                                    }
                                    if (!context.mounted) {
                                      return;
                                    }
                                    final messenger =
                                        ScaffoldMessenger.of(context);
                                    final charityProvider =
                                        context.read<CharityProvider>();
                                    try {
                                      await charityProvider
                                          .deleteCharity(charityId);
                                      if (!context.mounted) return;
                                      messenger.showSnackBar(
                                        const SnackBar(
                                            content: Text('Charity archived')),
                                      );
                                    } catch (e) {
                                      if (!context.mounted) return;
                                      messenger.showSnackBar(
                                        SnackBar(
                                            content: Text('Delete failed: $e')),
                                      );
                                    }
                                  },
                                  icon: const Icon(Icons.delete_outline),
                                  label: const Text('Delete'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 8),
                    const Text(
                      'Donations Ledger',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: _textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (ledgerSummary.isEmpty)
                      _panelCard(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'No donation data yet',
                              style: TextStyle(
                                color: _textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Charity donation records will appear here.',
                              style: TextStyle(color: _textMuted),
                            ),
                          ],
                        ),
                      )
                    else
                      ...ledgerSummary.map((s) {
                        final total = (((s['total_raised_cents'] ?? 0) as num)
                                .toDouble() /
                            100.0);
                        final ledgerTotal =
                            (((s['ledger_total_cents'] ?? 0) as num)
                                    .toDouble() /
                                100.0);
                        return _panelCard(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                s['charity_name']?.toString() ?? 'Charity',
                                style: const TextStyle(
                                  color: _textPrimary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Total: \$${total.toStringAsFixed(2)} • Ledger: \$${ledgerTotal.toStringAsFixed(2)} • Donations: ${s['donation_count'] ?? 0}',
                                style: const TextStyle(
                                  color: _textMuted,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    const SizedBox(height: 10),
                    const Text(
                      'Recent Transactions',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: _textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (donationEntries.isEmpty)
                      const SizedBox.shrink()
                    else
                      ...donationEntries.take(20).map((d) {
                        final amount =
                            (((d['amount_cents'] ?? 0) as num).toDouble() /
                                100.0);
                        return _panelCard(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${d['charity_name'] ?? 'Charity'} • \$${amount.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  color: _textPrimary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${d['user_email'] ?? 'user'} • ${d['payment_provider'] ?? 'provider'}',
                                style: const TextStyle(
                                  color: _textMuted,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${d['created_at'] ?? ''}',
                                style: const TextStyle(
                                  color: Color(0xFF74829F),
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UsersTab extends StatefulWidget {
  const _UsersTab();

  @override
  State<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<_UsersTab> {
  static const Color _bg = Color(0xFF080B12);
  static const Color _panel = Color(0xFF121722);
  static const Color _panelBorder = Color(0xFF252D3D);
  static const Color _textPrimary = Color(0xFFF3F6FF);
  static const Color _textMuted = Color(0xFF9CA8C2);
  static const Color _accent = Color(0xFFFF4FA3);

  final TextEditingController _searchController = TextEditingController();
  String _roleFilter = '';
  int? _selectedUserId;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  ButtonStyle _outlinedStyle() {
    return OutlinedButton.styleFrom(
      foregroundColor: _textPrimary,
      backgroundColor: _panel,
      side: const BorderSide(color: _panelBorder),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    );
  }

  ButtonStyle _filledStyle() {
    return ElevatedButton.styleFrom(
      foregroundColor: Colors.white,
      backgroundColor: _accent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    );
  }

  Future<void> _refreshUsers() async {
    await context.read<AdminUserManagementProvider>().loadUsers(
          query: _searchController.text.trim(),
          role: _roleFilter.isEmpty ? null : _roleFilter,
        );
  }

  Future<void> _loadDetails(int userId) async {
    setState(() => _selectedUserId = userId);
    await context.read<AdminUserManagementProvider>().loadUserDetails(userId);
  }

  String _formatAdminTimestamp(dynamic value) {
    final raw = (value ?? '').toString().trim();
    if (raw.isEmpty) return 'Not recorded';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    final local = parsed.toLocal();
    String twoDigits(int input) => input.toString().padLeft(2, '0');
    return '${local.year}-${twoDigits(local.month)}-${twoDigits(local.day)} ${twoDigits(local.hour)}:${twoDigits(local.minute)}';
  }

  DateTime? _parseAdminDate(dynamic value) {
    final raw = (value ?? '').toString().trim();
    if (raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toLocal();
  }

  Future<DateTime?> _pickAdminDateTime(
    BuildContext dialogContext, {
    DateTime? initialDateTime,
    String helpText = 'Select date and time',
  }) async {
    final now = DateTime.now();
    final firstDate = DateTime(now.year - 5, 1, 1);
    final lastDate = DateTime(now.year + 5, 12, 31);
    final initial = initialDateTime ?? now;
    final normalizedInitial = initial.isBefore(firstDate)
        ? firstDate
        : initial.isAfter(lastDate)
            ? lastDate
            : initial;

    final pickedDate = await showDatePicker(
      context: dialogContext,
      initialDate: normalizedInitial,
      firstDate: firstDate,
      lastDate: lastDate,
      helpText: helpText,
    );
    if (pickedDate == null || !dialogContext.mounted) return null;

    final pickedTime = await showTimePicker(
      context: dialogContext,
      initialTime: TimeOfDay.fromDateTime(normalizedInitial),
    );
    if (pickedTime == null) return null;

    return DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );
  }

  Future<void> _openEditUserDialog(Map<String, dynamic> user) async {
    final rootContext = context;
    final provider = context.read<AdminUserManagementProvider>();
    final usernameController =
        TextEditingController(text: (user['username'] ?? '').toString());
    final emailController =
        TextEditingController(text: (user['email'] ?? '').toString());
    final statusController =
        TextEditingController(text: (user['status'] ?? 'available').toString());
    final skillController =
        TextEditingController(text: (user['skill_level'] ?? '').toString());
    final clubController = TextEditingController(
        text: (user['club_affiliation'] ?? '').toString());
    String role = (user['role'] ?? 'guest').toString();
    bool profileCompleted = user['profile_setup_completed'] == true;
    final formKey = GlobalKey<FormState>();

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: const Text('Edit User Profile'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: usernameController,
                    decoration: const InputDecoration(labelText: 'Username'),
                    validator: (v) => (v == null || v.trim().length < 2)
                        ? 'Invalid username'
                        : null,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: emailController,
                    decoration: const InputDecoration(labelText: 'Email'),
                    validator: (v) => (v == null || !v.contains('@'))
                        ? 'Invalid email'
                        : null,
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: role,
                    items: const [
                      DropdownMenuItem(value: 'guest', child: Text('guest')),
                      DropdownMenuItem(
                          value: 'subscriber', child: Text('subscriber')),
                      DropdownMenuItem(value: 'admin', child: Text('admin')),
                    ],
                    onChanged: (value) =>
                        setModalState(() => role = value ?? 'guest'),
                    decoration: const InputDecoration(labelText: 'Role'),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: statusController,
                    decoration: const InputDecoration(labelText: 'Status'),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: skillController,
                    decoration: const InputDecoration(
                        labelText: 'Skill (beginner/intermediate/pro/elite)'),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: clubController,
                    decoration: const InputDecoration(labelText: 'Club'),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    value: profileCompleted,
                    onChanged: (value) =>
                        setModalState(() => profileCompleted = value),
                    title: const Text('Profile setup completed'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                try {
                  await provider.updateUser(
                    (user['id'] as num).toInt(),
                    {
                      'username': usernameController.text.trim(),
                      'email': emailController.text.trim(),
                      'role': role,
                      'status': statusController.text.trim(),
                      'profile_setup_completed': profileCompleted,
                      if (skillController.text.trim().isNotEmpty)
                        'skill_level':
                            skillController.text.trim().toLowerCase(),
                      if (clubController.text.trim().isNotEmpty)
                        'club_affiliation': clubController.text.trim(),
                    },
                  );
                  if (!rootContext.mounted) return;
                  Navigator.of(rootContext).pop();
                  ScaffoldMessenger.of(rootContext).showSnackBar(
                    const SnackBar(content: Text('User profile updated')),
                  );
                  if (_selectedUserId == (user['id'] as num).toInt()) {
                    await provider.loadUserDetails(_selectedUserId!);
                  }
                } catch (e) {
                  if (!rootContext.mounted) return;
                  ScaffoldMessenger.of(rootContext).showSnackBar(
                    SnackBar(content: Text('Update failed: $e')),
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openEditScoreDialog(Map<String, dynamic> score) async {
    final rootContext = context;
    final provider = context.read<AdminUserManagementProvider>();
    final scoreController =
        TextEditingController(text: (score['score'] ?? '').toString());
    final courseController =
        TextEditingController(text: (score['course_name'] ?? '').toString());
    final playedOnController =
        TextEditingController(text: (score['played_on'] ?? '').toString());
    bool isVerified = score['is_verified'] == true;
    final formKey = GlobalKey<FormState>();

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: const Text('Edit Golf Score'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: courseController,
                  decoration: const InputDecoration(labelText: 'Course'),
                  validator: (v) => (v == null || v.trim().length < 2)
                      ? 'Invalid course'
                      : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: scoreController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Score'),
                  validator: (v) {
                    final n = int.tryParse((v ?? '').trim());
                    if (n == null || n < 1 || n > 45) return 'Score 1-45';
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: playedOnController,
                  decoration: const InputDecoration(
                      labelText: 'Played On (YYYY-MM-DD)'),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  value: isVerified,
                  onChanged: (value) => setModalState(() => isVerified = value),
                  title: const Text('Verified'),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                try {
                  await provider.updateScore(
                    score['id'].toString(),
                    {
                      'course_name': courseController.text.trim(),
                      'score': int.parse(scoreController.text.trim()),
                      'played_on': playedOnController.text.trim(),
                      'is_verified': isVerified,
                    },
                  );
                  if (!rootContext.mounted) return;
                  Navigator.of(rootContext).pop();
                  ScaffoldMessenger.of(rootContext).showSnackBar(
                    const SnackBar(content: Text('Score updated')),
                  );
                } catch (e) {
                  if (!rootContext.mounted) return;
                  ScaffoldMessenger.of(rootContext).showSnackBar(
                    SnackBar(content: Text('Score update failed: $e')),
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openSubscriptionDialog(
      Map<String, dynamic> subscription) async {
    final rootContext = context;
    final provider = context.read<AdminUserManagementProvider>();
    String status = (subscription['status'] ?? 'inactive').toString();
    String planId = (subscription['plan_id'] ?? 'monthly').toString();
    bool cancelAtPeriodEnd = subscription['cancel_at_period_end'] == true;
    DateTime? renewalDate = _parseAdminDate(subscription['renewal_date']) ??
        _parseAdminDate(subscription['current_period_end']);
    final currentPeriodEnd =
        _parseAdminDate(subscription['current_period_end']);

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: const Text('Manage Subscription'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: planId,
                  items: const [
                    DropdownMenuItem(value: 'monthly', child: Text('monthly')),
                    DropdownMenuItem(value: 'yearly', child: Text('yearly')),
                  ],
                  onChanged: (value) =>
                      setModalState(() => planId = value ?? 'monthly'),
                  decoration: const InputDecoration(labelText: 'Plan'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: status,
                  items: const [
                    DropdownMenuItem(value: 'active', child: Text('active')),
                    DropdownMenuItem(value: 'inactive', child: Text('inactive')),
                    DropdownMenuItem(
                        value: 'cancelled', child: Text('cancelled')),
                    DropdownMenuItem(value: 'lapsed', child: Text('lapsed')),
                  ],
                  onChanged: (value) =>
                      setModalState(() => status = value ?? 'inactive'),
                  decoration: const InputDecoration(labelText: 'Status'),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  value: cancelAtPeriodEnd,
                  onChanged: (value) =>
                      setModalState(() => cancelAtPeriodEnd = value),
                  title: const Text('Cancel at period end'),
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _panel,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _panelBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Renewal / current period end',
                        style: TextStyle(
                          color: _textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatAdminTimestamp(renewalDate),
                        style: const TextStyle(color: _textMuted),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            style: _outlinedStyle(),
                            onPressed: () async {
                              final picked = await _pickAdminDateTime(
                                rootContext,
                                initialDateTime:
                                    renewalDate ?? currentPeriodEnd ?? DateTime.now(),
                                helpText: 'Select Renewal Date',
                              );
                              if (picked == null || !rootContext.mounted) {
                                return;
                              }
                              setModalState(() => renewalDate = picked);
                            },
                            icon: const Icon(Icons.edit_calendar),
                            label: const Text('Pick Renewal'),
                          ),
                          TextButton(
                            onPressed: currentPeriodEnd == null
                                ? null
                                : () => setModalState(
                                    () => renewalDate = currentPeriodEnd,
                                  ),
                            child: const Text('Use period end'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                try {
                  final selectedRenewalDate = renewalDate;
                  final renewalIso = selectedRenewalDate
                      ?.toUtc()
                      .toIso8601String();
                  await provider.updateSubscription(
                    subscription['id'].toString(),
                    {
                      'plan_id': planId,
                      'status': status,
                      'cancel_at_period_end': cancelAtPeriodEnd,
                      if (renewalIso != null) 'renewal_date': renewalIso,
                      if (renewalIso != null)
                        'current_period_end': renewalIso,
                    },
                  );
                  if (!rootContext.mounted) return;
                  Navigator.of(rootContext).pop();
                  ScaffoldMessenger.of(rootContext).showSnackBar(
                    const SnackBar(content: Text('Subscription updated')),
                  );
                } catch (e) {
                  if (!rootContext.mounted) return;
                  ScaffoldMessenger.of(rootContext).showSnackBar(
                    SnackBar(content: Text('Subscription update failed: $e')),
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _panelCard({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(14),
    EdgeInsetsGeometry margin = EdgeInsets.zero,
  }) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _panelBorder),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AdminUserManagementProvider>();

    return ColoredBox(
      color: _bg,
      child: Column(
        children: [
          _adminContentFrame(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'User Management',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: _textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 250,
                      child: TextField(
                        controller: _searchController,
                        style: const TextStyle(color: _textPrimary),
                        decoration: const InputDecoration(
                          labelText: 'Search user/email/club',
                          prefixIcon: Icon(Icons.search),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 160,
                      child: DropdownButtonFormField<String>(
                        initialValue: _roleFilter.isEmpty ? null : _roleFilter,
                        items: const [
                          DropdownMenuItem(
                              value: 'guest', child: Text('guest')),
                          DropdownMenuItem(
                              value: 'subscriber', child: Text('subscriber')),
                          DropdownMenuItem(
                              value: 'admin', child: Text('admin')),
                        ],
                        onChanged: (value) =>
                            setState(() => _roleFilter = value ?? ''),
                        decoration:
                            const InputDecoration(labelText: 'Role filter'),
                      ),
                    ),
                    OutlinedButton.icon(
                      style: _outlinedStyle(),
                      onPressed: _refreshUsers,
                      icon: const Icon(Icons.filter_alt),
                      label: const Text('Apply'),
                    ),
                    OutlinedButton.icon(
                      style: _outlinedStyle(),
                      onPressed: () async {
                        _searchController.clear();
                        setState(() => _roleFilter = '');
                        await _refreshUsers();
                      },
                      icon: const Icon(Icons.restart_alt),
                      label: const Text('Reset'),
                    ),
                    ElevatedButton.icon(
                      style: _filledStyle(),
                      onPressed: _refreshUsers,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Refresh'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.zero,
              child: _adminContentFrame(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (provider.error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          provider.error!,
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                      ),
                    if (provider.isLoading && provider.users.isEmpty)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: CircularProgressIndicator(color: _accent),
                        ),
                      )
                    else if (provider.users.isEmpty)
                      _panelCard(
                        child: const Text(
                          'No users found.',
                          style: TextStyle(color: _textMuted),
                        ),
                      )
                    else
                      ...provider.users.map((user) {
                        final userId = (user['id'] as num?)?.toInt() ?? 0;
                        final latestSub = user['latest_subscription']
                            as Map<String, dynamic>?;
                        final selected = _selectedUserId == userId;
                        return _panelCard(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${user['username']} • ${user['email']}',
                                          style: const TextStyle(
                                            color: _textPrimary,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Role: ${user['role']} • Scores: ${user['score_count'] ?? 0} • Status: ${user['status'] ?? '-'}',
                                          style: const TextStyle(
                                            color: _textMuted,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        if (latestSub != null)
                                          Text(
                                            'Subscription: ${latestSub['status']} • ${latestSub['plan_id']}',
                                            style: const TextStyle(
                                              color: Color(0xFF2FD8A3),
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Wrap(
                                    spacing: 8,
                                    children: [
                                      OutlinedButton(
                                        style: _outlinedStyle(),
                                        onPressed: () =>
                                            _openEditUserDialog(user),
                                        child: const Text('Edit Profile'),
                                      ),
                                      ElevatedButton(
                                        style: _filledStyle(),
                                        onPressed: () => _loadDetails(userId),
                                        child: Text(
                                            selected ? 'Loaded' : 'Manage'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              if (selected) ...[
                                const SizedBox(height: 12),
                                const Divider(color: _panelBorder),
                                const SizedBox(height: 8),
                                const Text(
                                  'Golf Scores',
                                  style: TextStyle(
                                    color: _textPrimary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                if (provider.selectedUserScores.isEmpty)
                                  const Text(
                                    'No scores found',
                                    style: TextStyle(color: _textMuted),
                                  )
                                else
                                  ...provider.selectedUserScores
                                      .take(8)
                                      .map((score) => Padding(
                                            padding: const EdgeInsets.only(
                                                bottom: 6),
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    '${score['played_on']} • ${score['course_name']} • ${score['score']}',
                                                    style: const TextStyle(
                                                      color: _textMuted,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                                OutlinedButton(
                                                  style: _outlinedStyle(),
                                                  onPressed: () =>
                                                      _openEditScoreDialog(
                                                          score),
                                                  child: const Text('Edit'),
                                                ),
                                              ],
                                            ),
                                          )),
                                const SizedBox(height: 8),
                                const Text(
                                  'Subscriptions',
                                  style: TextStyle(
                                    color: _textPrimary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                if (provider.selectedUserSubscriptions.isEmpty)
                                  const Text(
                                    'No subscriptions found',
                                    style: TextStyle(color: _textMuted),
                                  )
                                else
                                  ...provider.selectedUserSubscriptions
                                      .take(5)
                                      .map((sub) => Padding(
                                            padding: const EdgeInsets.only(
                                                bottom: 6),
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    '${sub['status']} • ${sub['plan_id']} • ends ${sub['current_period_end']}',
                                                    style: const TextStyle(
                                                      color: _textMuted,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                                ElevatedButton(
                                                  style: _filledStyle(),
                                                  onPressed: () =>
                                                      _openSubscriptionDialog(
                                                          sub),
                                                  child: const Text('Manage'),
                                                ),
                                              ],
                                            ),
                                          )),
                              ],
                            ],
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnalyticsTab extends StatefulWidget {
  const _AnalyticsTab();

  @override
  State<_AnalyticsTab> createState() => _AnalyticsTabState();
}

class _AnalyticsTabState extends State<_AnalyticsTab> {
  bool _didLoad = false;
  static const Color _bg = Color(0xFF080B12);
  static const Color _panel = Color(0xFF121722);
  static const Color _panelBorder = Color(0xFF252D3D);
  static const Color _textPrimary = Color(0xFFF3F6FF);
  static const Color _textMuted = Color(0xFF9CA8C2);
  static const Color _accent = Color(0xFFFF4FA3);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didLoad) return;
    _didLoad = true;
    context.read<AdminAnalyticsProvider>().loadAnalytics(days: 30);
  }

  double _toUsd(num cents) => cents.toDouble() / 100.0;
  String _usd(num cents) => '\$${_toUsd(cents).toStringAsFixed(2)}';
  String _usdRaw(num amount) => '\$${amount.toStringAsFixed(2)}';

  Color _semanticColor(String key) {
    final v = key.toLowerCase();
    if (v.contains('high') ||
        v.contains('failed') ||
        v.contains('rejected') ||
        v.contains('fraud')) {
      return const Color(0xFFDC2626);
    }
    if (v.contains('pending') || v.contains('open') || v.contains('medium')) {
      return const Color(0xFFD97706);
    }
    if (v.contains('active') ||
        v.contains('completed') ||
        v.contains('paid') ||
        v.contains('accepted') ||
        v.contains('subscriber')) {
      return const Color(0xFF15803D);
    }
    if (v.contains('admin')) {
      return const Color(0xFF2563EB);
    }
    if (v.contains('guest') ||
        v.contains('declined') ||
        v.contains('cancelled') ||
        v.contains('expired') ||
        v.contains('revoked')) {
      return const Color(0xFF64748B);
    }
    return const Color(0xFF1D4ED8);
  }

  Widget _sectionHeader(
    String title, {
    VoidCallback? onRefresh,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              color: _textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
          const Spacer(),
          if (onRefresh != null)
            InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: onRefresh,
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _panel,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: _panelBorder),
                ),
                child: const Icon(Icons.refresh, color: _textPrimary, size: 20),
              ),
            ),
        ],
      ),
    );
  }

  Widget _metricGrid(List<_AnalyticsMetricCardData> cards) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns =
            width >= 1080 ? 4 : (width >= 760 ? 3 : (width >= 480 ? 2 : 1));
        final ratio = columns >= 4
            ? 2.35
            : (columns == 3
                ? 2.05
                : (columns == 2 ? 1.75 : (width >= 360 ? 1.95 : 1.65)));
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: cards.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: ratio,
          ),
          itemBuilder: (context, index) {
            final card = cards[index];
            return Container(
              decoration: BoxDecoration(
                color: _panel,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: _panelBorder),
              ),
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (card.icon != null)
                        Icon(
                          card.icon,
                          size: 16,
                          color: card.dotColor,
                        ),
                      if (card.icon != null) const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          card.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _textMuted,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    card.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _textPrimary,
                      fontSize: 28,
                      height: 1.0,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: card.dotColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          card.caption,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: card.dotColor,
                            fontWeight: FontWeight.w600,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _distributionBlock(String title, Map<String, dynamic> map) {
    final rows = map.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    return Container(
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _panelBorder),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: _textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 10),
          if (rows.isEmpty)
            const Text('No data', style: TextStyle(color: _textMuted))
          else
            ...rows.map((e) {
              final color = _semanticColor(e.key);
              return Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        e.key,
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      '${e.value}',
                      style: const TextStyle(
                        color: _textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _distributionGrid(List<Widget> cards) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 1080 ? 3 : (width >= 680 ? 2 : 1);
        if (columns == 1) {
          return Column(
            children: cards
                .map((w) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: w,
                    ))
                .toList(),
          );
        }
        final cardWidth = (width - ((columns - 1) * 10)) / columns;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: cards
              .map(
                (w) => SizedBox(
                  width: cardWidth,
                  child: w,
                ),
              )
              .toList(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AdminAnalyticsProvider>();
    final data = provider.analytics;

    if (provider.isLoading && data == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.error != null && data == null) {
      return Container(
        color: _bg,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                provider.error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.redAccent),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => context
                    .read<AdminAnalyticsProvider>()
                    .loadAnalytics(days: 30),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (data == null) {
      return const ColoredBox(
        color: _bg,
        child: Center(
          child: Text(
            'No analytics data yet',
            style: TextStyle(color: _textMuted),
          ),
        ),
      );
    }

    final kpis = Map<String, dynamic>.from(data['kpis'] ?? const {});
    final financial = Map<String, dynamic>.from(kpis['financial'] ?? const {});
    final draws = Map<String, dynamic>.from(kpis['draws'] ?? const {});
    final breakdowns =
        Map<String, dynamic>.from(data['breakdowns'] ?? const {});
    final window = Map<String, dynamic>.from(data['window'] ?? const {});
    final days = (window['days'] as num?)?.toInt() ?? 30;

    final revenueCards = [
      _AnalyticsMetricCardData(
        title: 'Subscription Revenue',
        value: _usd((financial['subscription_revenue_cents'] as num?) ?? 0),
        caption: 'plan checkout',
        dotColor: const Color(0xFFFF4FA3),
        icon: Icons.payments_outlined,
      ),
      _AnalyticsMetricCardData(
        title: 'Charity Donations',
        value: _usd((financial['charity_donations_cents'] as num?) ?? 0),
        caption: 'subscriber charity',
        dotColor: const Color(0xFF40D9A7),
        icon: Icons.favorite_border,
      ),
      _AnalyticsMetricCardData(
        title: 'Event Donations',
        value: _usd((financial['event_donations_cents'] as num?) ?? 0),
        caption: 'event unlocks',
        dotColor: const Color(0xFF6DB8FF),
        icon: Icons.event_available_outlined,
      ),
      _AnalyticsMetricCardData(
        title: 'Wallet Top-Ups',
        value: _usdRaw((financial['wallet_topups_usd'] as num?) ?? 0),
        caption: 'wallet funding',
        dotColor: const Color(0xFFFFB454),
        icon: Icons.account_balance_wallet_outlined,
      ),
    ];

    final drawCards = [
      _AnalyticsMetricCardData(
        title: 'Total Draws',
        value: '${draws['total_draws'] ?? 0}',
        caption: 'all periods',
        dotColor: const Color(0xFF64B3FF),
        icon: Icons.casino_outlined,
      ),
      _AnalyticsMetricCardData(
        title: 'Completed Draws',
        value: '${draws['completed_draws'] ?? 0}',
        caption: 'closed cycles',
        dotColor: const Color(0xFF2FD8A3),
        icon: Icons.verified_outlined,
      ),
      _AnalyticsMetricCardData(
        title: 'Pending Claims',
        value: '${draws['pending_claims'] ?? 0}',
        caption: 'winner verification',
        dotColor: const Color(0xFFFFA94A),
        icon: Icons.pending_actions_outlined,
      ),
      _AnalyticsMetricCardData(
        title: 'Paid Claims',
        value: '${draws['paid_claims'] ?? 0}',
        caption: 'payout completed',
        dotColor: const Color(0xFFFF67A2),
        icon: Icons.attach_money_outlined,
      ),
    ];

    return ColoredBox(
      color: _bg,
      child: RefreshIndicator(
        color: _accent,
        backgroundColor: _panel,
        onRefresh: () =>
            context.read<AdminAnalyticsProvider>().loadAnalytics(days: days),
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            _adminContentFrame(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionHeader(
                    'Analytics',
                    onRefresh: () {
                      context
                          .read<AdminAnalyticsProvider>()
                          .loadAnalytics(days: days);
                    },
                  ),
                  Text(
                    'Window: $days days',
                    style: const TextStyle(
                      color: _textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (provider.isLoading) ...[
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: const LinearProgressIndicator(
                        minHeight: 3,
                        color: _accent,
                        backgroundColor: _panelBorder,
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  _sectionHeader('Revenue (USD)'),
                  _metricGrid(revenueCards),
                  const SizedBox(height: 18),
                  _sectionHeader('Draw Engine'),
                  _metricGrid(drawCards),
                  const SizedBox(height: 18),
                  _sectionHeader('Distribution'),
                  _distributionGrid([
                    _distributionBlock(
                      'Event Status',
                      Map<String, dynamic>.from(
                        breakdowns['event_status'] ?? const {},
                      ),
                    ),
                    _distributionBlock(
                      'Score Status',
                      Map<String, dynamic>.from(
                        breakdowns['score_status'] ?? const {},
                      ),
                    ),
                    _distributionBlock(
                      'Unlock Status',
                      Map<String, dynamic>.from(
                        breakdowns['unlock_status'] ?? const {},
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrendsTab extends StatefulWidget {
  const _TrendsTab();

  @override
  State<_TrendsTab> createState() => _TrendsTabState();
}

class _TrendsTabState extends State<_TrendsTab> {
  bool _didLoad = false;

  static const Color _bg = Color(0xFF080B12);
  static const Color _panel = Color(0xFF121722);
  static const Color _panelBorder = Color(0xFF252D3D);
  static const Color _textPrimary = Color(0xFFF3F6FF);
  static const Color _textMuted = Color(0xFF9CA8C2);
  static const Color _accent = Color(0xFFFF4FA3);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didLoad) return;
    _didLoad = true;
    final provider = context.read<AdminAnalyticsProvider>();
    if (provider.analytics == null && !provider.isLoading) {
      provider.loadAnalytics(days: 30);
    }
  }

  List<Map<String, dynamic>> _series(dynamic raw) {
    if (raw is! List) return const [];
    final out = <Map<String, dynamic>>[];
    for (final row in raw) {
      if (row is Map) {
        out.add(Map<String, dynamic>.from(row));
      }
    }
    return out;
  }

  List<double> _seriesValues(List<Map<String, dynamic>> series) {
    final values = <double>[];
    for (final row in series) {
      final raw = row['value'];
      if (raw is num) {
        values.add(raw.toDouble());
        continue;
      }
      values.add(double.tryParse('$raw') ?? 0.0);
    }
    return values;
  }

  List<double> _downsample(List<double> values, {int maxPoints = 40}) {
    if (values.length <= maxPoints) return values;
    final output = <double>[];
    final step = (values.length - 1) / (maxPoints - 1);
    for (var i = 0; i < maxPoints; i++) {
      final idx = (i * step).round().clamp(0, values.length - 1);
      output.add(values[idx]);
    }
    return output;
  }

  double _sumValues(List<double> values) {
    var sum = 0.0;
    for (final value in values) {
      sum += value;
    }
    return sum;
  }

  String _formatValue(double value, {required bool cents}) {
    if (cents) {
      return '\$${(value / 100.0).toStringAsFixed(2)}';
    }
    return value.round().toString();
  }

  Widget _statChip({
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _panelBorder),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 12.5, color: _textMuted),
          children: [
            TextSpan(text: '$label: '),
            TextSpan(
              text: value,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(
    String title, {
    VoidCallback? onRefresh,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              color: _textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
          const Spacer(),
          if (onRefresh != null)
            InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: onRefresh,
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _panel,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: _panelBorder),
                ),
                child: const Icon(Icons.refresh, color: _textPrimary, size: 20),
              ),
            ),
        ],
      ),
    );
  }

  Widget _trendChartCard({
    required String title,
    required List<Map<String, dynamic>> series,
    required bool cents,
    required Color color,
  }) {
    final values = _seriesValues(series);
    final chartValues = _downsample(values);
    final total = _sumValues(values);
    final latest = values.isNotEmpty ? values.last : 0.0;
    final average = values.isNotEmpty ? total / values.length : 0.0;

    return Container(
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _panelBorder),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: _textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${values.length} points',
                style: const TextStyle(
                  color: _textMuted,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (values.isEmpty)
            const SizedBox(
              height: 140,
              child: Center(
                child: Text(
                  'No trend points yet',
                  style: TextStyle(color: _textMuted),
                ),
              ),
            )
          else
            SizedBox(
              height: 160,
              width: double.infinity,
              child: CustomPaint(
                painter: _LineBarChartPainter(
                  values: chartValues,
                  color: color,
                  gridColor: _panelBorder,
                ),
              ),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _statChip(
                label: 'Latest',
                value: _formatValue(latest, cents: cents),
                color: color,
              ),
              _statChip(
                label: 'Daily Avg',
                value: _formatValue(average, cents: cents),
                color: const Color(0xFF6DB8FF),
              ),
              _statChip(
                label: 'Total',
                value: _formatValue(total, cents: cents),
                color: const Color(0xFF40D9A7),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AdminAnalyticsProvider>();
    final data = provider.analytics;

    if (provider.isLoading && data == null) {
      return const ColoredBox(
        color: _bg,
        child: Center(child: CircularProgressIndicator(color: _accent)),
      );
    }

    if (provider.error != null && data == null) {
      return ColoredBox(
        color: _bg,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                provider.error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.redAccent),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => context
                    .read<AdminAnalyticsProvider>()
                    .loadAnalytics(days: 30),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (data == null) {
      return const ColoredBox(
        color: _bg,
        child: Center(
          child: Text(
            'No trends data yet',
            style: TextStyle(color: _textMuted),
          ),
        ),
      );
    }

    final trends = Map<String, dynamic>.from(data['trends'] ?? const {});
    final window = Map<String, dynamic>.from(data['window'] ?? const {});
    final days = (window['days'] as num?)?.toInt() ?? 30;

    final subscriptionSeries =
        _series(trends['subscription_revenue_cents_daily']);
    final charitySeries = _series(trends['charity_donations_cents_daily']);
    final eventSeries = _series(trends['event_donations_cents_daily']);
    final drawsSeries = _series(trends['draws_completed_daily']);

    return ColoredBox(
      color: _bg,
      child: RefreshIndicator(
        color: _accent,
        backgroundColor: _panel,
        onRefresh: () =>
            context.read<AdminAnalyticsProvider>().loadAnalytics(days: days),
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            _adminContentFrame(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionHeader(
                    'Trends',
                    onRefresh: () {
                      context
                          .read<AdminAnalyticsProvider>()
                          .loadAnalytics(days: days);
                    },
                  ),
                  Text(
                    'Daily line-bar trends for the selected analytics window',
                    style: const TextStyle(
                      color: _textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (provider.isLoading) ...[
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: const LinearProgressIndicator(
                        minHeight: 3,
                        color: _accent,
                        backgroundColor: _panelBorder,
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  _trendChartCard(
                    title: 'Subscription Revenue',
                    series: subscriptionSeries,
                    cents: true,
                    color: const Color(0xFFFF4FA3),
                  ),
                  const SizedBox(height: 14),
                  _trendChartCard(
                    title: 'Charity Donations',
                    series: charitySeries,
                    cents: true,
                    color: const Color(0xFF40D9A7),
                  ),
                  const SizedBox(height: 14),
                  _trendChartCard(
                    title: 'Event Donations',
                    series: eventSeries,
                    cents: true,
                    color: const Color(0xFF6DB8FF),
                  ),
                  const SizedBox(height: 14),
                  _trendChartCard(
                    title: 'Draws Completed',
                    series: drawsSeries,
                    cents: false,
                    color: const Color(0xFFFFB454),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LineBarChartPainter extends CustomPainter {
  const _LineBarChartPainter({
    required this.values,
    required this.color,
    required this.gridColor,
  });

  final List<double> values;
  final Color color;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    if (rect.width <= 0 || rect.height <= 0) return;

    final gridPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.7)
      ..strokeWidth = 1;

    for (var i = 0; i <= 4; i++) {
      final y = rect.top + (rect.height * i / 4.0);
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), gridPaint);
    }

    if (values.isEmpty) {
      return;
    }

    final maxValue = values.reduce(math.max);
    if (maxValue <= 0) {
      return;
    }

    final count = values.length;
    final stepX = count == 1 ? 0.0 : rect.width / (count - 1);
    final barWidth =
        math.max(2.0, math.min(10.0, (stepX == 0.0 ? 10.0 : stepX * 0.46)));

    double xFor(int index) {
      if (count == 1) return rect.left + (rect.width / 2.0);
      return rect.left + (index * stepX);
    }

    final barPaint = Paint()..color = color.withValues(alpha: 0.24);
    for (var i = 0; i < count; i++) {
      final ratio = (values[i] / maxValue).clamp(0.0, 1.0);
      final x = xFor(i);
      final barTop = rect.bottom - (rect.height * ratio);
      final bar = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          x - (barWidth / 2.0),
          barTop,
          barWidth,
          rect.bottom - barTop,
        ),
        const Radius.circular(3),
      );
      canvas.drawRRect(bar, barPaint);
    }

    final areaPath = Path();
    final linePath = Path();
    for (var i = 0; i < count; i++) {
      final ratio = (values[i] / maxValue).clamp(0.0, 1.0);
      final x = xFor(i);
      final y = rect.bottom - (rect.height * ratio);
      if (i == 0) {
        areaPath.moveTo(x, rect.bottom);
        areaPath.lineTo(x, y);
        linePath.moveTo(x, y);
      } else {
        areaPath.lineTo(x, y);
        linePath.lineTo(x, y);
      }
    }
    areaPath.lineTo(xFor(count - 1), rect.bottom);
    areaPath.close();

    final areaPaint = Paint()..color = color.withValues(alpha: 0.10);
    canvas.drawPath(areaPath, areaPaint);

    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(linePath, linePaint);

    final pointPaint = Paint()..color = color;
    final step = math.max(1, (count / 12).floor());
    for (var i = 0; i < count; i += step) {
      final ratio = (values[i] / maxValue).clamp(0.0, 1.0);
      final x = xFor(i);
      final y = rect.bottom - (rect.height * ratio);
      canvas.drawCircle(Offset(x, y), 2.4, pointPaint);
    }
    if ((count - 1) % step != 0) {
      final ratio = (values.last / maxValue).clamp(0.0, 1.0);
      canvas.drawCircle(
        Offset(xFor(count - 1), rect.bottom - (rect.height * ratio)),
        2.4,
        pointPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LineBarChartPainter oldDelegate) {
    if (oldDelegate.color != color || oldDelegate.gridColor != gridColor) {
      return true;
    }
    if (oldDelegate.values.length != values.length) {
      return true;
    }
    for (var i = 0; i < values.length; i++) {
      if (oldDelegate.values[i] != values[i]) return true;
    }
    return false;
  }
}

class _AnalyticsMetricCardData {
  const _AnalyticsMetricCardData({
    required this.title,
    required this.value,
    required this.caption,
    required this.dotColor,
    this.icon,
  });

  final String title;
  final String value;
  final String caption;
  final Color dotColor;
  final IconData? icon;
}
