/// Ligação ao mesmo projecto Supabase do Punho.
///
/// O operador não tem base de dados própria: vê a empresa do gestor, com as
/// permissões que `punho_membros` lhe der. Por isso o URL e a chave são os do
/// Punho, e entram por `--dart-define` como lá — nunca committados.
///
///     flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
class SupabaseConfig {
  const SupabaseConfig._();
  static const url = String.fromEnvironment('SUPABASE_URL');
  static const anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static bool get enabled => url.isNotEmpty && anonKey.isNotEmpty;
}
