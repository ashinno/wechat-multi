# WeChat Multi — showcase site

A single-page, dependency-free static site that showcases the app. No build
step: it's plain HTML, CSS, and a few lines of JS.

```
site/
├── index.html      # the page
├── styles.css      # design tokens mirror the app's Brand enum + slot palette
├── app.js          # copy-to-clipboard buttons (progressive enhancement)
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

`.github/workflows/pages.yml` publishes this folder to GitHub Pages on every
push to `main` that touches `site/`. One-time setup:

> **Settings → Pages → Build and deployment → Source: GitHub Actions**

Then the site goes live at `https://ashinno.github.io/wechat-multi/`.
