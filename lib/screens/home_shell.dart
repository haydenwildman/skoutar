import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_session.dart';
import '../theme/app_theme.dart';
import '../widgets/skoutar_logo.dart';
import '../utils/responsive.dart';
import '../widgets/sidebar_nav.dart';
import 'login_screen.dart';
import 'pitcher_switcher_dialog.dart';
import 'game_input_screen.dart';
import 'overview_screen.dart';
import 'pitch_breakdown_screen.dart';
import 'count_approach_screen.dart';
import 'spray_chart_screen.dart';
import 'game_logs_screen.dart';
import 'pitch_sequencing_screen.dart';
import 'scouting_report_screen.dart';
import 'edit_raw_data_screen.dart';
import 'edit_at_bats_screen.dart';
import '../bullpen/analysis_screen.dart';
import '../bullpen/bullpen_screen.dart';
import '../bullpen/repository.dart';
import '../bullpen/store.dart';
import '../widgets/stat_hold_info.dart';

/// The authenticated shell of the app: persistent sidebar + a body that
/// swaps between the feature screens, mirroring the R app's
/// `sbNav()` / `.tab-page` show/hide behavior.
class HomeShell extends StatefulWidget {
  /// Where Bullpen / Game Mode data is saved. Defaults to Supabase; tests
  /// pass an in-memory repository.
  final BullpenRepository? bullpenRepository;
  const HomeShell({super.key, this.bullpenRepository});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  String _selected = 'Game Input';
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _drawerOpenOnMobile = false;
  // Only meaningful for the wide/desktop layout — the mobile Drawer is
  // already inherently collapsible (open/close), so this only affects the
  // persistent side rail shown at >=900px width.
  bool _sidebarCollapsed = false;

  /// Bullpen + Pitching Analysis state, shared by both tabs (so a plan made
  /// on Pitching Analysis can be sent to Bullpen).
  late final BullpenStore _bullpen;
  late final AppSession _session;

  @override
  void initState() {
    super.initState();
    final session = context.read<AppSession>();
    _session = session;
    _bullpen = BullpenStore(
      repo: widget.bullpenRepository ?? SupabaseBullpenRepository(),
      userIdProvider: () => session.activePitcherId, // the ACTIVE pitcher
    );
    session.onActivePitcherChanged = () => _bullpen.reloadForPitcher();
    _bullpen.addListener(_onBullpenChanged);
    _bullpen.load();
    WidgetsBinding.instance.addObserver(this);
  }

