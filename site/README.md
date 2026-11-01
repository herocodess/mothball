# mothball.dev

The landing page. Plain HTML, CSS and JavaScript: no framework, no build step,
no dependencies.

```
site/
  index.html     the page
  style.css      colours, layout and motion
  main.js        theme switcher, floating nav, scroll reveals, downloads
  og.png         share image (1200 x 630) shown when the link is pasted
  favicon.svg    follows the system's light or dark mode
  img/           app screenshots, light and dark
  fonts/         Instrument Sans and IBM Plex Mono (SIL Open Font License)
```

## Run it locally

```
cd site
python3 -m http.server 8000
```

Then open http://localhost:8000.

## Downloads

The download section reads the latest GitHub release when the page loads, so
a new release shows up on the site by itself, with its version and file
sizes. If GitHub can't be reached, the page falls back to the version in
`FALLBACK` near the top of the downloads code in `main.js`; bump it now and
then.

## Download counts

Two sources, both private to the maintainer:

- **Clicks on this site's download buttons** go to
  [GoatCounter](https://www.goatcounter.com), which is open source, uses no
  cookies and keeps no personal data. Each click is an event named like
  `download/win/arm64/0.1.3` (OS, chip, version). The dashboard is private
  to the account owner. The site code is `mothball`, set in `index.html`.
- **Every download from anywhere** (the site, Homebrew, Scoop, the in-app
  updater, direct links) is counted by GitHub per file:

  ```
  scripts/download-stats.sh            # all releases
  scripts/download-stats.sh v0.1.3     # one release
  ```

## Domain

The canonical URL and share image address are `https://mothball.dev/`. If
the domain changes, update the `canonical`, `og:url` and `og:image` lines in
`index.html`.
