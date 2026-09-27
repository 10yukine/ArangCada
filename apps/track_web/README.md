# ArangCada ride tracking

A static page for a shared ride link at `/t/<token>`. It uses HTML, CSS and
JavaScript, with no frontend framework or bundler. Only `public/` is deployed.

## Configuration

Set these environment variables before generating the ignored browser config:

| Variable | Value |
| --- | --- |
| `SUPABASE_URL` | Recipient's Supabase project URL |
| `SUPABASE_ANON_KEY` | Client publishable/anon key |
| `MAPTILER_STYLE_URL` | Map style URL with a restricted client key |

From the repository root:

```sh
node apps/track_web/build-config.js
python -m http.server 8000 --directory apps/track_web/public
```

The local Python server does not provide the deployed SPA fallback. Cloudflare
serves `/t/<token>` through the routing configured in `wrangler.jsonc`.

Browser configuration is visible to visitors. Never use a service-role key;
restrict provider keys and keep the real `config.js` out of Git.

## Implementation

- `public/render.js` parses tokens and prepares display values.
- `public/track.js` fetches updates and renders the map and trip status.
- `public/style.css` controls presentation.
- `build-config.js` generates `public/config.js` from the environment.

The backend validates shared links and limits the returned data. Treat links as
bearer credentials. Preserve expiry handling, minimal payloads, `no-referrer`
and `noindex` protections when changing this page.

## Checks and deployment

Run `npm test` from this directory. With the intended Cloudflare account
configured, deploy from the repository root:

```sh
npx wrangler deploy --config apps/track_web/wrangler.jsonc
```

Configure the recipient's domains and provider restrictions before acceptance.
See [the security policy](../../SECURITY.md) for access and privacy requirements.
