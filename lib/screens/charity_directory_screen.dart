import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/charity_provider.dart';
import 'charity_profile_screen.dart';

class CharityDirectoryScreen extends StatefulWidget {
  const CharityDirectoryScreen({super.key});

  @override
  State<CharityDirectoryScreen> createState() => _CharityDirectoryScreenState();
}

class _CharityDirectoryScreenState extends State<CharityDirectoryScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedCause = 'All';
  bool _featuredOnly = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<CharityProvider>();
      if (provider.charities.isEmpty) {
        provider.loadCharities();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _filtered(List<Map<String, dynamic>> charities) {
    final search = _searchController.text.trim().toLowerCase();
    return charities.where((charity) {
      if (_featuredOnly && charity['is_featured'] != true) {
        return false;
      }
      if (_selectedCause != 'All' &&
          (charity['cause'] ?? '').toString() != _selectedCause) {
        return false;
      }
      if (search.isEmpty) {
        return true;
      }
      final haystack = [
        (charity['name'] ?? '').toString(),
        (charity['description'] ?? '').toString(),
        (charity['cause'] ?? '').toString(),
        (charity['location'] ?? '').toString(),
        (charity['spotlight_text'] ?? '').toString(),
      ].join(' ').toLowerCase();
      return haystack.contains(search);
    }).toList();
  }

  Widget _card(Map<String, dynamic> charity) {
    final imageUrl = (charity['hero_image_url'] ?? '').toString();
    final raisedUsd =
        (((charity['total_raised_cents'] ?? 0) as num).toDouble() / 100.0);
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CharityProfileScreen(
                charityId: (charity['id'] ?? '').toString(),
                initialCharity: charity,
              ),
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (imageUrl.isNotEmpty)
              Image.network(
                imageUrl,
                height: 180,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  height: 180,
                  color: const Color(0xFFE9EFF4),
                  alignment: Alignment.center,
                  child: const Icon(Icons.image_outlined),
                ),
              )
            else
              Container(
                height: 180,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF1CA36B), Color(0xFFD4AF37)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (charity['is_featured'] == true)
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF4CC),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'Spotlight Charity',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF8C6A00),
                        ),
                      ),
                    ),
                  Text(
                    (charity['name'] ?? 'Charity').toString(),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${charity['cause'] ?? 'Community Impact'}  -  ${charity['location'] ?? 'Global'}',
                    style: const TextStyle(
                      color: Color(0xFF8C6A00),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    (charity['description'] ?? 'No description available.')
                        .toString(),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF55677D),
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '\$${raisedUsd.toStringAsFixed(2)} raised',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF314759),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CharityProfileScreen(
                              charityId: (charity['id'] ?? '').toString(),
                              initialCharity: charity,
                            ),
                          ),
                        );
                      },
                      child: const Text('View Profile'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CharityProvider>();
    final causes = <String>['All', ...provider.availableCauses];
    final filtered = _filtered(provider.charities);

    return Scaffold(
      appBar: AppBar(title: const Text('Charity Directory')),
      body: RefreshIndicator(
        onRefresh: () => context.read<CharityProvider>().loadCharities(),
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            const Text(
              'Discover charities supported by the platform, filter by cause, and open full profiles with current events and donation actions.',
              style: TextStyle(
                color: Color(0xFF55677D),
                height: 1.45,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search charities, causes, or event themes',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.close),
                      ),
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: causes.map((cause) {
                return ChoiceChip(
                  label: Text(cause),
                  selected: _selectedCause == cause,
                  onSelected: (_) {
                    setState(() {
                      _selectedCause = cause;
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _featuredOnly,
              onChanged: (value) {
                setState(() {
                  _featuredOnly = value;
                });
              },
              title: const Text('Show spotlight charities only'),
            ),
            const SizedBox(height: 10),
            Text(
              '${filtered.length} charities found',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFF314759),
              ),
            ),
            const SizedBox(height: 14),
            if (provider.isLoading && provider.charities.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (filtered.isEmpty)
              const Card(
                child: ListTile(
                  title: Text('No charities match that search'),
                  subtitle: Text(
                    'Try a different cause or clear the spotlight filter.',
                  ),
                ),
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 900;
                  if (!wide) {
                    return Column(
                      children: filtered
                          .map(
                            (charity) => Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: _card(charity),
                            ),
                          )
                          .toList(),
                    );
                  }
                  return Wrap(
                    spacing: 14,
                    runSpacing: 14,
                    children: filtered
                        .map(
                          (charity) => SizedBox(
                            width: (constraints.maxWidth - 14) / 2,
                            child: _card(charity),
                          ),
                        )
                        .toList(),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
