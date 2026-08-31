// Writes config.js from environment variables at deploy time.
//
// WHY THIS EXISTS
//
// config.js holds the Supabase URL, the Supabase anon key, and the MapTiler
// style URL. None of them is a secret -- all three ship to the browser -- but
// the MapTiler key still should not sit in Git, because a key in version
// history outlives any decision to rotate it.
//
// So config.js is gitignored. That creates a problem for a Git-connected
// Cloudflare Pages build: the file simply is not in the repo Pages clones, and
// the page would render its "expired" state for every visitor.
//
// This script closes that gap. Set the three values as environment variables in
// the Pages project settings, and run it as the build command:
//
//   Build command:   node apps/track_web/build-config.js
//   Deploy command:  npx wrangler deploy --config apps/track_web/wrangler.jsonc
//
// Locally, run the same script with the same three variables set. One
// mechanism for both, rather than a checked-in example file that drifts.

import { writeFileSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
// public/ is the only directory wrangler serves, so the generated config
// must land there rather than beside this script.
const OUT = join(HERE, 'public', 'config.js');

const { SUPABASE_URL, SUPABASE_ANON_KEY, MAPTILER_STYLE_URL } = process.env;

const missing = [
  ['SUPABASE_URL', SUPABASE_URL],
  ['SUPABASE_ANON_KEY', SUPABASE_ANON_KEY],
  ['MAPTILER_STYLE_URL', MAPTILER_STYLE_URL],
].filter(([, value]) => !value).map(([name]) => name);

if (missing.length > 0) {
  // Fail the build rather than emit a broken config. A deploy that silently
  // shows every visitor "this tracking link has expired" is far worse than a
  // build that stops and tells you which variable is missing.
  if (existsSync(OUT)) {
    console.log('build-config: env vars missing, but config.js already exists — leaving it alone.');
    process.exit(0);
  }
  console.error(
    `build-config: missing required environment variable(s): ${missing.join(', ')}\n` +
    'Set them in the Cloudflare Workers project settings, or copy config.example.js ' +
    'to public/config.js for local use.',
  );
  process.exit(1);
}

// A service_role key must never reach the browser. This is a cheap guard
// against someone pasting the wrong key into the Pages settings: Supabase
// service keys carry the "service_role" claim in their payload.
if (SUPABASE_ANON_KEY.includes('service_role')) {
  console.error(
    'build-config: SUPABASE_ANON_KEY looks like a SERVICE ROLE key. Refusing to ' +
    'write it into a public page. Use the anon/publishable key.',
  );
  process.exit(1);
}

writeFileSync(
  OUT,
  `// GENERATED at build time by build-config.js. Do not edit, do not commit.
window.ARANGCADA_CONFIG = ${JSON.stringify(
    {
      supabaseUrl: SUPABASE_URL,
      supabaseAnonKey: SUPABASE_ANON_KEY,
      mapStyleUrl: MAPTILER_STYLE_URL,
    },
    null,
    2,
  )};
`,
  'utf8',
);

console.log('build-config: wrote config.js');
