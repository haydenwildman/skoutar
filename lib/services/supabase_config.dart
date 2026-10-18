import 'package:supabase_flutter/supabase_flutter.dart';
// Re-exported so any file that imports this one also gets SupabaseClient,
// AuthException, FunctionException, etc. without a second import line.
export 'package:supabase_flutter/supabase_flutter.dart';

/// ══════════════════════════════════════════════════════════════
/// SUPABASE CONFIG
///
/// The project URL is the SKOUTAR project (xmzdwoqvnnwhbnntziuk), the one every
/// migration in this repo is run against.
///
/// The anon/publishable key is NOT stored in the source. It is public by design
/// (every table is locked down by Row Level Security), but keeping it out of the
/// repo means a key can be rotated without a code change and a key for the wrong
/// project can never be committed by accident. Supply it at build/run time:
///
///   flutter run -d windows --dart-define=SUPABASE_ANON_KEY=<anon/publishable key>
///   flutter build web      --dart-define=SUPABASE_ANON_KEY=<anon/publishable key>
///
/// Find it in the Supabase dashboard: Project Settings -> API (copy the anon /
/// publishable key of project xmzdwoqvnnwhbnntziuk). NEVER use the service_role /
/// secret key here: it bypasses RLS and must only live on Supabase's servers.
/// ══════════════════════════════════════════════════════════════
const supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://xmzdwoqvnnwhbnntziuk.supabase.co',
);
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

/// Call once at app startup, before runApp(). Sets up the singleton
/// accessed everywhere else via `Supabase.instance.client`.
Future<void> initSupabase() async {
  if (supabaseAnonKey.isEmpty) {
    throw StateError(
      'SUPABASE_ANON_KEY was not provided. Run with '
      '--dart-define=SUPABASE_ANON_KEY=<anon/publishable key of $supabaseUrl>.',
    );
  }
  assert(!supabaseAnonKey.startsWith('sb_secret_'), 'A secret key must never be used in the app.');
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
}

/// Shorthand used throughout the services layer.
SupabaseClient get sb => Supabase.instance.client;
