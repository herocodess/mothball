# usemothball.dev

The landing page, in English, Arabic, Spanish, French, Japanese, Portuguese
(Brazil) and Chinese (Simplified). Plain HTML, CSS and JavaScript: no
framework, no dependencies, and Cloudflare serves the files as they are.

```
site/
  i18n/page.html the page, with {{key}} where text goes
  i18n/en.json   the English text; ar.json, es.json, ... the translations
  index.html     the English page, written by scripts/build-site.py
  ar/, es/, ...  each language's page, written the same way
  style.css      colours, layout and motion
  main.js        theme switcher, floating nav, scroll reveals, downloads
  og.png         share image (1200 x 630) shown when the link is pasted
  favicon.svg    follows the system's light or dark mode
  img/           app screenshots, light and dark
  fonts/         Instrument Sans and IBM Plex Mono (SIL Open Font License)
```

## Languages

Edit `i18n/page.html` or the `i18n/*.json` text, never the written pages, then
run the script and commit everything it changed:

```
python3 scripts/build-site.py
```

CI runs it with `--check` and fails if a written page is out of date.

- Each language lives at its own address (`/ar/`, `/fr/`, ...), with
  `hreflang` links so search engines show the right one. English is at `/`.
- The language menu sits next to the theme switch. A visitor whose browser
  prefers another language the site has gets a small note offering it, in
  that language; there is never a redirect. Picking a language, or closing
  the note, is remembered in the browser.
- Arabic pages are right to left. Commands, file names and the terminal
  example stay left to right; sizes in Arabic text are wrapped in direction
  marks so "71.0 GB" stays whole.
- A new key must be added to every language's file; the script refuses to
  write pages while one is missing.

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

The canonical URL and share image address are `https://usemothball.dev/`. If
the domain changes, update the `canonical`, `og:url` and `og:image` lines in
`index.html`.
