# Flutter Web on Supabase

This project is prepared to deploy a Flutter Web build into Supabase Storage and serve it through the `static-proxy` Edge Function so client-side routes resolve correctly.

## Files added for deployment

- `scripts/upload-supabase-web.cjs`: uploads `build/web` to a public Storage bucket and sets `Content-Type` plus `Cache-Control`.
- `supabase/functions/static-proxy/index.ts`: serves files from Storage and falls back to `index.html` on 404.
- `.github/workflows/deploy.yml`: builds Flutter Web on every push to `main` and uploads the build output to Supabase Storage.

## 1. Install local prerequisites

Use Node 20+, Flutter, and the Supabase CLI.

```powershell
npm install
flutter pub get
npx supabase login
```

If the local project is not linked yet, link it once:

```powershell
npx supabase link --project-ref YOUR_PROJECT_REF
```

## 2. Build the Flutter Web app

For a root URL deployment, keep the base href at `/`.

```powershell
flutter build web --release --base-href / `
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co `
  --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```

If you insist on using the raw function URL instead of a root-domain reverse proxy, change the base href to `/functions/v1/static-proxy/`.

## 3. Upload static files to Storage

Set the required environment variables in the current shell:

```powershell
$env:SUPABASE_URL='https://YOUR_PROJECT_REF.supabase.co'
$env:SUPABASE_SERVICE_ROLE_KEY='YOUR_SERVICE_ROLE_KEY'
$env:SUPABASE_BUCKET='flutter-web'
$env:SUPABASE_WEB_DIR='build/web'
```

Run the uploader:

```powershell
npm run supabase:web:upload
```

What the uploader does:

- Creates the bucket if it does not exist.
- Ensures the bucket is public.
- Preserves the full `build/web` folder structure.
- Uploads files with `upsert: true`.
- Sets `Content-Type` from the file extension.

Cache policy:

- `index.html`: `public, max-age=0, must-revalidate`
- Default `safe-flutter` mode: also revalidates stable Flutter runtime files such as `main.dart.js`, `flutter.js`, `flutter_bootstrap.js`, `flutter_service_worker.js`, `manifest.json`, `version.json`, and `canvaskit/*`
- Everything else: `public, max-age=31536000, immutable`

To force the stricter policy you originally requested for all non-HTML files, set:

```powershell
$env:SUPABASE_CACHE_MODE='strict'
npm run supabase:web:upload
```

That mode is less safe for stock Flutter builds because runtime asset URLs are stable across releases.

## 4. Deploy the SPA Edge Function

Serve locally:

```powershell
npx supabase functions serve static-proxy --no-verify-jwt
```

Deploy to Supabase:

```powershell
npx supabase functions deploy static-proxy --no-verify-jwt --use-api
```

Behavior:

- If the requested file exists in the public bucket, the function returns it as-is.
- If Storage returns `404`, the function returns `index.html` with `text/html; charset=utf-8`.
- `GET`, `HEAD`, and `OPTIONS` are supported.

The function reads:

- `SUPABASE_URL`
- `SUPABASE_BUCKET` (defaults to `flutter-web`)
- `STATIC_PROXY_ALLOWED_ORIGIN` (defaults to `*`)

## 5. Project URL and custom domain routing

Supabase deploys Edge Functions under `/functions/v1/<function-name>`. The `static-proxy` function handles SPA routing correctly once traffic reaches it, but serving the app at the hostname root requires a reverse proxy or CDN rule in front of Supabase.

Recommended setup:

1. Point your public hostname, such as `app.example.com`, at your edge/CDN layer.
2. Proxy all requests from `/` to `https://YOUR_PROJECT_REF.supabase.co/functions/v1/static-proxy`.
3. Preserve the request path and query string.
4. Keep the Flutter build base href at `/`.

If you use a Supabase custom hostname for the project, the project services move to that hostname, but Edge Functions still live under `/functions/v1/...`. Inference: you still need a root-path proxy rule if you want the app at `https://app.example.com/` instead of `https://app.example.com/functions/v1/static-proxy/`.

## 6. GitHub Actions setup

Create these repository secrets:

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `SUPABASE_BUCKET`
- `SUPABASE_PUBLISHABLE_KEY`

Why the extra publishable key secret exists:

- The upload job uses the service role key.
- The Flutter build itself needs the publishable client key because this app reads it from Dart defines at build time.

The workflow in `.github/workflows/deploy.yml` does this on every push to `main`:

1. Checks out the repo.
2. Installs Flutter and Node.
3. Runs `flutter pub get`.
4. Builds `build/web`.
5. Runs `npm ci`.
6. Uploads `build/web` to Supabase Storage with the Node uploader.

## Troubleshooting

### Deep links return 404

- Confirm the request is hitting `static-proxy`, not the raw Storage public URL.
- Confirm `index.html` exists in the target bucket.
- If you are using a root-domain reverse proxy, preserve the full incoming path when proxying.

### The app stays stale after a new deploy

- Use the default `safe-flutter` cache mode.
- If you previously uploaded with `strict`, re-upload with `safe-flutter`.
- Consider building with `flutter build web --release --pwa-strategy=none` if you do not need the generated Flutter service worker.

### CORS errors

- Prefer same-origin hosting through a reverse proxy so browser asset requests are not cross-origin.
- If you intentionally call the function cross-origin, set `STATIC_PROXY_ALLOWED_ORIGIN` to the expected origin.

### Bucket uploads fail

- The upload script requires the `service_role` key, not the publishable key.
- Do not expose `SUPABASE_SERVICE_ROLE_KEY` in Flutter code, browser code, or client-side `.env` files.
- GitHub Actions secrets are the correct place for the service role key in CI.

### Wrong file types from Storage

- Re-run the uploader so object metadata is replaced with the correct `Content-Type`.
- The script sets `Content-Type` on every upsert, so this is usually fixed by a clean re-upload.

## Optional fast-update tips

- For the simplest release behavior, disable the Flutter service worker unless you explicitly need offline support.
- Keep `index.html` revalidating on every request.
- If you later add hashed filenames to your Flutter asset pipeline, you can safely move more files to `immutable`.
