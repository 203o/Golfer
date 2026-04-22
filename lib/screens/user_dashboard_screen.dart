import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../services/auth_service.dart';
import '../services/charity_provider.dart';
import '../services/draw_provider.dart';
import '../services/subscription_provider.dart';
import '../services/tournament_provider.dart';
import '../widgets/app_skeleton.dart';
import '../widgets/top_navigation_bar.dart';
import 'landing_screen.dart';
import 'tournament_inbox_screen.dart';
import 'tournament_player_screen.dart';

enum DashboardView { dashboard, draw }

class UserDashboardScreen extends StatefulWidget {
  const UserDashboardScreen({
    super.key,
    this.initialView = DashboardView.dashboard,
  });

  final DashboardView initialView;

  @override
  State<UserDashboardScreen> createState() => _UserDashboardScreenState();
}

class _UserDashboardScreenState extends State<UserDashboardScreen> {
  static const double _maxContentWidth = 1120;
  bool _didLoad = false;
  bool _summaryValuesLoading = true;
  int _selectedModuleIndex = 0;
  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _wallet;
  Map<String, dynamic>? _referral;
  bool _walletBusy = false;
  Timer? _liveRefreshTimer;
  final TextEditingController _walletAmountController =
      TextEditingController(text: '10.00');

  static const List<_DashboardModuleData> _modules = [
    _DashboardModuleData(
      label: 'Proof Upload',
      title: 'Winner Verification',
      subtitle:
          'Upload screenshot proof from the golf platform for winning entries only.',
      icon: Icons.upload_file_outlined,
    ),
    _DashboardModuleData(
      label: '5 Match',
      title: 'Hit all 5 numbers. Win the monthly jackpot.',
      subtitle: 'If nobody hits 5, the jackpot rolls into next month.',
      icon: Icons.leaderboard_outlined,
    ),
    _DashboardModuleData(
      label: '3 & 4 Match',
      title: '3 and 4 number matches earn monthly rewards.',
      subtitle:
          'Track the latest published winners across the supporting tiers.',
      icon: Icons.flash_on_outlined,
    ),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didLoad) return;
    _didLoad = true;
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() => _summaryValuesLoading = true);
    }
    final authService = context.read<AuthService>();
    final tournamentProvider = context.read<TournamentProvider>();
    await Future.wait([
      context.read<DrawProvider>().loadDraws(),
      context.read<CharityProvider>().loadCharities(),
      context.read<SubscriptionProvider>().loadSubscriptions(),
      tournamentProvider.loadDashboardBootstrap(),
      tournamentProvider.loadInbox().catchError((_) {}),
    ]);
    try {
      final profile = await authService.fetchMyProfile();
      final wallet = await authService.fetchMyWallet();
      Map<String, dynamic>? referral;
      try {
        referral = await authService.fetchMyReferral();
      } catch (_) {
        referral = null;
      }
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _wallet = wallet;
        _referral = referral;
      });
    } catch (_) {}
    _liveRefreshTimer?.cancel();
    _liveRefreshTimer = Timer.periodic(const Duration(seconds: 8), (_) async {
      if (!mounted || _selectedModuleIndex != 2) return;
      try {
        await context
            .read<TournamentProvider>()
            .loadDashboardBootstrap(silent: true);
      } catch (_) {}
    });
    if (mounted) {
      setState(() => _summaryValuesLoading = false);
    }
  }

  @override
  void dispose() {
    _liveRefreshTimer?.cancel();
    _walletAmountController.dispose();
    super.dispose();
  }

  Future<void> _openWalletTopupDialog(double amount) async {
    final emailController = TextEditingController();
    final cardController = TextEditingController();
    final expController = TextEditingController();
    final cvcController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setModalState) => AlertDialog(
          title: const Text('Top Up Wallet'),
          content: Form(
            key: formKey,
            child: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    initialValue: amount.toStringAsFixed(2),
                    readOnly: true,
                    decoration:
                        const InputDecoration(labelText: 'Amount (USD)'),
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
                  TextFormField(
                    controller: cardController,
                    decoration: const InputDecoration(labelText: 'Card Number'),
                    validator: (v) =>
                        (v == null || v.replaceAll(' ', '').length < 12)
                            ? 'Invalid card number'
                            : null,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: expController,
                          decoration: const InputDecoration(labelText: 'MM/YY'),
                          validator: (v) =>
                              (v == null || v.length < 4) ? 'Invalid' : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          controller: cvcController,
                          decoration: const InputDecoration(labelText: 'CVC'),
                          validator: (v) =>
                              (v == null || v.length < 3) ? 'Invalid' : null,
                        ),
                      ),
                    ],
                  ),
                  if (_walletBusy) ...[
                    const SizedBox(height: 12),
                    const CircularProgressIndicator(strokeWidth: 2),
                  ]
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed:
                  _walletBusy ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: _walletBusy
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      if (cardController.text
                          .replaceAll(' ', '')
                          .endsWith('0002')) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Card declined (mock).')),
                        );
                        return;
                      }
                      setModalState(() => _walletBusy = true);
                      try {
                        if (!mounted) return;
                        await context.read<AuthService>().topUpWallet(
                              amount: amount,
                              paymentProvider: 'stripe_mock',
                            );
                        if (!mounted) return;
                        await _load();
                        if (!dialogContext.mounted) return;
                        Navigator.pop(dialogContext);
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Wallet topped up successfully.')),
                        );
                      } catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Top-up failed: $e')),
                        );
                        setModalState(() => _walletBusy = false);
                      }
                    },
              child: const Text('Top Up'),
            ),
          ],
        ),
      ),
    );
  }

  Future<Map<String, dynamic>?> _ensureReferralLoaded() async {
    final currentLink = (_referral?['referral_link'] ?? '').toString().trim();
    final currentCode = (_referral?['referral_code'] ?? '').toString().trim();
    if (currentLink.isNotEmpty || currentCode.isNotEmpty) return _referral;
    try {
      final payload = await context.read<AuthService>().fetchMyReferral();
      if (!mounted) return payload;
      setState(() => _referral = payload);
      return payload;
    } catch (_) {
      return _referral;
    }
  }

  String _buildFallbackReferralLink(String referralCode) {
    final base = Uri.base;
    final hasOrigin = base.origin.trim().isNotEmpty;
    final origin = hasOrigin
        ? base.origin.trim()
        : '${base.scheme}://${base.host}${base.hasPort ? ':${base.port}' : ''}';
    return '$origin/?ref=$referralCode';
  }

  Future<void> _copyReferralLink() async {
    final latest = await _ensureReferralLoaded();
    final referralCode = (latest?['referral_code'] ?? '').toString().trim();
    var referralLink = (latest?['referral_link'] ?? '').toString().trim();
    if (referralLink.isEmpty && referralCode.isNotEmpty) {
      referralLink = _buildFallbackReferralLink(referralCode);
    }
    if (referralLink.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Referral code is not ready yet. Refresh once and retry.'),
        ),
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: referralLink));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Referral link copied.')),
    );
  }

  Future<void> _openExternalUrl(String? url) async {
    final value = (url ?? '').trim();
    if (value.isEmpty) return;
    final ok =
        await launchUrlString(value, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open proof link')),
      );
    }
  }

  String _usdFromCents(dynamic rawCents) {
    final cents = (rawCents as num?)?.toInt() ?? 0;
    return '\$${(cents / 100.0).toStringAsFixed(2)}';
  }

  String _claimReviewLabel(String rawStatus) {
    switch (rawStatus.trim().toLowerCase()) {
      case 'approved':
        return 'Approved';
      case 'rejected':
        return 'Rejected';
      case 'pending':
        return 'Pending Review';
      default:
        return 'Proof Required';
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

  Future<void> _openWinnerProofDialog(Map<String, dynamic> result) async {
    final entryId = (result['entry_id'] ?? '').toString();
    if (entryId.isEmpty) return;
    final claim =
        (result['claim'] as Map?)?.cast<String, dynamic>() ?? const {};
    final controller = TextEditingController(
      text: (claim['proof_url'] ?? '').toString(),
    );

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Proof Upload'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${result['draw_key'] ?? '-'} • ${result['match_label'] ?? 'Winner'}',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Paste the screenshot URL from the golf platform. Eligibility verification applies to winners only.',
                style: TextStyle(
                  color: Color(0xFF607289),
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Screenshot URL',
                  hintText: 'https://...',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final proofUrl = controller.text.trim();
              final uri = Uri.tryParse(proofUrl);
              if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Enter a valid screenshot URL'),
                  ),
                );
                return;
              }
              final drawProvider = context.read<DrawProvider>();
              final messenger = ScaffoldMessenger.of(context);
              try {
                final response = await drawProvider.submitWinnerClaim(
                  entryId: entryId,
                  proofUrl: proofUrl,
                );
                if (!dialogContext.mounted) return;
                Navigator.pop(dialogContext);
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      response['resubmitted'] == true
                          ? 'Proof re-submitted for admin review'
                          : 'Proof submitted for admin review',
                    ),
                  ),
                );
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(content: Text('Proof submission failed: $e')),
                );
              }
            },
            child: const Text('Submit Proof'),
          ),
        ],
      ),
    );
  }

  void _onNavTap(TopNavItem item) {
    Widget screen;
    switch (item) {
      case TopNavItem.jackpot:
        screen = const LandingScreen();
      case TopNavItem.draw:
        screen =
            const UserDashboardScreen(initialView: DashboardView.dashboard);
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

  @override
  Widget build(BuildContext context) {
    final draw = context.watch<DrawProvider>();
    final charity = context.watch<CharityProvider>();
    final sub = context.watch<SubscriptionProvider>();
    final tournamentProvider = context.watch<TournamentProvider>();
    final profileWalletLoading = _summaryValuesLoading;
    final quickSnapshotLoading = _summaryValuesLoading ||
        draw.isLoading ||
        charity.isLoading ||
        sub.isLoading;
    final latestResult = draw.myDrawResults.isNotEmpty
        ? draw.myDrawResults.first
        : (draw.latestWeekly ?? draw.latestMonthly);
    final latestResultPosition = latestResult == null
        ? 'No result yet'
        : ((latestResult['status'] == 'completed')
            ? (latestResult['match_label'] ?? 'Published').toString()
            : 'Awaiting publish');

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            TopNavigationBar(
              activeItem: TopNavItem.dashboard,
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
                  padding: EdgeInsets.zero,
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final horizontalPadding =
                            constraints.maxWidth < 640 ? 12.0 : 16.0;
                        return Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxWidth: _maxContentWidth,
                            ),
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
                                  const SizedBox(height: 2),
                                  _moduleNavBar(),
                                  const SizedBox(height: 10),
                                  _selectedModuleIndex == 0
                                      ? _referralBannerCard()
                                      : _DashboardModuleCard(
                                          title: _modules[_selectedModuleIndex]
                                              .title,
                                          subtitle:
                                              _modules[_selectedModuleIndex]
                                                  .subtitle,
                                          icon: _modules[_selectedModuleIndex]
                                              .icon,
                                        ),
                                  const SizedBox(height: 10),
                                  _buildModuleContent(tournamentProvider, draw),
                                  const SizedBox(height: 18),
                                  _buildContextCards(
                                    tournamentProvider: tournamentProvider,
                                    draw: draw,
                                    charity: charity,
                                    sub: sub,
                                    profileWalletLoading: profileWalletLoading,
                                    quickSnapshotLoading: quickSnapshotLoading,
                                    latestResultPosition: latestResultPosition,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
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

  Widget _referralBannerCard() {
    final bonusAmount =
        ((_referral?['bonus_amount_usd'] ?? 20) as num).toDouble();
    final referralCode = (_referral?['referral_code'] ?? '').toString().trim();
    return Card(
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: Color(0xFFEAF4FB),
          child: Icon(Icons.share_outlined, color: Color(0xFF1B5D86)),
        ),
        title: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4,
          runSpacing: 2,
          children: [
            const Text(
              'Refer a friend and get a',
              style: TextStyle(
                color: Color(0xFF0F172A),
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              '\$${bonusAmount.toStringAsFixed(0)}',
              style: const TextStyle(
                color: Color(0xFFD4AF37),
                fontWeight: FontWeight.w800,
              ),
            ),
            const Text(
              'bonus',
              style: TextStyle(
                color: Color(0xFF0F172A),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        subtitle: Text(
          referralCode.isEmpty
              ? 'Copy your referral link to invite new players.'
              : 'Referral code: $referralCode',
          style: const TextStyle(color: Color(0xFF607289)),
        ),
        trailing: FittedBox(
          child: TextButton.icon(
            onPressed: _copyReferralLink,
            icon: const Icon(Icons.link, size: 18),
            label: const Text('Copy Link'),
          ),
        ),
      ),
    );
  }

  Widget _buildContextCards({
    required TournamentProvider tournamentProvider,
    required DrawProvider draw,
    required CharityProvider charity,
    required SubscriptionProvider sub,
    required bool profileWalletLoading,
    required bool quickSnapshotLoading,
    required String latestResultPosition,
  }) {
    final winnerResults = draw.myDrawResults
        .where((item) => item['is_winner'] == true)
        .toList(growable: false);
    final pendingVerificationCount = winnerResults.where((item) {
      final claim = (item['claim'] as Map?)?.cast<String, dynamic>();
      return claim != null &&
          (claim['review_status'] ?? '').toString().toLowerCase() == 'pending';
    }).length;
    final pendingPayoutCount = winnerResults.where((item) {
      final claim = (item['claim'] as Map?)?.cast<String, dynamic>();
      return claim != null &&
          (claim['review_status'] ?? '').toString().toLowerCase() ==
              'approved' &&
          (claim['payout_state'] ?? '').toString().toLowerCase() != 'paid';
    }).length;
    if (_selectedModuleIndex == 1) {
      return _jackpotWinnersCard(tournamentProvider);
    }
    if (_selectedModuleIndex == 2) {
      return _weeklyDrawWinnersCard(tournamentProvider);
    }
    return Column(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Dashboard',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                _metricLine(
                  'Display Name',
                  (_profile?['display_name'] ?? '-').toString(),
                  isLoading: profileWalletLoading,
                ),
                _metricLine(
                  'Skill Level',
                  (_profile?['skill_level'] ?? '-').toString(),
                  isLoading: profileWalletLoading,
                ),
                _metricLine(
                  'Club',
                  (_profile?['club_affiliation'] ?? '-').toString(),
                  isLoading: profileWalletLoading,
                ),
                _metricLine(
                  'Available Amount',
                  '\$${((_wallet?['available_amount'] ?? 0) as num).toDouble().toStringAsFixed(2)}',
                  isLoading: profileWalletLoading,
                ),
                const SizedBox(height: 10),
                LayoutBuilder(
                  builder: (context, walletConstraints) {
                    final stacked = walletConstraints.maxWidth < 540;
                    if (stacked) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: _walletAmountController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Top-up Amount (USD)',
                            ),
                          ),
                          const SizedBox(height: 10),
                          ElevatedButton.icon(
                            onPressed: _walletBusy
                                ? null
                                : () {
                                    final amount = double.tryParse(
                                      _walletAmountController.text.trim(),
                                    );
                                    if (amount == null || amount <= 0) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Enter a valid top-up amount.',
                                          ),
                                        ),
                                      );
                                      return;
                                    }
                                    _openWalletTopupDialog(amount);
                                  },
                            icon: const Icon(
                                Icons.account_balance_wallet_outlined),
                            label: const Text('Top Up Wallet'),
                          ),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        SizedBox(
                          width: 220,
                          child: TextField(
                            controller: _walletAmountController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Top-up Amount (USD)',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton.icon(
                          onPressed: _walletBusy
                              ? null
                              : () {
                                  final amount = double.tryParse(
                                    _walletAmountController.text.trim(),
                                  );
                                  if (amount == null || amount <= 0) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Enter a valid top-up amount.',
                                        ),
                                      ),
                                    );
                                    return;
                                  }
                                  _openWalletTopupDialog(amount);
                                },
                          icon:
                              const Icon(Icons.account_balance_wallet_outlined),
                          label: const Text('Top Up Wallet'),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Quick Snapshot',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                _metricLine(
                  'Active Draws',
                  '${draw.draws.length}',
                  isLoading: quickSnapshotLoading,
                ),
                _metricLine(
                  'Supported Charities',
                  '${charity.charities.length}',
                  isLoading: quickSnapshotLoading,
                ),
                _metricLine(
                  'My Subscriptions',
                  '${sub.subscriptions.length}',
                  isLoading: quickSnapshotLoading,
                ),
                _metricLine(
                  'My Latest Result',
                  latestResultPosition,
                  isLoading: quickSnapshotLoading,
                ),
                _metricLine(
                  'Verification Pending',
                  '$pendingVerificationCount',
                  isLoading: quickSnapshotLoading,
                ),
                _metricLine(
                  'Payout Pending',
                  '$pendingPayoutCount',
                  isLoading: quickSnapshotLoading,
                ),
                _metricLine(
                  'Total Raised',
                  '\$${charity.totalDonations.toStringAsFixed(2)}',
                  isLoading: quickSnapshotLoading,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _jackpotWinnersCard(TournamentProvider tournamentProvider) {
    final winners = tournamentProvider.dashboardJackpotWinners;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '5-Number Winners',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            if (winners.isEmpty)
              const Text('No published 5-number winners yet.')
            else
              ...winners.map((winner) {
                final name = (winner['username'] ?? 'Winner').toString();
                final payout = ((winner['payout_usd'] ?? 0) as num).toDouble();
                final drawKey = (winner['draw_key'] ?? '-').toString();
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    radius: 14,
                    backgroundColor: const Color(0xFFEAF4FB),
                    child: const Text(
                      '5',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1B5D86),
                      ),
                    ),
                  ),
                  title: Text(name),
                  subtitle: Text('Draw: $drawKey'),
                  trailing: Text(
                    '\$${payout.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _weeklyDrawWinnersCard(TournamentProvider tournamentProvider) {
    final winners = tournamentProvider.dashboardWeeklyDrawWinners;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '3 & 4 Number Winners',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            if (winners.isEmpty)
              const Text('No published 3 or 4 number winners yet.')
            else
              ...winners.map((winner) {
                final name = (winner['username'] ?? 'Winner').toString();
                final payout = ((winner['payout_usd'] ?? 0) as num).toDouble();
                final drawKey = (winner['draw_key'] ?? '-').toString();
                final matchLabel =
                    (winner['match_label'] ?? 'Match Winner').toString();
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    radius: 14,
                    backgroundColor: const Color(0xFFEAF4FB),
                    child: Text(
                      (winner['match_count'] ?? '-').toString(),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1B5D86),
                      ),
                    ),
                  ),
                  title: Text(name),
                  subtitle: Text('$matchLabel • Draw: $drawKey'),
                  trailing: Text(
                    '\$${payout.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _metricLine(
    String label,
    String value, {
    bool isLoading = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFF607289)),
            ),
          ),
          if (isLoading)
            SizedBox(
              width: 96,
              child: AppShimmer(
                child: AppSkeletonBox(
                  height: 12,
                  width: 96,
                  radius: 999,
                ),
              ),
            )
          else
            Text(
              value,
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }

  Widget _moduleNavBar() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: List.generate(_modules.length, (index) {
            final module = _modules[index];
            final selected = _selectedModuleIndex == index;
            return InkWell(
              onTap: () {
                setState(() => _selectedModuleIndex = index);
                if (index == 2) {
                  context
                      .read<TournamentProvider>()
                      .loadDashboardBootstrap(silent: true);
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
                      module.icon,
                      size: 16,
                      color: const Color(0xFFD4AF37),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      module.label,
                      style: TextStyle(
                        color: selected
                            ? const Color(0xFF1B5D86)
                            : const Color(0xFF607289),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildModuleContent(
    TournamentProvider tournamentProvider,
    DrawProvider draw,
  ) {
    if (_selectedModuleIndex == 0) {
      final winnerResults = draw.myDrawResults
          .where((item) => item['is_winner'] == true)
          .toList(growable: false);
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Proof Upload',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text(
                'Winner verification applies to winners only. Submit a screenshot link from the golf platform, wait for admin approval, then track payment state from Pending to Paid.',
                style: TextStyle(
                  color: Color(0xFF607289),
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 12),
              if (winnerResults.isEmpty)
                const Text(
                  'No winning entries need proof verification yet.',
                )
              else
                ...winnerResults.map((result) {
                  final claim =
                      (result['claim'] as Map?)?.cast<String, dynamic>() ??
                          const <String, dynamic>{};
                  final reviewStatus =
                      (claim['review_status'] ?? '').toString();
                  final payoutState =
                      (claim['payout_state'] ?? 'pending').toString();
                  final proofUrl = (claim['proof_url'] ?? '').toString();
                  final canSubmitProof = result['can_submit_proof'] == true;
                  final reviewNotes =
                      (claim['review_notes'] ?? '').toString().trim();
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFD7E0EA)),
                      color: const Color(0xFFF8FAFC),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${result['draw_key'] ?? '-'} • ${result['match_label'] ?? 'Winner'}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Verification: ${_claimReviewLabel(reviewStatus)} • Payment: ${_claimPayoutLabel(payoutState)}',
                          style: const TextStyle(
                            color: Color(0xFF607289),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Prize amount: ${_usdFromCents(result['payout_cents'])}',
                          style: const TextStyle(
                            color: Color(0xFF1B5D86),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (reviewNotes.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Admin note: $reviewNotes',
                            style: const TextStyle(
                              color: Color(0xFF8A4B08),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ElevatedButton.icon(
                              onPressed: canSubmitProof
                                  ? () => _openWinnerProofDialog(result)
                                  : null,
                              icon: const Icon(Icons.upload_file_outlined),
                              label: Text(
                                proofUrl.isNotEmpty &&
                                        reviewStatus.toLowerCase() == 'rejected'
                                    ? 'Re-upload Proof'
                                    : 'Upload Proof',
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: proofUrl.trim().isEmpty
                                  ? null
                                  : () => _openExternalUrl(proofUrl),
                              icon: const Icon(Icons.open_in_new),
                              label: const Text('Open Proof'),
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
      );
    }

    if (tournamentProvider.error != null &&
        tournamentProvider.dashboardMyScores.isEmpty &&
        tournamentProvider.dashboardLeaderboard.isEmpty &&
        tournamentProvider.dashboardLiveEvents.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Text(
            tournamentProvider.error!,
            style: const TextStyle(color: Colors.red),
          ),
        ),
      );
    }

    if (_selectedModuleIndex == 1) {
      final leaderboard = tournamentProvider.dashboardLeaderboard;
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Leaderboard (Lowest to Highest)',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              if (leaderboard.isEmpty)
                const Text('No recorded scores yet.')
              else
                ...leaderboard.map(
                  (row) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      radius: 14,
                      backgroundColor: const Color(0xFFEAF4FB),
                      child: Text(
                        '${row['rank'] ?? '-'}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1B5D86),
                        ),
                      ),
                    ),
                    title: Text((row['player_name'] ?? 'Player').toString()),
                    subtitle: Text(
                      'Rounds: ${(row['rounds_played'] ?? 0)} • Last: ${(row['last_round_at'] ?? '-').toString()}',
                    ),
                    trailing: Text(
                      '${(row['average_score'] ?? row['total_points'] ?? 0)} avg',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    final liveEvents = tournamentProvider.dashboardLiveEvents;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Running Events • Updated ${_relativeTime(tournamentProvider.dashboardGeneratedAt)}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            if (liveEvents.isEmpty)
              const Text('No events are currently running.')
            else
              ...liveEvents.map((event) {
                final players = List<Map<String, dynamic>>.from(
                    event['players'] ?? const []);
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFD7E0EA)),
                    color: const Color(0xFFF8FAFC),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${(event['event_name'] ?? event['event_type'] ?? 'Event').toString()} • ${(event['status'] ?? 'in_progress').toString()}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      ...players.map(
                        (p) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              Expanded(
                                  child:
                                      Text((p['name'] ?? 'Player').toString())),
                              Text(
                                p['live_total'] == null
                                    ? '--'
                                    : '${p['live_total']}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  String _relativeTime(DateTime? dt) {
    if (dt == null) return 'now';
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 10) return 'just now';
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }
}

class _DashboardModuleCard extends StatelessWidget {
  const _DashboardModuleCard({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: const Color(0xFFEAF4FB),
          child: Icon(icon, color: const Color(0xFF1B5D86)),
        ),
        title: Text(
          title,
          style: const TextStyle(
            color: Color(0xFF0F172A),
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(color: Color(0xFF607289)),
        ),
      ),
    );
  }
}

class _DashboardModuleData {
  const _DashboardModuleData({
    required this.label,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String label;
  final String title;
  final String subtitle;
  final IconData icon;
}
