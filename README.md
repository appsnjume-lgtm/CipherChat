# CipherChat

CipherChat is a Flutter chat app backed by Supabase.

## Supabase configuration

Do not commit local Supabase credentials. Pass the public Supabase URL and anon
key with Dart defines when running or building the app:

```powershell
flutter run `
  --dart-define=SUPABASE_URL=https://your-project.supabase.co `
  --dart-define=SUPABASE_ANON_KEY=your-anon-key
```

Use the same flags for release builds:

```powershell
flutter build apk `
  --dart-define=SUPABASE_URL=https://your-project.supabase.co `
  --dart-define=SUPABASE_ANON_KEY=your-anon-key
```
