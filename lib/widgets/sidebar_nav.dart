import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'skoutar_logo.dart';

class NavItem {
  final IconData icon;
  final String label;
  final bool requiresPlus;
  const NavItem(this.icon, this.label, {this.requiresPlus = false});
}

/// Static nav structure — 1:1 with the R app's `tab_map` / sidebar links.
/// Professional outline icons only — no colorful/emoji glyphs, so every
/// entry renders in a single solid color consistent with the rest of the
/// sidebar (see [_navTile]).
const List<NavItem> mainNavItems = [
  NavItem(Icons.edit_note_outlined, 'Game Input'),
  NavItem(Icons.bar_chart_outlined, 'Overview'),
  NavItem(Icons.donut_large_outlined, 'Pitch Breakdown'),
  NavItem(Icons.psychology_outlined, 'Count & Approach', requiresPlus: true),
  NavItem(Icons.map_outlined, 'Spray Chart'),
  NavItem(Icons.receipt_long_outlined, 'Game Logs'),
  NavItem(Icons.timeline_outlined, 'Pitch Sequencing', requiresPlus: true),
  NavItem(Icons.visibility_outlined, 'Scouting Report', requiresPlus: true),
  NavItem(Icons.table_chart_outlined, 'Edit Raw Data'),
  NavItem(Icons.edit_outlined, 'Edit At-Bats'),
];

class SidebarNav extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelect;
  final bool isPlus;
  final String pitcherName;
  final VoidCallback onLogout;

  /// Whether the sidebar is showing its narrow, icon-only form. Purely a
  /// display concern — [onToggleCollapse] is what flips it, owned by the
  /// parent (HomeShell) so the collapsed/expanded choice survives screen
  /// switches.
  final bool collapsed;
  final VoidCallback onToggleCollapse;

  const SidebarNav({
    super.key,
    required this.selected,
    required this.onSelect,
    required this.isPlus,
    required this.pitcherName,
    required this.onLogout,
    this.collapsed = false,
    required this.onToggleCollapse,
  });

  static const double expandedWidth = 230;
  static const double collapsedWidth = 64;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeInOut,
      width: collapsed ? collapsedWidth : expandedWidth,
      color: AppColors.ink,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(collapsed ? 8 : 16, 16, collapsed ? 8 : 16, 8),
              child: collapsed
                  ? Column(
                      children: [
                        SkoutarLogo(height: 28),
                        const SizedBox(height: 8),
                        IconButton(
                          icon: const Icon(Icons.logout, color: Colors.white70, size: 18),
                          tooltip: 'Sign out',
                          onPressed: onLogout,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        // The SKOUTAR logo already carries the wordmark, so it
                        // stands alone (no separate app-name text beside it).
                        Expanded(
                          child: Align(
                              alignment: Alignment.centerLeft,
                              child: SkoutarLogo(height: 44)),
                        ),
                        IconButton(
                          icon: const Icon(Icons.logout, color: Colors.white70, size: 18),
                          tooltip: 'Sign out',
                          onPressed: onLogout,
                        ),
                      ],
                    ),
            ),
            // ── Collapse / expand toggle ────────────────────────────
            Tooltip(
              message: collapsed ? 'Expand sidebar' : 'Collapse sidebar',
              child: InkWell(
                onTap: onToggleCollapse,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    mainAxisAlignment:
                        collapsed ? MainAxisAlignment.center : MainAxisAlignment.end,
                    children: [
                      if (!collapsed)
                        const Padding(
                          padding: EdgeInsets.only(right: 4),
                          child: Text('Collapse',
                              style: TextStyle(color: Colors.white54, fontSize: 11)),
                        ),
                      Icon(
                        collapsed ? Icons.chevron_right : Icons.chevron_left,
                        color: Colors.white54,
                        size: 18,
                      ),
                      if (!collapsed) const SizedBox(width: 10),
                    ],
                  ),
                ),
              ),
            ),
            if (collapsed)
              Tooltip(
                message: pitcherName,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.sports_baseball_outlined,
                      color: Colors.white, size: 14),
                ),
              )
            else
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.sports_baseball_outlined,
                        color: Colors.white, size: 13),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        pitcherName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            const Divider(color: Colors.white24, height: 20),
            // The nav list scrolls on its own so every entry stays
            // reachable on short screens (e.g. a phone in landscape).
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _sectionLabel('MAIN'),
                    _navTile(mainNavItems[0]),
                    _navTile(mainNavItems[1]),
                    _sectionLabel('ANALYTICS'),
                    _navTile(mainNavItems[2]),
                    _navTile(mainNavItems[3]),
                    _navTile(mainNavItems[4]),
                    _navTile(mainNavItems[5]),
                    _navTile(mainNavItems[6]),
                    _navTile(mainNavItems[7]),
                    _sectionLabel('DATA'),
                    _navTile(mainNavItems[8]),
                    _navTile(mainNavItems[9]),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    if (collapsed) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: Divider(color: Colors.white24, height: 1, indent: 16, endIndent: 16),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
          color: Colors.white.withOpacity(0.4),
        ),
      ),
    );
  }

  Widget _navTile(NavItem item) {
    final locked = item.requiresPlus && !isPlus;
    final active = selected == item.label;
    final tile = InkWell(
      onTap: locked ? null : () => onSelect(item.label),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 11, horizontal: collapsed ? 0 : 18),
        alignment: collapsed ? Alignment.center : null,
        decoration: BoxDecoration(
          color: active ? AppColors.brandOrange.withOpacity(0.22) : null,
          border: Border(
            left: BorderSide(
              width: 3,
              color: active ? AppColors.brandOrange : Colors.transparent,
            ),
          ),
        ),
        child: collapsed
            ? Stack(
                alignment: Alignment.center,
                children: [
                  Icon(item.icon,
                      size: 18,
                      color: locked
                          ? AppColors.navIconOrange.withOpacity(0.35)
                          : AppColors.navIconOrange),
                  if (locked)
                    const Positioned(
                      right: 14,
                      bottom: 2,
                      child: Icon(Icons.lock, size: 10, color: Colors.white38),
                    ),
                ],
              )
            : Row(
                children: [
                  Icon(item.icon,
                      size: 17,
                      color: locked
                          ? AppColors.navIconOrange.withOpacity(0.35)
                          : AppColors.navIconOrange),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item.label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: locked ? Colors.white38 : Colors.white.withOpacity(0.85),
                        fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                  if (locked)
                    const Icon(Icons.lock, size: 13, color: Colors.white38),
                ],
              ),
      ),
    );
    return collapsed ? Tooltip(message: item.label, child: tile) : tile;
  }
}
