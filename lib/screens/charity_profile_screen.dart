import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../services/auth_provider.dart';
import '../services/charity_provider.dart';

class CharityProfileScreen extends StatefulWidget {
  const CharityProfileScreen({
    super.key,
    required this.charityId,
    this.initialCharity,
  });

  final String charityId;
  final Map<String, dynamic>? initialCharity;

  @override
  State<CharityProfileScreen> createState() => _CharityProfileScreenState();
}

class _CharityProfileScreenState extends State<CharityProfileScreen> {
  Map<String, dynamic>? _charity;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _charity = widget.initialCharity;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final charity = await context
          .read<CharityProvider>()
          .loadCharityProfile(widget.charityId);
      if (!mounted) return;
      setState(() {
        _charity = charity ?? _charity;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
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

  String _formatEventDate(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return 'Date to be announced';
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return value;
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[parsed.month - 1]} ${parsed.day}, ${parsed.year}';
  }

  Future<void> _openContributionSheet(Map<String, dynamic> charity) async {
    if (!context.read<AuthProvider>().isAuthenticated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to choose a charity.')),
      );
      return;
    }

    final savedPct = double.tryParse(
          (context
                      .read<CharityProvider>()
                      .myCharitySelection?['contribution_pct'] ??
                  '10')
              .toString(),
        ) ??
        10;
    double contributionPct = savedPct.clamp(10, 100).toDouble();

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Choose ${charity['name'] ?? 'Charity'}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'This sets your default charity contribution for signup and future subscription renewals.',
                  style: TextStyle(
                    color: Colors.blueGrey.shade700,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Contribution: ${contributionPct.toStringAsFixed(0)}%',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Slider(
                  value: contributionPct,
                  min: 10,
                  max: 100,
                  divisions: 18,
                  label: '${contributionPct.toStringAsFixed(0)}%',
                  onChanged: (value) {
                    setModalState(() {
                      contributionPct = value.roundToDouble();
                    });
                  },
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [10, 15, 20, 25].map((pct) {
                    return ChoiceChip(
                      label: Text('$pct%'),
                      selected: contributionPct.round() == pct,
                      onSelected: (_) {
                        setModalState(() {
                          contributionPct = pct.toDouble();
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      try {
                        await context
                            .read<CharityProvider>()
                            .saveMyCharitySelection(
                              charityId: (charity['id'] ?? '').toString(),
                              contributionPct: contributionPct,
                            );
                        if (!context.mounted) return;
                        Navigator.of(context).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Charity preference saved'),
                          ),
                        );
                      } catch (e) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Unable to save: $e')),
                        );
                      }
                    },
                    child: const Text('Save Charity Preference'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openDonationDialog(Map<String, dynamic> charity) async {
    if (!context.read<AuthProvider>().isAuthenticated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to make a donation.')),
      );
      return;
    }

    final controller = TextEditingController(text: '10');
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Donate to ${charity['name'] ?? 'Charity'}'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Donation Amount (USD)',
            hintText: '10.00',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final amount = double.tryParse(controller.text.trim());
              if (amount == null || amount < 1) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    content: Text('Enter at least \$1.00 for a one-time gift.'),
                  ),
                );
                return;
              }
              try {
                if (!mounted) return;
                final charityProvider = context.read<CharityProvider>();
                final messenger = ScaffoldMessenger.of(context);
                await charityProvider.createIndependentDonation(
                  charityId: (charity['id'] ?? '').toString(),
                  amountUsd: amount,
                );
                await _load();
                if (!dialogContext.mounted) return;
                Navigator.of(dialogContext).pop();
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Donation recorded successfully'),
                  ),
                );
              } catch (e) {
                if (!dialogContext.mounted) return;
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  SnackBar(content: Text('Donation failed: $e')),
                );
              }
            },
            child: const Text('Donate Once'),
          ),
        ],
      ),
    );
  }

  Widget _heroImage(String? url) {
    if ((url ?? '').trim().isEmpty) {
      return Container(
        height: 240,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            colors: [Color(0xFF0F766E), Color(0xFFD4AF37)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Image.network(
        url!,
        height: 240,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          height: 240,
          color: const Color(0xFFE7EEF3),
          alignment: Alignment.center,
          child: const Icon(Icons.image_outlined, size: 34),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final charity = _charity;
    final gallery =
        List<String>.from(charity?['gallery_image_urls'] ?? const []);
    final events = List<Map<String, dynamic>>.from(
        charity?['upcoming_events'] ?? const []);

    return Scaffold(
      appBar: AppBar(
        title: Text((charity?['name'] ?? 'Charity Profile').toString()),
      ),
      body: _loading && charity == null
          ? const Center(child: CircularProgressIndicator())
          : charity == null
              ? Center(
                  child: Text(_error ?? 'Unable to load charity profile'),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(18),
                    children: [
                      _heroImage(charity['hero_image_url']?.toString()),
                      const SizedBox(height: 18),
                      Text(
                        (charity['name'] ?? 'Charity').toString(),
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _TagChip(
                            icon: Icons.favorite_outline,
                            text: (charity['cause'] ?? 'Community Impact')
                                .toString(),
                          ),
                          if ((charity['location'] ?? '')
                              .toString()
                              .trim()
                              .isNotEmpty)
                            _TagChip(
                              icon: Icons.location_on_outlined,
                              text: charity['location'].toString(),
                            ),
                          _TagChip(
                            icon: Icons.volunteer_activism_outlined,
                            text:
                                '\$${(((charity['total_raised_cents'] ?? 0) as num).toDouble() / 100.0).toStringAsFixed(2)} raised',
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        (charity['description'] ?? 'No description available.')
                            .toString(),
                        style: const TextStyle(
                          color: Color(0xFF55677D),
                          height: 1.55,
                        ),
                      ),
                      if ((charity['spotlight_text'] ?? '')
                          .toString()
                          .trim()
                          .isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF7DA),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFE5C84D)),
                          ),
                          child: Text(
                            charity['spotlight_text'].toString(),
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF594400),
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          ElevatedButton.icon(
                            onPressed: () => _openContributionSheet(charity),
                            icon: const Icon(Icons.favorite_border),
                            label: const Text('Choose for Subscription'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => _openDonationDialog(charity),
                            icon: const Icon(Icons.volunteer_activism_outlined),
                            label: const Text('Donate Once'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => _openWebsite(
                                charity['website_url']?.toString()),
                            icon: const Icon(Icons.open_in_new),
                            label: const Text('Visit Website'),
                          ),
                        ],
                      ),
                      if (gallery.isNotEmpty) ...[
                        const SizedBox(height: 26),
                        const Text(
                          'Gallery',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 150,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: gallery.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 12),
                            itemBuilder: (context, index) => ClipRRect(
                              borderRadius: BorderRadius.circular(18),
                              child: Image.network(
                                gallery[index],
                                width: 220,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  width: 220,
                                  color: const Color(0xFFE7EEF3),
                                  alignment: Alignment.center,
                                  child: const Icon(Icons.image_not_supported),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 26),
                      const Text(
                        'Upcoming Events',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (events.isEmpty)
                        const Card(
                          child: ListTile(
                            title: Text('No upcoming charity events yet'),
                            subtitle: Text(
                              'This profile will list golf days and partner events as they are added.',
                            ),
                          ),
                        )
                      else
                        ...events.map((event) {
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    (event['title'] ?? 'Upcoming Event')
                                        .toString(),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _formatEventDate(
                                        event['event_date']?.toString()),
                                    style: const TextStyle(
                                      color: Color(0xFF8C6A00),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  if ((event['location'] ?? '')
                                      .toString()
                                      .trim()
                                      .isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      event['location'].toString(),
                                      style: const TextStyle(
                                        color: Color(0xFF55677D),
                                      ),
                                    ),
                                  ],
                                  if ((event['description'] ?? '')
                                      .toString()
                                      .trim()
                                      .isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      event['description'].toString(),
                                      style: const TextStyle(
                                        color: Color(0xFF55677D),
                                        height: 1.4,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        }),
                    ],
                  ),
                ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FA),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFD7E0E8)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF607289)),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Color(0xFF314759),
            ),
          ),
        ],
      ),
    );
  }
}
