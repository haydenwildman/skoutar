import 'package:supabase_flutter/supabase_flutter.dart';
// Re-exported so any file that imports this one also gets SupabaseClient,
// AuthException, FunctionException, etc. without a second import line.
export 'package:supabase_flutter/supabase_flutter.dart';

/// ══════════════════════════════════════════════════════════════
/// SUPABASE CONFIG
///
/// The anon/public key below is SAFE to ship in the app — it has no
/// power on its own; every table it touches is locked down by Row
/// Level Security policies (see supabase_schema.sql). Never put the
/// service_role/secret key here or anywhere else in this app — that
/// key bypasses RLS entirely and must only ever live on Supabase's
/// servers, never in this app.
/// ══════════════════════════════════════════════════════════════
const supabaseUrl = 'https://xuqrmsjiftjwlhoqekpi.supabase.co';
const supabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inh1cXJtc2ppZnRqd2xob3Fla3BpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODkwODcyMTQsImV4cCI6MjEwNDY2MzIxNH0.VGM3pUe2i22wP9pAl74Tvz5nDKw7MLdm7GEQFZ91xDM';

/// Call once at app startup, before runApp(). Sets up the singleton
/// accessed everywhere else via `Supabase.instance.client`.
Future<void> initSupabase() async {
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
}

/// Shorthand used throughout the services layer.
SupabaseClient get sb => Supabase.instance.client;
