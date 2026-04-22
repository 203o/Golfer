import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_provider.dart';
import '../services/tournament_provider.dart';

enum TopNavItem {
  jackpot,
  draw,
  charityTournaments,
  dashboard,
}

class TopNavigationBar extends StatelessWidget {
  const TopNavigationBar({
    super.key,
    required this.activeItem,
    required this.onNavigate,
    this.onOpenMySessions,
    this.onOpenInbox,
    this.trailing,
    this.restrictedMode = false,
    this.isDark = false,
  });

  final TopNavItem activeItem;
  final ValueChanged<TopNavItem> onNavigate;
  final VoidCallback? onOpenMySessions;
  final VoidCallback? onOpenInbox;
  final Widget? trailing;
  final bool restrictedMode;
  final bool isDark;
  static const Color _gold = Color(0xFFD4AF37);

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final tournament = context.watch<TournamentProvider>();
    final user = auth.currentUser;
    final displayName = user?.displayName?.trim();
    final label = (displayName != null && displayName.isNotEmpty)
        ? displayName
        : (user?.email ?? 'Guest');
    final surfaceColor =
        isDark ? const Color(0xFF0E141F) : const Color(0xFFF8FAFC);
    final borderColor =
        isDark ? const Color(0xFF252D3D) : const Color(0xFFD6DEE8);
    final canShowInboxBell = auth.isAuthenticated && !auth.isAdmin;
    final unreadInboxCount = canShowInboxBell ? tournament.unreadInboxCount : 0;
    const bellDockSize = 38.0;
    final reservedTrailingWidth = canShowInboxBell ? (bellDockSize + 22) : 0.0;
    final trailingRightInset = trailing != null ? 44.0 : 14.0;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: EdgeInsets.fromLTRB(14, 10, 14 + reservedTrailingWidth, 10),
          decoration: BoxDecoration(
            color: surfaceColor,
            border: Border(bottom: BorderSide(color: borderColor)),
          ),
          child: Row(
            children: [
              _ProfilePill(
                name: label,
                onTap: () => _openProfileMenu(context),
                isDark: isDark,
              ),
              const SizedBox(width: 10),
              if (!restrictedMode)
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _navButton(
                          TopNavItem.jackpot,
                          '',
                          icon: Icons.home_rounded,
                          iconOnly: true,
                        ),
                        _navButton(
                          TopNavItem.charityTournaments,
                          'Charity Tournaments',
                          icon: Icons.event_available_outlined,
                        ),
                        _navButton(
                          TopNavItem.dashboard,
                          'Dashboard',
                          icon: Icons.person_outline,
                        ),
                      ],
                    ),
                  ),
                )
              else
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _restrictedTitle(activeItem),
                  ),
                ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing!,
              ],
            ],
          ),
        ),
        if (canShowInboxBell)
          Positioned(
            right: trailingRightInset - 4,
            bottom: -8,
            child: Container(
              width: bellDockSize + 8,
              height: 18,
              alignment: Alignment.topCenter,
              color: surfaceColor,
              child: _notificationBell(unreadInboxCount),
            ),
          ),
      ],
    );
  }

  Widget _navButton(
    TopNavItem item,
    String text, {
    IconData? icon,
    bool iconOnly = false,
  }) {
    final active = item == activeItem;
    final activeColor =
        isDark ? const Color(0xFFFF4FA3) : const Color(0xFF1B5D86);
    final inactiveColor =
        isDark ? const Color(0xFF9CA8C2) : const Color(0xFF4E6075);
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: TextButton(
        onPressed: active ? null : () => onNavigate(item),
        style: TextButton.styleFrom(
          foregroundColor: active ? activeColor : inactiveColor,
          disabledForegroundColor: activeColor,
          padding: EdgeInsets.symmetric(
            horizontal: iconOnly ? 10 : 12,
            vertical: 8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null)
              Icon(
                icon,
                size: iconOnly ? 20 : 16,
                color: _gold,
              ),
            if (!iconOnly && text.trim().isNotEmpty) ...[
              const SizedBox(width: 6),
              Text(
                text,
                style: TextStyle(
                  fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _restrictedTitle(TopNavItem item) {
    final textColor =
        isDark ? const Color(0xFFEAF0FF) : const Color(0xFF1B5D86);
    if (item == TopNavItem.jackpot || item == TopNavItem.draw) {
      return const Icon(Icons.home_rounded, color: _gold, size: 20);
    }
    return Text(
      _titleFor(item),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: textColor,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _notificationBell(int unreadCount) {
    final onTap =
        onOpenInbox ?? () => onNavigate(TopNavItem.charityTournaments);
    return Tooltip(
      message: 'Inbox',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isDark ? const Color(0xFF172234) : const Color(0xFFEAF4FB),
            border: Border.all(
              color: isDark ? const Color(0xFF2A3853) : const Color(0xFFD0DFEA),
            ),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              const Center(
                child: Icon(
                  Icons.notifications_outlined,
                  color: _gold,
                  size: 20,
                ),
              ),
              if (unreadCount > 0)
                Positioned(
                  top: 2,
                  right: 2,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    constraints: const BoxConstraints(minWidth: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE53935),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.white, width: 1),
                    ),
                    child: Text(
                      unreadCount > 99 ? '99+' : '$unreadCount',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _titleFor(TopNavItem item) {
    switch (item) {
      case TopNavItem.jackpot:
        return 'Home';
      case TopNavItem.draw:
        return 'Home';
      case TopNavItem.charityTournaments:
        return 'Charity Tournaments';
      case TopNavItem.dashboard:
        return 'Dashboard';
    }
  }

  Future<void> _openProfileMenu(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    final user = auth.currentUser;
    final displayName = user?.displayName?.trim();
    final label = (displayName != null && displayName.isNotEmpty)
        ? displayName
        : (user?.email ?? 'Guest');

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor:
          isDark ? const Color(0xFF121722) : const Color(0xFFF8FAFC),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: isDark
                        ? const Color(0xFFFF4FA3)
                        : const Color(0xFF1993D1),
                    child: Text(
                      label.isNotEmpty ? label[0].toUpperCase() : 'G',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: isDark
                            ? const Color(0xFFF3F6FF)
                            : const Color(0xFF1E3146),
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (!restrictedMode) ...[
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      onNavigate(TopNavItem.dashboard);
                    },
                    icon: const Icon(Icons.person_outline),
                    label: const Text('Open Dashboard'),
                  ),
                ),
              ],
              if (!restrictedMode && onOpenMySessions != null) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      onOpenMySessions!.call();
                    },
                    icon: const Icon(Icons.event_note_outlined),
                    label: const Text('My Sessions'),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: auth.isAuthenticated
                      ? () async {
                          await auth.signOut();
                          if (!context.mounted) return;
                          Navigator.pop(context);
                          onNavigate(TopNavItem.jackpot);
                        }
                      : () => Navigator.pop(context),
                  icon: Icon(auth.isAuthenticated ? Icons.logout : Icons.close),
                  label: Text(auth.isAuthenticated ? 'Logout' : 'Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfilePill extends StatelessWidget {
  const _ProfilePill({
    required this.name,
    required this.onTap,
    required this.isDark,
  });

  final String name;
  final VoidCallback onTap;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final maxNameWidth = MediaQuery.of(context).size.width < 600 ? 78.0 : 150.0;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: isDark ? const Color(0xFF172234) : const Color(0xFFEAF4FB),
          border: Border.all(
            color: isDark ? const Color(0xFF2A3853) : const Color(0xFFD0DFEA),
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 11,
              backgroundColor:
                  isDark ? const Color(0xFFFF4FA3) : const Color(0xFF1993D1),
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : 'G',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxNameWidth),
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isDark
                      ? const Color(0xFFEAF0FF)
                      : const Color(0xFF1D3950),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
