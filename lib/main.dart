import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/storage_service.dart';
import 'services/auth_service.dart';
import 'services/app_session.dart';
import 'services/supabase_config.dart';
import 'theme/app_theme.dart';
import 'screens/login_screen.dart';
import 'screens/home_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initSupabase();

  final storage = StorageService();
  final auth = AuthService();
  final session = AppSession(auth: auth, storage: storage);

  // If a Supabase session was persisted from a previous visit (same
  // browser/device), pick it back up so the person doesn't have to log
  // in again every time.
  final restoredUser = await auth.restoreSession();
  if (restoredUser != null) {
    await session.login(restoredUser);
  }

  runApp(
    ChangeNotifierProvider.value(
      value: session,
      child: const SkoutarApp(),
    ),
  );
}

class SkoutarApp extends StatelessWidget {
  const SkoutarApp({super.key});

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
      home: const _RootRouter(),
    );
  }
}

/// Decides whether to show the Login screen or the authenticated Home
/// shell, based on whether AppSession already has a logged-in user
/// (set either by a fresh login, or by the session-restore in main()).
class _RootRouter extends StatelessWidget {
  const _RootRouter();

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AppSession>();
    return session.isLoggedIn ? const HomeShell() : const LoginScreen();
  }
}