  /// Finish any save still in flight whenever the app is sent to the
  /// background, hidden, or closed (phone suspension, minimized window).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _session.flushPendingWrites();
    }
  }

  /// "Send to Bullpen" asks the shell to switch tabs.
  void _onBullpenChanged() {
    final tab = _bullpen.navigateRequest;
    if (tab != null) {
      _bullpen.clearNavigateRequest();
      if (mounted) setState(() => _selected = tab);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _session.onActivePitcherChanged = null;
    _bullpen.removeListener(_onBullpenChanged);
    _bullpen.dispose();
    super.dispose();
  }

  /// Looks up the same outline icon already used for this section in the
  /// sidebar, so every screen's top bar carries the "[ICON] PRIMARY TITLE"
  /// pattern consistently, without duplicating an icon map per-screen.
  IconData _iconFor(String label) {
    for (final item in mainNavItems) {
      if (item.label == label) return item.icon;
    }
    return Icons.circle_outlined;
  }

  Widget _buildBody(String label) {
    switch (label) {
      case 'Game Input':
        return const GameInputScreen();
      case 'Overview':
        return const OverviewScreen();
      case 'Pitch Breakdown':
        return const PitchBreakdownScreen();
      case 'Count & Approach':
        return const CountApproachScreen();
      case 'Spray Chart':
        return const SprayChartScreen();
      case 'Game Logs':
        return const GameLogsScreen();
      case 'Pitch Sequencing':
        return const PitchSequencingScreen();
      case 'Scouting Report':
        return const ScoutingReportScreen();
      case 'Edit Raw Data':
        return const EditRawDataScreen();
      case 'Edit At-Bats':
        return const EditAtBatsScreen();
      case 'Bullpen':
        return const BullpenScreen();
      case 'Pitching Analysis':
        return const PitchingAnalysisScreen();
      default:
        return const GameInputScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<BullpenStore>.value(
      value: _bullpen,
      child: Builder(builder: (ctx) {
        final switching = ctx.watch<AppSession>().switchingPitcher;
        return Stack(
          fit: StackFit.expand,
          children: [
            _buildShell(ctx),
            // Blocks input while another pitcher's data loads, so nothing can
            // be logged against the wrong pitcher mid-switch.
            if (switching)
              const Positioned.fill(
                child: ColoredBox(
                  color: Color(0x66000000),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        );
      }),
    );
  }

  Widget _buildShell(BuildContext context) {
    final session = context.watch<AppSession>();
    final isNarrow = MediaQuery.of(context).size.width < 900;

    final sidebar = SidebarNav(
      selected: _selected,
      onSelect: (label) {
        setState(() {
          _selected = label;
          _drawerOpenOnMobile = false;
        });
        // On the slide-out (mobile) navigation, picking a page closes it.
        if (isNarrow) _scaffoldKey.currentState?.closeDrawer();
      },
      isPlus: session.isPlus,
      pitcherName: session.activePitcherName,
      onAccount: () => showPitcherSwitcher(context),
      onLogout: () async {
        await session.logout();
        if (!context.mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      },
      // Always expanded inside the mobile Drawer (isNarrow) — collapsing
      // only makes sense for the persistent side rail on wide screens.
      collapsed: isNarrow ? false : _sidebarCollapsed,
      onToggleCollapse: () => setState(() => _sidebarCollapsed = !_sidebarCollapsed),
    );

    if (isNarrow) {
      final screenWidth = MediaQuery.sizeOf(context).width;
      final pad = Responsive.pagePadding(context);
      return Scaffold(
        key: _scaffoldKey,
        appBar: AppBar(
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SkoutarLogo(height: 32),
              const SizedBox(width: 8),
              Icon(_iconFor(_selected), size: 18, color: AppColors.navIconOrange),
              const SizedBox(width: 6),
              Flexible(
                child: Text(_selected,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          // The explicit `leading` replaces Flutter's automatic menu
          // button, so it must open the drawer itself.
          leading: HoldTip(message: 'Menu', child: IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
          )),
        ),
        // Same sidebar widget as desktop, sized to its natural width
        // (capped so it never covers the whole phone screen).
        drawer: Drawer(
          width: screenWidth * 0.85 < SidebarNav.expandedWidth + 20
              ? screenWidth * 0.85
              : SidebarNav.expandedWidth + 20,
          backgroundColor: AppColors.ink,
          child: sidebar,
        ),
        body: SafeArea(
          child: Stack(
            children: [
              Positioned(
                right: -60,
                bottom: -40,
                child: Image.asset('assets/images/logo_watermark.png', width: 260),
              ),
              SingleChildScrollView(
                padding: EdgeInsets.all(pad),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                child: _buildBody(_selected),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          sidebar,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  height: 52,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: AppColors.colBorder)),
                  ),
                  child: Row(
                    children: [
                      SkoutarLogo(height: 32),
                      const SizedBox(width: 10),
                      Icon(_iconFor(_selected), size: 19, color: AppColors.ink),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          _selected,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.left,
                          style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                              color: AppColors.ink),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      // Faint watermark behind the working area — matches
                      // the "behind the screen → watermarked version" rule.
                      Positioned(
                        right: -60,
                        bottom: -40,
                        child: Image.asset(
                          'assets/images/logo_watermark.png',
                          width: 320,
                        ),
                      ),
                      SingleChildScrollView(
                        padding: const EdgeInsets.all(12),
                        child: _buildBody(_selected),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
