const fs = require('node:fs/promises');
const fsSync = require('node:fs');
const path = require('node:path');
const mime = require('mime');
const { createClient } = require('@supabase/supabase-js');

loadLocalEnvFiles([
  'supabase.storage.local.env',
  '.env.local',
  'supabase.functions.local.env',
]);

const ROOT_DIR = process.cwd();
const ARG_BUILD_DIR = process.argv[2];
const BUILD_DIR = path.resolve(
  ROOT_DIR,
  ARG_BUILD_DIR || process.env.SUPABASE_WEB_DIR || 'build/web',
);
const BUCKET = process.env.SUPABASE_BUCKET || 'flutter-web';
const SUPABASE_URL = process.env.SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const CACHE_MODE = process.env.SUPABASE_CACHE_MODE || 'safe-flutter';
const CONCURRENCY = Number.parseInt(process.env.SUPABASE_UPLOAD_CONCURRENCY || '6', 10);
const DRY_RUN = process.argv.includes('--dry-run');

const SAFE_REVALIDATE_PATHS = new Set([
  '.last_build_id',
  'flutter.js',
  'flutter_bootstrap.js',
  'flutter_service_worker.js',
  'index.html',
  'main.dart.js',
  'manifest.json',
  'version.json',
  'assets/AssetManifest.bin',
  'assets/AssetManifest.bin.json',
  'assets/FontManifest.json',
  'assets/NOTICES',
]);

function loadLocalEnvFiles(fileNames) {
  for (const fileName of fileNames) {
    const fullPath = path.resolve(process.cwd(), fileName);
    if (!fsSync.existsSync(fullPath)) {
      continue;
    }

    const raw = fsSync.readFileSync(fullPath, 'utf8');
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

function requireEnv(name, value) {
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
}

function normalizePath(relativePath) {
  return relativePath.split(path.sep).join('/');
}

function inferContentType(relativePath) {
  const contentType = mime.getType(relativePath);
  if (contentType) {
    return contentType;
  }

  if (relativePath.endsWith('.wasm')) {
    return 'application/wasm';
  }
  if (relativePath.endsWith('.frag')) {
    return 'text/plain; charset=utf-8';
  }
  if (relativePath.endsWith('.symbols')) {
    return 'text/plain; charset=utf-8';
  }
  if (relativePath.endsWith('.bin')) {
    return 'application/octet-stream';
  }

  return 'application/octet-stream';
}

function inferCacheControl(relativePath) {
  if (relativePath === 'index.html') {
    return 'public, max-age=0, must-revalidate';
  }

  if (CACHE_MODE === 'strict') {
    return 'public, max-age=31536000, immutable';
  }

  if (
    SAFE_REVALIDATE_PATHS.has(relativePath) ||
    relativePath.startsWith('canvaskit/')
  ) {
    return 'public, max-age=0, must-revalidate';
  }

  return 'public, max-age=31536000, immutable';
}

async function walk(dir) {
  const entries = await fs.readdir(dir, { withFileTypes: true });
  const files = await Promise.all(entries.map(async (entry) => {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      return walk(fullPath);
    }
    if (entry.isFile()) {
      return [fullPath];
    }
    return [];
  }));

  return files.flat();
}

async function ensureBuildDirExists() {
  const stat = await fs.stat(BUILD_DIR).catch(() => null);
  if (!stat || !stat.isDirectory()) {
    throw new Error(`Flutter web build directory does not exist: ${BUILD_DIR}`);
  }
}

function createSupabaseAdminClient() {
  requireEnv('SUPABASE_URL', SUPABASE_URL);
  requireEnv('SUPABASE_SERVICE_ROLE_KEY', SERVICE_ROLE_KEY);

  return createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
    global: {
      headers: {
        'X-Client-Info': 'flowstock-web-deploy',
      },
    },
  });
}

async function ensureBucket(client) {
  const bucketResponse = await client.storage.getBucket(BUCKET);
  if (bucketResponse.error) {
    const message = String(bucketResponse.error.message || '');
    const isMissingBucket =
      bucketResponse.error.statusCode === '404' ||
      /not found/i.test(message);

    if (!isMissingBucket) {
      throw new Error(`Unable to read bucket "${BUCKET}": ${message}`);
    }

    console.log(`Creating public bucket "${BUCKET}"...`);
    const createResponse = await client.storage.createBucket(BUCKET, {
      public: true,
    });
    if (createResponse.error) {
      throw new Error(
        `Unable to create bucket "${BUCKET}": ${createResponse.error.message}`,
      );
    }
    return;
  }

  if (!bucketResponse.data.public) {
    console.log(`Updating bucket "${BUCKET}" to public...`);
    const updateResponse = await client.storage.updateBucket(BUCKET, {
      public: true,
    });
    if (updateResponse.error) {
      throw new Error(
        `Unable to update bucket "${BUCKET}": ${updateResponse.error.message}`,
      );
    }
  }
}

async function uploadFile(client, filePath) {
  const relativePath = normalizePath(path.relative(BUILD_DIR, filePath));
  const content = await fs.readFile(filePath);
  const contentType = inferContentType(relativePath);
  const cacheControl = inferCacheControl(relativePath);

  if (DRY_RUN) {
    console.log(`[dry-run] ${relativePath} (${contentType}) ${cacheControl}`);
    return;
  }

  const response = await client.storage.from(BUCKET).upload(relativePath, content, {
    upsert: true,
    contentType,
    cacheControl,
  });

  if (response.error) {
    throw new Error(`Upload failed for "${relativePath}": ${response.error.message}`);
  }

  console.log(`Uploaded ${relativePath} (${contentType}) ${cacheControl}`);
}

async function runPool(items, worker, size) {
  const queue = [...items];
  const failures = [];

  const runners = Array.from({ length: Math.max(1, size) }, async () => {
    while (queue.length > 0) {
      const item = queue.shift();
      if (!item) {
        continue;
      }

      try {
        await worker(item);
      } catch (error) {
        failures.push(error);
      }
    }
  });

  await Promise.all(runners);

  if (failures.length > 0) {
    throw new AggregateError(failures, 'One or more uploads failed.');
  }
}

async function main() {
  await ensureBuildDirExists();

  const files = await walk(BUILD_DIR);
  if (files.length === 0) {
    throw new Error(`No files found in ${BUILD_DIR}`);
  }

  console.log(
    `${DRY_RUN ? 'Inspecting' : 'Uploading'} ${files.length} files from ${BUILD_DIR} to bucket "${BUCKET}" using cache mode "${CACHE_MODE}".`,
  );

  if (DRY_RUN) {
    await runPool(files, (filePath) => uploadFile(null, filePath), CONCURRENCY);
    return;
  }

  const client = createSupabaseAdminClient();
  await ensureBucket(client);
  await runPool(files, (filePath) => uploadFile(client, filePath), CONCURRENCY);

  const publicUrl = `${SUPABASE_URL.replace(/\/$/, '')}/storage/v1/object/public/${BUCKET}/index.html`;
  console.log(`Storage entrypoint: ${publicUrl}`);
  if (CACHE_MODE !== 'strict') {
    console.log(
      'Cache mode "safe-flutter" revalidates stable Flutter runtime files to avoid stale deploys.',
    );
  }
}

main().catch((error) => {
  console.error(error instanceof AggregateError ? error.errors : error);
  process.exit(1);
});
