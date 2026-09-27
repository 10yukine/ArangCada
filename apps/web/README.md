# ArangCada public website

Static HTML, CSS and JavaScript for the public information and legal pages.
`wrangler.jsonc` configures the `arangcada-web` Worker and its custom domains.
Only `public/` is served.

| Path | Page |
| --- | --- |
| `/ph` | Main website |
| `/terms` | Terms of Service |
| `/policy` | Privacy Policy |

## Local preview

From the repository root:

```sh
python -m http.server 8000 --directory apps/web/public
```

Open `/ph.html` for the local preview. Cloudflare handles extensionless paths
and the root redirect in the deployed site.

## Legal content

Edit the Markdown in `legal/`, then regenerate the public pages from the
repository root using Python with the `markdown` package installed:

```sh
python scripts/render_legal_html.py
```

Review the generated changes before publishing. Preserve any draft status and
review notices in the source documents.

## Deployment

With the intended Cloudflare account configured:

```sh
npx wrangler deploy --config apps/web/wrangler.jsonc
```

Recipients must configure their own hosting account and domains. Keep deployment
tokens out of source and public assets.
