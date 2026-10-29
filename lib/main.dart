import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/storage_service.dart';
import 'services/auth_service.dart';
import 'services/app_session.dart';
import 'services/supabase_config.dart';
import 'services/remembered_account_service.dart';
import 'subscriptions/subscription_service.dart';
import 'screens/subscribe_screen.dart';
import 'theme/app_theme.dart';
import 'screens/login_screen.dart';
import 'screens/home_shell.dart';
import 'screens/set_new_password_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Must be read BEFORE Supabase initializes (it may clean the URL): true when
  // the page was opened from a password-reset email link (web).
  final startedInRecovery = Uri.base.toString().contains('type=recovery');
  await initSupabase();
  // RevenueCat (iOS/Android only; a no-op elsewhere or without a key; never throws).
  await SubscriptionService.instance.init();

  final storage = StorageService();
  final auth = AuthService();
  final session = AppSession(auth: auth, storage: storage);

  // If a Supabase session was persisted from a previous visit (same
  // browser/device), pick it back up so the person doesn't have to log
  // in again every time.
  final restoredUser = startedInRecovery ? null : await auth.restoreSession();
  if (restoredUser != null) {
    try {
      await session.login(restoredUser);
      // This device is signed in as this account, so it is the one the login
      // screen should offer after the next sign-out.
      await RememberedAccountService.save(restoredUser.email);
    } catch (_) {
      // Data couldn't be loaded (e.g. the latest database update isn't
      // installed yet): fall back to the login screen instead of a blank app.
      await session.logout();
    }
  }

  runApp(
    ChangeNotifierProvider.value(
      value: session,
      child: SkoutarApp(startInRecovery: startedInRecovery),
    ),
  );
}

class SkoutarApp extends StatelessWidget {
  final bool startInRecovery;
  const SkoutarApp({super.key, this.startInRecovery = false});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SKOUTAR',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      // Teko is narrower/smaller-looking than Roboto at the same point size;
      // scale all text once, globally, instead of editing every TextStyle.
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: TextScaler.linear(mq.textScaler.scale(1.0) * AppFonts.textScale),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: _RootRouter(startInRecovery: startInRecovery),
    );
  }
}

/// Decides whether to show the Login screen or the authenticated Home
/// shell, based on whether AppSession already has a logged-in user
/// (set either by a fresh login, or by the session-restore in main()).
///
/// Also catches the password-reset email link: Supabase signs the person in
/// with a short-lived recovery session and fires `passwordRecovery`, which must
/// show "set a new password" instead of silently opening the app.
class _RootRouter extends StatefulWidget {
  final bool startInRecovery;
  const _RootRouter({required this.startInRecovery});

  @override
  State<_RootRouter> createState() => _RootRouterState();
}

class _RootRouterState extends State<_RootRouter> {
  late bool _recovering;
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    _recovering = widget.startInRecovery;
    _authSub = sb.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.passwordRecovery && mounted) {
        setState(() => _recovering = true);
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_recovering) {
      return SetNewPasswordScreen(onDone: () async {
        final session = context.read<AppSession>();
        await session.logout(); // clear any app state from the recovery session
        if (mounted) setState(() => _recovering = false);
      });
    }
    final session = context.watch<AppSession>();
    if (!session.isLoggedIn) return const LoginScreen();
    // Not paid yet (and no meaningful trial left, or a brand-new account):
    // offer the real purchase screen. "Not now" continues into the app.
    if (session.shouldOfferSubscription) return const SubscribeScreen(asGate: true);
    return const HomeShell();
  }
}
