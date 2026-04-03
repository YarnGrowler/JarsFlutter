/// Public Supabase client settings for the **Jars** hosted project.
/// The anon key is meant to ship in client apps (RLS still applies). Override via
/// `--dart-define` or `.env` for staging/other projects.
const String kDefaultSupabaseProjectRef = 'felftpxgwqlqhlgcwanz';

const String kDefaultSupabaseUrl =
    'https://felftpxgwqlqhlgcwanz.supabase.co';

/// Dashboard → Settings → API → anon public (same as `npx supabase projects api-keys`).
const String kDefaultSupabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZlbGZ0cHhnd3FscWhsZ2N3YW56Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzUwODY4NDAsImV4cCI6MjA5MDY2Mjg0MH0.90AMc-sbBIfDkUFDHkG6LqdNAH3lVPPJVIVSDm89fpI';
