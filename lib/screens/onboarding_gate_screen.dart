import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../services/auth_service.dart';
import '../services/charity_provider.dart';
import '../services/auth_provider.dart';
import '../services/subscription_provider.dart';
import 'admin_dashboard_screen.dart';
import 'user_dashboard_screen.dart';

class OnboardingGateScreen extends StatefulWidget {
  const OnboardingGateScreen({super.key});

  @override
  State<OnboardingGateScreen> createState() => _OnboardingGateScreenState();
}

class _OnboardingGateScreenState extends State<OnboardingGateScreen> {
  static const Color _accentGreen = Color(0xFF1CA36B);
  static const Color _accentGold = Color(0xFFD4AF37);
  static const Color _accentSun = Color(0xFFF4C542);

  bool _loading = true;
  bool _profileCompleted = false;
  bool _profileStateReliable = false;
  String _resolvedRole = 'guest';
  bool _showingProfileDialog = false;
  String? _selectedPlanId;
  String? _selectedCharityId;
  double _charityContributionPct = 10;
  bool _processingPayment = false;
  bool _showCharityRequiredError = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final auth = context.read<AuthProvider>();
    final user = auth.currentUser;
    if (user == null) {
      if (!mounted) return;
      setState(() => _loading = false);
      return;
    }

    final authService = context.read<AuthService>();
    final charity = context.read<CharityProvider>();
    final sub = context.read<SubscriptionProvider>();

    bool done = false;
    bool reliable = false;
    String resolvedRole = auth.backendRole.trim().toLowerCase();
    try {
      await authService.ensureBackendRegistration();
      final profile = await authService.fetchMyProfile();
      done = profile['profile_setup_completed'] == true;
      resolvedRole =
          (profile['role'] ?? auth.backendRole).toString().trim().toLowerCase();
      reliable = true;
    } catch (_) {
      // Retry once; auth/web startup can race with initial token resolution.
      try {
        await Future<void>.delayed(const Duration(milliseconds: 450));
        await authService.ensureBackendRegistration();
        final profile = await authService.fetchMyProfile();
        done = profile['profile_setup_completed'] == true;
        resolvedRole = (profile['role'] ?? auth.backendRole)
            .toString()
            .trim()
            .toLowerCase();
        reliable = true;
      } catch (_) {}
    }

    await Future.wait([
      sub.loadSubscriptions(),
      charity.loadCharities(),
    ]);
    final savedSelection = await charity.getMyCharitySelection();
    final savedCharityId = savedSelection?['charity_id']?.toString();
    final savedContributionPct =
        (savedSelection?['contribution_pct'] as String?) ?? '';
    final parsedContributionPct = double.tryParse(savedContributionPct);

    if (!mounted) return;
    setState(() {
      _profileCompleted = done;
      _profileStateReliable = reliable;
      _resolvedRole = resolvedRole;
      if (parsedContributionPct != null && parsedContributionPct >= 10) {
        _charityContributionPct =
            parsedContributionPct.clamp(10, 100).toDouble();
      }
      if (savedCharityId != null &&
          charity.charities
              .any((c) => (c['id'] ?? '').toString() == savedCharityId)) {
        _selectedCharityId = savedCharityId;
      } else if (_selectedCharityId != null &&
          !charity.charities
              .any((c) => (c['id'] ?? '').toString() == _selectedCharityId)) {
        _selectedCharityId = null;
      }
      _loading = false;
    });

    if (_profileStateReliable && !_profileCompleted) {
      _openProfilePopup();
    }
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

  bool _hasActiveSubscription(SubscriptionProvider sub) {
    if (sub.subscriptions.isEmpty) return false;
    final status =
        (sub.subscriptions.first['status'] ?? '').toString().toLowerCase();
    return status == 'active';
  }

  bool _isConfiguredAdminEmail(String? email) {
    final value = (email ?? '').trim().toLowerCase();
    if (value.isEmpty) return false;
    String raw = '';
    try {
      raw = (dotenv.env['ADMIN_EMAILS'] ?? '').trim();
    } catch (_) {
      raw = '';
    }
    if (raw.isEmpty) return false;
    final allow = raw
        .split(',')
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toSet();
    return allow.contains(value);
  }

  int _planAmountCents(String? planId) {
    switch ((planId ?? '').trim().toLowerCase()) {
      case 'yearly':
      case 'vip':
        return 4999;
      case 'monthly':
      case 'basic':
      default:
        return 999;
    }
  }

  double _minimumContributionUsd(String? planId) {
    return _planAmountCents(planId) * 0.10 / 100.0;
  }

  double _selectedContributionUsd(String? planId) {
    return _planAmountCents(planId) * _charityContributionPct / 100.0 / 100.0;
  }

