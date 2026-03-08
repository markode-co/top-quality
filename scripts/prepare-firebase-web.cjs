const fs = require('node:fs/promises');
const path = require('node:path');

const buildDir = path.resolve(process.cwd(), 'build/web');

const readme = `# Firebase Hosting Deploy

This folder is ready to deploy to Firebase Hosting.

## Build

\`\`\`bash
npm run firebase:web:build
\`\`\`

## Local preview

\`\`\`bash
npm run firebase:serve
\`\`\`

## Deploy

\`\`\`bash
npm run firebase:deploy
\`\`\`

## Required environment variables for build

- SUPABASE_URL
- SUPABASE_PUBLISHABLE_KEY

SPA rewrites and cache headers are configured in the repository root \`firebase.json\`.
`;

async function ensureBuildDir() {
  const stat = await fs.stat(buildDir).catch(() => null);
  if (!stat || !stat.isDirectory()) {
    throw new Error(`Missing build directory: ${buildDir}`);
  }
}

async function removeIfExists(fileName) {
  await fs.rm(path.join(buildDir, fileName), {
    force: true,
    recursive: false,
  }).catch(() => {});
}

async function main() {
  await ensureBuildDir();

  await removeIfExists('_redirects');
  await removeIfExists('_headers');
  await removeIfExists('README-NETLIFY.md');
  await removeIfExists('README-RENDER.md');

  await fs.writeFile(path.join(buildDir, 'README-FIREBASE.md'), readme, 'utf8');

  console.log('Prepared build/web for Firebase Hosting.');
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
