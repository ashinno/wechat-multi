# WeChat Multi — showcase site

A single-page, dependency-free static site that showcases the app. No build
step: it's plain HTML, CSS, and a few lines of JS.

```
site/
├── index.html      # the page
├── styles.css      # design tokens mirror the app's Brand enum + slot palette
├── app.js          # copy-to-clipboard buttons (progressive enhancement)
├── vercel.json     # static config for Vercel (clean URLs, cache + security headers)
└── assets/
    ├── icon.png    # app icon (copied from docs/icon.png)
    └── favicon.svg # jade "stack" mark
```

## Preview locally

```bash
cd site
python3 -m http.server 8000
# open http://localhost:8000
```

Or just open `site/index.html` directly in a browser.

## Deploy

The site is a plain static folder, so any static host works. Two are wired up:

### Vercel (recommended)

[![Deploy with Vercel](https://vercel.com/button)](https://vercel.com/new/clone?repository-url=https://github.com/ashinno/wechat-multi&root-directory=site&project-name=wechat-multi&repository-name=wechat-multi)

The button above pre-fills the **Root Directory** as `site`, so Vercel serves
this folder directly — no build step. `vercel.json` adds clean URLs plus cache
and security headers.

From the CLI instead:

```bash
cd site
vercel          # preview deploy
vercel --prod   # production deploy
```

> If you import the repo manually in the Vercel dashboard, set **Root
> Directory → `site`** and framework preset **Other** (no build command).

### GitHub Pages

`.github/workflows/pages.yml` publishes this folder on every push to `main`
that touches `site/`. One-time setup:

> **Settings → Pages → Build and deployment → Source: GitHub Actions**

Then the site goes live at `https://ashinno.github.io/wechat-multi/`.