  Future<void> _markProfileComplete({
    required String displayName,
    required String skillLevel,
    required String clubAffiliation,
  }) async {
    final authService = context.read<AuthService>();
    await authService.completeProfileSetup(
      displayName: displayName.trim(),
      skillLevel: skillLevel,
      clubAffiliation: clubAffiliation.trim(),
    );
    if (!mounted) return;
    setState(() {
      _profileCompleted = true;
      _profileStateReliable = true;
    });
  }

  Future<void> _openProfilePopup() async {
    if (_showingProfileDialog || !_loading && _profileCompleted) return;
    _showingProfileDialog = true;
    final user = context.read<AuthProvider>().currentUser;
    final nameController = TextEditingController(text: user?.displayName ?? '');
    final clubController = TextEditingController();
    String selectedSkill = 'beginner';
    final formKey = GlobalKey<FormState>();

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Complete Profile Setup'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Complete your profile once to continue.',
                style: TextStyle(color: Color(0xFF607289)),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Display Name'),
                validator: (v) => (v == null || v.trim().length < 2)
                    ? 'Enter at least 2 characters'
                    : null,
              ),
              const SizedBox(height: 10),
              StatefulBuilder(
                builder: (context, setModalState) =>
                    DropdownButtonFormField<String>(
                  initialValue: selectedSkill,
                  items: const [
                    DropdownMenuItem(
                        value: 'beginner', child: Text('Beginner')),
                    DropdownMenuItem(
                        value: 'intermediate', child: Text('Intermediate')),
                    DropdownMenuItem(value: 'pro', child: Text('Pro')),
                    DropdownMenuItem(value: 'elite', child: Text('Elite')),
                  ],
                  onChanged: (v) =>
                      setModalState(() => selectedSkill = v ?? 'beginner'),
                  decoration: const InputDecoration(labelText: 'Skill Level'),
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: clubController,
                decoration:
                    const InputDecoration(labelText: 'Club Affiliation'),
                validator: (v) => (v == null || v.trim().length < 2)
                    ? 'Enter your club affiliation'
                    : null,
              ),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              await _markProfileComplete(
                displayName: nameController.text,
                skillLevel: selectedSkill,
                clubAffiliation: clubController.text,
              );
              if (!context.mounted) return;
              Navigator.of(context).pop();
            },
            child: const Text('Save Profile'),
          ),
        ],
      ),
    );

    _showingProfileDialog = false;
  }

  Future<void> _openStripeMockCheckout(String planId) async {
    final charityId = _selectedCharityId;
    if (charityId == null || charityId.isEmpty) {
      if (mounted) {
        setState(() => _showCharityRequiredError = true);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a charity before payment.')),
      );
      return;
    }
    if (_charityContributionPct < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Minimum charity contribution is 10% of the plan fee'),
        ),
      );
      return;
    }

    final emailController = TextEditingController(
      text: context.read<AuthProvider>().currentUser?.email ?? '',
    );
    final cardController = TextEditingController();
    final expController = TextEditingController();
    final cvcController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setModalState) => AlertDialog(
          title: const Text('Stripe Payment (Mock)'),
          content: Form(
            key: formKey,
            child: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: emailController,
                    decoration: const InputDecoration(labelText: 'Email'),
                    validator: (v) => (v == null || !v.contains('@'))
                        ? 'Invalid email'
                        : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: cardController,
                    decoration: const InputDecoration(labelText: 'Card Number'),
                    validator: (v) =>
                        (v == null || v.replaceAll(' ', '').length < 12)
                            ? 'Invalid card number'
                            : null,
                  ),
                  const SizedBox(height: 10),
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
                      const SizedBox(width: 10),
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
                  if (_processingPayment) ...[
                    const SizedBox(height: 14),
                    const CircularProgressIndicator(strokeWidth: 2),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: _processingPayment
                  ? null
                  : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: _processingPayment
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setModalState(() => _processingPayment = true);
                      try {
                        final charityProvider = context.read<CharityProvider>();
                        final subscriptionProvider =
                            context.read<SubscriptionProvider>();
                        await Future.delayed(const Duration(milliseconds: 900));
                        if (cardController.text
                            .replaceAll(' ', '')
                            .endsWith('0002')) {
                          throw Exception('Card declined (mock).');
                        }
                        if (!mounted) return;
                        await subscriptionProvider.createSubscription(
                          '',
                          planId,
                          paymentProvider: 'stripe_mock',
                          charityId: charityId,
                          charityContributionPct: _charityContributionPct,
                        );
                        try {
                          await charityProvider.saveMyCharitySelection(
                            charityId: charityId,
                            contributionPct: _charityContributionPct,
                          );
                        } catch (_) {
                          // Best-effort sync only; the subscription checkout already persists the selection server-side.
                        }
                        if (!dialogContext.mounted) return;
                        Navigator.pop(dialogContext);
                      } catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Payment failed: $e')),
                        );
                        setModalState(() => _processingPayment = false);
                      }
                    },
              child: const Text('Pay Now'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _planCard({
    required String title,
    required String subtitle,
    required String price,
    required String planId,
  }) {
    final selected = _selectedPlanId == planId;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected ? _accentGold : const Color(0xFFD9DEE5),
          width: selected ? 1.4 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 6),
            Text(subtitle, style: const TextStyle(color: Color(0xFF607289))),
            const SizedBox(height: 8),
            Text(
              price,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => setState(() => _selectedPlanId = planId),
                style: OutlinedButton.styleFrom(
                  foregroundColor: selected
                      ? const Color(0xFF8C6A00)
                      : const Color(0xFF1B5D86),
                  side: BorderSide(
                    color: selected
                        ? _accentGold.withValues(alpha: 0.85)
                        : const Color(0xFFD0D8E2),
                  ),
                  backgroundColor: selected
                      ? _accentGold.withValues(alpha: 0.10)
                      : Colors.transparent,
                ),
                child: Text(selected ? 'Selected' : 'Choose Plan'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepPill({
    required String label,
    required bool done,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: done ? color.withValues(alpha: 0.14) : const Color(0xFFEEF3F7),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: done ? color.withValues(alpha: 0.45) : const Color(0xFFD3DDE7),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            done ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 15,
            color: done ? color : const Color(0xFF6E8094),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: done ? color : const Color(0xFF5E7287),
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final sub = context.watch<SubscriptionProvider>();
    final charity = context.watch<CharityProvider>();
    final hasCharities = charity.charities.isNotEmpty;
    final selectedCharity =
        charity.charities.cast<Map<String, dynamic>?>().firstWhere(
              (c) => (c?['id'] ?? '').toString() == (_selectedCharityId ?? ''),
              orElse: () => null,
            );

    if (_loading || auth.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final effectiveRole =
        (_resolvedRole.isNotEmpty ? _resolvedRole : auth.backendRole)
            .trim()
            .toLowerCase();
    final isAdminResolved = auth.isAdmin ||
        effectiveRole == 'admin' ||
        effectiveRole == 'admine' ||
        _isConfiguredAdminEmail(auth.currentUser?.email);
    final isSubscriberResolved = effectiveRole == 'subscriber';
    final hasActiveSubscription = _hasActiveSubscription(sub);

    if (isAdminResolved) {
      return const AdminDashboardScreen();
    }

    // Never hard-lock existing subscribers on transient profile sync failures.
    if (!_profileStateReliable &&
        (hasActiveSubscription || isSubscriberResolved)) {
      return const UserDashboardScreen();
    }

    if (_profileStateReliable && !_profileCompleted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openProfilePopup();
      });
    }

    if (_profileCompleted && (hasActiveSubscription || isSubscriberResolved)) {
      return const UserDashboardScreen();
    }

    final profileStepDone = _profileCompleted;
    final charityStepDone = (_selectedCharityId ?? '').trim().isNotEmpty;
    final paymentStepDone = hasActiveSubscription || isSubscriberResolved;
    final completedSteps = [
      profileStepDone,
      charityStepDone,
      paymentStepDone,
    ].where((v) => v).length;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F7),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Almost there. Activate your account.',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Complete your setup once: profile, charity, then activation.',
                    style: TextStyle(color: Color(0xFF607289)),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$completedSteps of 3 steps completed',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF314759),
                            ),
                          ),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            value: completedSteps / 3,
                            minHeight: 7,
                            backgroundColor: const Color(0xFFE2EAF2),
                            color: _accentGreen,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _stepPill(
                                label: 'Profile',
                                done: profileStepDone,
                                color: _accentGreen,
                              ),
                              _stepPill(
                                label: 'Charity',
                                done: charityStepDone,
                                color: _accentSun,
                              ),
                              _stepPill(
                                label: 'Activation',
                                done: paymentStepDone,
                                color: _accentGold,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (!_profileStateReliable) ...[
                    const SizedBox(height: 8),
                    Card(
                      color: const Color(0xFFFFF9E8),
                      child: ListTile(
                        leading: const Icon(
                          Icons.info_outline,
                          color: Color(0xFF8A6D1A),
                        ),
                        title: const Text('Syncing profile state...'),
                        subtitle: const Text(
                          'We could not confirm your saved profile yet. Tap retry instead of re-entering data.',
                        ),
                        trailing: TextButton(
                          onPressed: _bootstrap,
                          child: const Text('Retry'),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(
                            _profileCompleted
                                ? Icons.check_circle
                                : Icons.account_circle_outlined,
                            color: _profileCompleted
                                ? _accentGreen
                                : const Color(0xFF607289),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _profileCompleted
                                  ? 'Profile completed'
                                  : 'Profile setup required (popup shown)',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          if (!_profileCompleted)
                            TextButton(
                              onPressed: _openProfilePopup,
                              child: const Text('Open'),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Activate Access',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Pick a plan and complete payment to unlock all features.',
                    style: TextStyle(color: Color(0xFF607289)),
                  ),
                  const SizedBox(height: 10),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth < 680) {
                        return Column(
                          children: [
                            _planCard(
                              title: 'Monthly Plan',
                              subtitle: 'Flexible monthly access',
                              price: '\$9.99 / month',
                              planId: 'monthly',
                            ),
                            const SizedBox(height: 10),
                            _planCard(
                              title: 'Yearly Plan',
                              subtitle: 'Discounted annual value',
                              price: '\$49.99 / year',
                              planId: 'yearly',
                            ),
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(
                            child: _planCard(
                              title: 'Monthly Plan',
                              subtitle: 'Flexible monthly access',
                              price: '\$9.99 / month',
                              planId: 'monthly',
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _planCard(
                              title: 'Yearly Plan',
                              subtitle: 'Discounted annual value',
                              price: '\$49.99 / year',
                              planId: 'yearly',
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Choose Charity and Contribution',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Pick a charity now, then choose the percentage of your subscription that goes to that cause every billing cycle.',
                    style: TextStyle(color: Color(0xFF607289), height: 1.35),
                  ),
                  const SizedBox(height: 8),
                  if (!hasCharities)
                    const Card(
                      child: ListTile(
                        title: Text('No active charities available'),
                        subtitle: Text(
                          'Admin must add/activate charities before checkout.',
                        ),
                      ),
                    )
                  else
                    DropdownButtonFormField<String>(
                      initialValue: _selectedCharityId,
                      items: charity.charities
                          .map(
                            (c) => DropdownMenuItem<String>(
                              value: c['id']?.toString(),
                              child: Text(c['name']?.toString() ?? 'Charity'),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() {
                        _selectedCharityId = v;
                        if ((v ?? '').trim().isNotEmpty) {
                          _showCharityRequiredError = false;
                        }
                      }),
                      decoration: const InputDecoration(
                        labelText: 'Supported Charity',
                        hintText: 'Select a charity',
                      ),
                    ),
                  if (hasCharities &&
                      _showCharityRequiredError &&
                      (_selectedCharityId ?? '').trim().isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        'Charity selection is required.',
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  if (selectedCharity != null) ...[
                    const SizedBox(height: 8),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              (selectedCharity['name'] ?? 'Charity').toString(),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              ((selectedCharity['cause'] ?? 'Community Impact')
                                      .toString())
                                  .trim(),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF8C6A00),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              (selectedCharity['description'] ?? '')
                                      .toString()
                                      .trim()
                                      .isEmpty
                                  ? 'No charity snippet available.'
                                  : (selectedCharity['description'] ?? '')
                                      .toString(),
                              style: const TextStyle(color: Color(0xFF607289)),
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              onPressed: () => _openWebsite(
                                selectedCharity['website_url']?.toString(),
                              ),
                              icon: const Icon(Icons.open_in_new, size: 16),
                              label: const Text('Visit Charity Website'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Charity Contribution: ${_charityContributionPct.toStringAsFixed(0)}%',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _selectedPlanId == null
                                ? 'Select a plan to preview the exact charity amount.'
                                : 'Minimum for this plan: \$${_minimumContributionUsd(_selectedPlanId).toStringAsFixed(2)}. Current contribution: \$${_selectedContributionUsd(_selectedPlanId).toStringAsFixed(2)} per billing cycle.',
                            style: const TextStyle(
                              color: Color(0xFF607289),
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Slider(
                            value: _charityContributionPct
                                .clamp(10, 100)
                                .toDouble(),
                            min: 10,
                            max: 100,
                            divisions: 18,
                            label:
                                '${_charityContributionPct.toStringAsFixed(0)}%',
                            onChanged: (value) {
                              setState(() {
                                _charityContributionPct = value.roundToDouble();
                              });
                            },
                          ),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [10, 15, 20, 25].map((pct) {
                              final selected =
                                  _charityContributionPct.round() == pct;
                              return ChoiceChip(
                                label: Text('$pct%'),
                                selected: selected,
                                onSelected: (_) {
                                  setState(() {
                                    _charityContributionPct = pct.toDouble();
                                  });
                                },
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: (!_profileCompleted ||
                              _selectedPlanId == null ||
                              _selectedCharityId == null ||
                              !hasCharities ||
                              _processingPayment)
                          ? null
                          : () => _openStripeMockCheckout(_selectedPlanId!),
                      icon: const Icon(Icons.lock_open),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _accentGreen,
                        foregroundColor: Colors.white,
                      ),
                      label: const Text('Activate Subscription'),
                    ),
                  ),
                  if (sub.error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        sub.error!,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
