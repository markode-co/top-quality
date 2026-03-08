const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

loadLocalEnvFiles([
  'supabase.storage.local.env',
  '.env.local',
  'supabase.functions.local.env',
]);

function loadLocalEnvFiles(fileNames) {
  for (const fileName of fileNames) {
    const fullPath = path.resolve(process.cwd(), fileName);
    if (!fs.existsSync(fullPath)) {
      continue;
    }

    const raw = fs.readFileSync(fullPath, 'utf8');
    for (const line of raw.split(/\r?\n/)) {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith('#')) {
        continue;
      }

      const separatorIndex = trimmed.indexOf('=');
      if (separatorIndex <= 0) {
        continue;
      }

      const key = trimmed.slice(0, separatorIndex).trim();
      let value = trimmed.slice(separatorIndex + 1).trim();
      if (
        (value.startsWith('"') && value.endsWith('"')) ||
        (value.startsWith("'") && value.endsWith("'"))
      ) {
        value = value.slice(1, -1);
      }

      if (!process.env[key]) {
        process.env[key] = value;
      }
    }
  }
}

function requireEnv(primaryName, fallbacks = []) {
  const names = [primaryName, ...fallbacks];
  for (const name of names) {
    const value = process.env[name];
    if (value && value.trim() !== '') {
      return value.trim();
    }
  }

  throw new Error(`Missing required environment variable: ${names.join(' or ')}`);
}

function run(command, args) {
  const result = spawnSync(command, args, {
    stdio: 'inherit',
    shell: true,
    env: process.env,
  });

  if (result.status !== 0) {
    process.exit(result.status ?? 1);
  }
}

function main() {
  const supabaseUrl = requireEnv('SUPABASE_URL', ['NEXT_PUBLIC_SUPABASE_URL']);
  const publishableKey = requireEnv('SUPABASE_PUBLISHABLE_KEY', [
    'NEXT_PUBLIC_SUPABASE_PUBLISHABLE_DEFAULT_KEY',
    'SUPABASE_ANON_KEY',
  ]);

  const flutterArgs = [
    'build',
    'web',
    '--release',
    '--base-href',
    '/',
    `--dart-define=SUPABASE_URL=${supabaseUrl}`,
    `--dart-define=SUPABASE_PUBLISHABLE_KEY=${publishableKey}`,
  ];

  if (process.env.SUPABASE_FUNCTIONS_URL) {
    flutterArgs.push(
      `--dart-define=SUPABASE_FUNCTIONS_URL=${process.env.SUPABASE_FUNCTIONS_URL}`,
    );
  }

  run('flutter', flutterArgs);
  run('node', ['./scripts/prepare-firebase-web.cjs']);
}

main();
