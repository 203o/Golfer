import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/tournament_provider.dart';

class TournamentAdminScreen extends StatefulWidget {
  const TournamentAdminScreen({super.key});

  @override
  State<TournamentAdminScreen> createState() => _TournamentAdminScreenState();
}

class _TournamentAdminScreenState extends State<TournamentAdminScreen> {
  final _courseName = TextEditingController();
  final _courseLocation = TextEditingController(text: 'Nairobi');
  final _courseRating = TextEditingController(text: '72.0');
  final _courseSlope = TextEditingController(text: '113');
  final _courseHoles = TextEditingController(text: '18');
  final _roundId = TextEditingController();
  final _userId = TextEditingController();
  final _eventTitle = TextEditingController(text: 'Solo Challenge');
  final _eventType = TextEditingController(text: 'solo');
  final _eventMinDonation = TextEditingController(text: '200');
  final _eventStart = TextEditingController();
  final _eventEnd = TextEditingController();
  final _eventKey = TextEditingController(text: 'weekly-event');
  final _teamSize = TextEditingController(text: '4');
  final _userIdsCsv = TextEditingController(text: '1,2,3,4,5,6,7,8');
  bool _busy = false;

  @override
  void dispose() {
    _courseName.dispose();
    _courseLocation.dispose();
    _courseRating.dispose();
    _courseSlope.dispose();
    _courseHoles.dispose();
    _roundId.dispose();
    _userId.dispose();
    _eventTitle.dispose();
    _eventType.dispose();
    _eventMinDonation.dispose();
    _eventStart.dispose();
    _eventEnd.dispose();
    _eventKey.dispose();
    _teamSize.dispose();
    _userIdsCsv.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _createCourse() async {
    final name = _courseName.text.trim();
    if (name.isEmpty) {
      _snack('Course name required');
      return;
    }
    final courseRating = double.tryParse(_courseRating.text.trim());
    final slope = int.tryParse(_courseSlope.text.trim());
    final holes = int.tryParse(_courseHoles.text.trim());
    if (courseRating == null || slope == null || holes == null) {
      _snack('Invalid course values');
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<TournamentProvider>().createCourse(
            name: name,
            location: _courseLocation.text.trim(),
            courseRating: courseRating,
            slopeRating: slope,
            holesCount: holes,
          );
      _snack('Course created');
    } catch (e) {
      _snack('Create course failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _lockRound() async {
    final id = _roundId.text.trim();
    if (id.isEmpty) {
      _snack('Enter round id');
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<TournamentProvider>().lockRound(roundId: id);
      _snack('Round finalized');
    } catch (e) {
      _snack('Lock failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _recomputeForUser() async {
    final id = int.tryParse(_userId.text.trim());
    if (id == null) {
      _snack('Enter numeric user id');
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<TournamentProvider>().recomputeRating(userId: id);
      _snack('Rating recomputed for user $id');
    } catch (e) {
      _snack('Recompute failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadFlags() async {
    setState(() => _busy = true);
    try {
      await context.read<TournamentProvider>().loadFraudFlags(statusFilter: 'open');
      _snack('Loaded open fraud flags');
    } catch (e) {
      _snack('Load flags failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _generateTeams() async {
    final teamSize = int.tryParse(_teamSize.text.trim());
    final ids = _userIdsCsv.text
        .split(',')
        .map((e) => int.tryParse(e.trim()))
        .whereType<int>()
        .toList();
    if (teamSize == null || ids.isEmpty) {
      _snack('Provide team size and valid user ids');
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<TournamentProvider>().generateTeamDraw(
            eventKey: _eventKey.text.trim(),
            teamSize: teamSize,
            userIds: ids,
          );
      _snack('Team draw generated');
    } catch (e) {
      _snack('Generate draw failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createEvent() async {
    final title = _eventTitle.text.trim();
    final eventType = _eventType.text.trim();
    final minDonation = int.tryParse(_eventMinDonation.text.trim());
    final now = DateTime.now().toUtc();
    final startAt = DateTime.tryParse(_eventStart.text.trim())?.toUtc() ?? now;
    final endAt = DateTime.tryParse(_eventEnd.text.trim())?.toUtc() ?? now.add(const Duration(days: 7));

    if (title.isEmpty || minDonation == null) {
      _snack('Provide valid event title and minimum donation cents');
      return;
    }

    setState(() => _busy = true);
    try {
      await context.read<TournamentProvider>().createEvent(
            title: title,
            eventType: eventType,
            minDonationCents: minDonation,
            startAt: startAt,
            endAt: endAt,
            description: 'Impact charity event',
          );
      _snack('Event created');
    } catch (e) {
      _snack('Create event failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TournamentProvider>();
    final latestDraw = provider.latestTeamDraw;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Tournament Admin'),
        backgroundColor: Colors.transparent,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Create Course', style: TextStyle(color: Colors.white, fontSize: 18)),
            const SizedBox(height: 8),
            TextField(controller: _courseName, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Course name')),
            TextField(controller: _courseLocation, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Location')),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _courseRating,
                    style: const TextStyle(color: Colors.white),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Course rating'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _courseSlope,
                    style: const TextStyle(color: Colors.white),
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Slope'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _courseHoles,
                    style: const TextStyle(color: Colors.white),
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Holes'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: _busy ? null : _createCourse, child: const Text('Create Course')),
            const Divider(height: 28),
            const Text('Create Event', style: TextStyle(color: Colors.white, fontSize: 18)),
            TextField(controller: _eventTitle, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Event title')),
            TextField(
              controller: _eventType,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'Event type (solo/one_on_one/skill_challenge/group_challenge/charity_sprint)'),
            ),
            TextField(
              controller: _eventMinDonation,
              style: const TextStyle(color: Colors.white),
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Suggested donation cents'),
            ),
            TextField(
              controller: _eventStart,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'Start ISO (optional)'),
            ),
            TextField(
              controller: _eventEnd,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'End ISO (optional)'),
            ),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: _busy ? null : _createEvent, child: const Text('Create Event')),
            const Divider(height: 28),
            const Text('Round Moderation', style: TextStyle(color: Colors.white, fontSize: 18)),
            TextField(controller: _roundId, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Round ID')),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: _busy ? null : _lockRound, child: const Text('Finalize Verified Round')),
            const Divider(height: 28),
            const Text('Ratings', style: TextStyle(color: Colors.white, fontSize: 18)),
            TextField(controller: _userId, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'User ID')),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: _busy ? null : _recomputeForUser, child: const Text('Recompute User Rating')),
            const Divider(height: 28),
            const Text('Team Draw', style: TextStyle(color: Colors.white, fontSize: 18)),
            TextField(controller: _eventKey, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Event key')),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _teamSize,
                    style: const TextStyle(color: Colors.white),
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Team size'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _userIdsCsv,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(labelText: 'User IDs CSV'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: _busy ? null : _generateTeams, child: const Text('Generate Teams')),
            const Divider(height: 28),
            ElevatedButton(onPressed: _busy ? null : _loadFlags, child: const Text('Load Open Fraud Flags')),
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: CircularProgressIndicator(),
              ),
            const SizedBox(height: 12),
            if (provider.fraudFlags.isNotEmpty) ...[
              const Text('Fraud Flags', style: TextStyle(color: Colors.white, fontSize: 16)),
              const SizedBox(height: 8),
              ...provider.fraudFlags.take(10).map(
                    (f) => ListTile(
                      title: Text(
                        '${f['flag_type']} (user ${f['user_id']})',
                        style: const TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        'Severity: ${f['severity']} | Status: ${f['status']}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
                  ),
            ],
            if (latestDraw != null) ...[
              const SizedBox(height: 12),
              Text(
                'Latest Draw Balance: ${latestDraw['balance_score']}',
                style: const TextStyle(color: Colors.greenAccent),
              ),
            ],
            if (provider.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(provider.error!, style: const TextStyle(color: Colors.redAccent)),
              ),
          ],
        ),
      ),
    );
  }
}
