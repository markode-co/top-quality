# Flutter Web on Firebase Hosting

This project is configured to deploy to Firebase Hosting as a single-page application.

## Required build variables

- `SUPABASE_URL`
- `SUPABASE_PUBLISHABLE_KEY`

No additional frontend key is required.

## Local build

```powershell
npm run firebase:web:build
```

## Local preview

```powershell
npm run firebase:serve
```

## Deploy

1. Install Firebase CLI if needed:

```powershell
npm install -g firebase-tools
```

2. Log in and choose your Firebase project:

```powershell
firebase login
firebase use --add
```

3. Deploy hosting:

```powershell
npm run firebase:deploy
```

The `firebase.json` file already contains:

- SPA rewrite to `/index.html`
- Cache headers for HTML and runtime files
- Long-term immutable caching for assets, icons, and CanvasKit files
