/// OAuth 2.0 **Web application** client ID from Google Cloud Console.
/// On Android, this is usually required so `idToken` is returned for Supabase.
/// Leave null or empty to use platform defaults (iOS often works; Android may not).
const String? kGoogleWebClientId = null;

/// Add this exact URL in Supabase Dashboard → Authentication → URL Configuration
/// → Redirect URLs (and Site URL if needed for mobile).
///
/// Must match the Android intent-filter and iOS URL scheme in native config.
const String kSupabaseMobileRedirectUrl = 'com.example.heat_app://login-callback';
