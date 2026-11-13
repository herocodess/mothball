// Mothball landing page: theme switcher, floating nav, scroll reveals and
// downloads. No dependencies.
(function () {
  'use strict';

  var root = document.documentElement;
  var REPO = 'herocodess/mothball';

  // ---------- This page's language. The text comes from #mb-words, written
  // into each page by scripts/build-site.py; English is the fallback.
  var WORDS = {};
  try { WORDS = JSON.parse(document.getElementById('mb-words').textContent); } catch (e) {}
  function t(key, vars) {
    var s = WORDS[key] || key;
    if (vars) Object.keys(vars).forEach(function (k) { s = s.split('{' + k + '}').join(vars[k]); });
    return s;
  }
  var LANG = root.lang || 'en';
  var RELEASES = 'https://github.com/' + REPO + '/releases';

  // ---------- Theme: System (default), Light or Dark, remembered per browser.
  var media = window.matchMedia ? window.matchMedia('(prefers-color-scheme: dark)') : null;
  var themeButtons = document.querySelectorAll('[data-theme-pick]');
  var NAMES = { system: t('themeSystem'), light: t('themeLight'), dark: t('themeDark') };
  var LABELS_THEME = { system: t('themeSystemLabel'), light: t('themeLightLabel'), dark: t('themeDarkLabel') };
  var narrow = window.matchMedia ? window.matchMedia('(max-width: 520px)') : { matches: false };

  function applyTheme(pref) {
    var dark = pref === 'dark' || (pref === 'system' && media && media.matches);
    root.dataset.theme = dark ? 'dark' : 'light';
    root.dataset.pref = pref;
    themeButtons.forEach(function (b) {
      b.setAttribute('aria-pressed', b.dataset.themePick === pref ? 'true' : 'false');
      if (narrow.matches) b.setAttribute('aria-label', t('themeTap', { name: NAMES[b.dataset.themePick] }));
      else b.setAttribute('aria-label', LABELS_THEME[b.dataset.themePick]);
    });
  }
  var ORDER = ['system', 'light', 'dark'];
  themeButtons.forEach(function (b) {
    b.addEventListener('click', function () {
      var pref = b.dataset.themePick;
      // On phones only the current theme's button shows; tapping it moves on.
      if (narrow.matches && pref === root.dataset.pref) pref = ORDER[(ORDER.indexOf(pref) + 1) % ORDER.length];
      try { localStorage.setItem('mothball-theme', pref); } catch (e) {}
      applyTheme(pref);
    });
  });
  if (media) {
    var onScheme = function () { if (root.dataset.pref === 'system') applyTheme('system'); };
    if (media.addEventListener) media.addEventListener('change', onScheme);
    if (narrow.addEventListener) narrow.addEventListener('change', function () { applyTheme(root.dataset.pref || 'system'); });
    else if (media.addListener) media.addListener(onScheme);
  }
  applyTheme(root.dataset.pref || 'system');

  // ---------- Nav: tucks into a floating pill once you scroll.
  var hdr = document.getElementById('hdr');
  var pill = false, ticking = false;
  function onScroll() {
    if (ticking) return;
    ticking = true;
    requestAnimationFrame(function () {
      ticking = false;
      var y = window.scrollY || 0;
      var next = pill ? y > 12 : y > 48;
      if (next !== pill) { pill = next; hdr.classList.toggle('pill', pill); }
    });
  }
  window.addEventListener('scroll', onScroll, { passive: true });
  onScroll();

  // ---------- Scroll reveals.
  var reveals = document.querySelectorAll('.reveal');
  if ('IntersectionObserver' in window) {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (e.isIntersecting) { e.target.classList.add('in'); io.unobserve(e.target); }
      });
    }, { rootMargin: '0px 0px -12% 0px', threshold: 0.08 });
    reveals.forEach(function (el) { io.observe(el); });
  } else {
    reveals.forEach(function (el) { el.classList.add('in'); });
  }

  // ---------- Downloads.
  // The list fills from the latest GitHub release, so a new version shows up
  // here without touching the site. FALLBACK is used if GitHub is unreachable.
  var FALLBACK = {
    version: '0.1.7',
    assets: {
      'Mothball-0.1.7.dmg': 28100448,
      'Mothball-0.1.7-windows-x64-setup.exe': 13324540,
      'Mothball-0.1.7-windows-arm64-setup.exe': 12455172,
      'Mothball-0.1.7-linux-x86_64.AppImage': 13806072,
      'Mothball-0.1.7-linux-aarch64.AppImage': 13031944
    }
  };

  var CATALOG = {
    mac: [
      { key: 'mac', match: /^Mothball-[\d.]+\.dmg$/, title: t('macTitle'), fits: t('macFits') }
    ],
    win: [
      { key: 'x64', match: /windows-x64-setup\.exe$/, title: t('winX64Title'), fits: t('winX64Fits') },
      { key: 'arm64', match: /windows-arm64-setup\.exe$/, title: t('winArmTitle'), fits: t('winArmFits') }
    ],
    linux: [
      { key: 'x64', match: /linux-x86_64\.AppImage$/, title: t('linuxX64Title'), fits: t('linuxX64Fits') },
      { key: 'arm64', match: /linux-aarch64\.AppImage$/, title: t('linuxArmTitle'), fits: t('linuxArmFits') }
    ]
  };
  var LABELS = { mac: 'macOS', win: 'Windows', linux: 'Linux' };

  function installFor(os, v, arm) {
    if (os === 'mac') return { title: t('orHomebrew'), cmd: '$ brew tap herocodess/tap\n$ brew trust herocodess/tap\n$ brew install --cask mothball', note: t('appIncludesCli') };
    if (os === 'win') return { title: t('orScoop'), cmd: '> scoop bucket add herocodess https://github.com/herocodess/scoop-bucket\n> scoop install mothball', note: t('scoopNote') };
    var deb = arm ? 'arm64' : 'amd64', rpm = arm ? 'aarch64' : 'x86_64';
    return {
      title: t('preferPackage'),
      cmd: '$ sudo apt install ./mothball_' + v + '-1_' + deb + '.deb     # Ubuntu, Debian\n$ sudo dnf install ./mothball-' + v + '-1.' + rpm + '.rpm    # Fedora',
      note: t('packageNote')
    };
  }

  var state = { os: null, arch: null, picked: null, release: null };

  var ua = navigator.userAgent || '';
  state.os = /Windows/i.test(ua) ? 'win'
    : /Mac OS X|Macintosh/i.test(ua) ? 'mac'
    : (/Linux|X11/i.test(ua) && !/Android/i.test(ua)) ? 'linux' : null;
  state.arch = /arm64|aarch64|ARM;/i.test(ua) ? 'arm' : null;
  try {
    if (navigator.userAgentData && navigator.userAgentData.getHighEntropyValues) {
      navigator.userAgentData.getHighEntropyValues(['architecture']).then(function (v) {
        if (v && v.architecture) { state.arch = v.architecture === 'arm' ? 'arm' : 'x86'; render(); }
      }).catch(function () {});
    }
  } catch (e) {}

  // Sizes in this page's language: "12.4 MB", "12,4 Mo". Arabic keeps 0-9.
  var NUM = null;
  try { NUM = new Intl.NumberFormat(LANG === 'ar' ? 'en' : LANG, { minimumFractionDigits: 1, maximumFractionDigits: 1 }); } catch (e) {}
  function mb(bytes) {
    var n = bytes / 1048576;
    return (NUM ? NUM.format(n) : n.toFixed(1)) + '\u00a0' + t('unitMB');
  }
  function el(tag, cls, text) { var n = document.createElement(tag); if (cls) n.className = cls; if (text != null) n.textContent = text; return n; }

  function releaseAssets() {
    if (state.release) return state.release;
    var base = RELEASES + '/download/v' + FALLBACK.version + '/';
    return {
      version: FALLBACK.version,
      assets: Object.keys(FALLBACK.assets).map(function (name) {
        return { name: name, size: FALLBACK.assets[name], url: base + name };
      })
    };
  }

  var filesEl = document.getElementById('dl-files');
  var tabButtons = document.querySelectorAll('[data-os]');
  var firstRender = true;

  function render() {
    var os = state.picked || state.os || 'mac';
    var arm = state.arch === 'arm';
    var rel = releaseAssets();

    tabButtons.forEach(function (b) { b.setAttribute('aria-pressed', b.dataset.os === os ? 'true' : 'false'); });

    var detected = document.getElementById('dl-detected');
    var picked = state.os === 'mac' ? LABELS.mac
      : arm ? t('osOnArm', { os: LABELS[state.os] })
      : state.arch === 'x86' ? LABELS[state.os] + ' x64' : LABELS[state.os];
    detected.textContent = state.os ? t('pickedFor', { os: picked }) : t('dlDefault');

    filesEl.textContent = '';
    CATALOG[os].forEach(function (item, i) {
      var asset = rel.assets.filter(function (a) { return item.match.test(a.name); })[0];
      if (!asset) return;
      var mine = state.os === os && (os === 'mac' || (item.key === 'arm64') === arm);
      var a = el('a', 'file' + (mine ? ' mine' : ''));
      a.href = asset.url;
      a.dataset.track = 'download/' + os + '/' + item.key + '/' + rel.version;
      if (!firstRender) a.style.setProperty('--d', (i * 0.06) + 's');
      else a.style.animation = 'none';

      var top = el('span', 'file-top');
      top.appendChild(el('span', 'file-title', item.title));
      if (mine) top.appendChild(el('span', 'badge', t('yourSystem')));
      a.appendChild(top);
      a.appendChild(el('span', 'quiet', item.fits));

      var bottom = el('span', 'file-bottom');
      var fname = el('span', 'file-name mono', asset.name);
      fname.dir = 'ltr';
      bottom.appendChild(fname);
      var size = el('span', 'file-size');
      size.innerHTML = '<svg aria-hidden="true" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 4v12"/><path d="M6 11l6 6 6-6"/><path d="M5 20h14"/></svg>';
      size.appendChild(document.createTextNode(mb(asset.size)));
      bottom.appendChild(size);
      a.appendChild(bottom);
      filesEl.appendChild(a);
    });
    firstRender = false;

    var inst = installFor(os, rel.version, arm && state.os === 'linux');
    document.getElementById('dl-install-title').textContent = inst.title;
    document.getElementById('dl-install').textContent = inst.cmd;
    document.getElementById('dl-note').textContent = inst.note;

    document.querySelectorAll('[data-version]').forEach(function (n) { n.textContent = 'v' + rel.version; });
  }

  tabButtons.forEach(function (b) {
    b.addEventListener('click', function () { state.picked = b.dataset.os; render(); });
  });
  render();

  // Latest release from GitHub. Cached for an hour so repeat visits don't use
  // up the anonymous API limit.
  (function loadRelease() {
    var KEY = 'mothball-release', now = Date.now();
    try {
      var cached = JSON.parse(localStorage.getItem(KEY) || 'null');
      if (cached && now - cached.at < 3600000) { state.release = cached.data; render(); return; }
    } catch (e) {}
    if (!window.fetch) return;
    fetch('https://api.github.com/repos/' + REPO + '/releases/latest', { headers: { Accept: 'application/vnd.github+json' } })
      .then(function (r) { if (!r.ok) throw new Error(r.status); return r.json(); })
      .then(function (j) {
        var data = {
          version: String(j.tag_name || '').replace(/^v/, ''),
          assets: (j.assets || []).map(function (a) { return { name: a.name, size: a.size, url: a.browser_download_url }; })
        };
        if (!data.version || !data.assets.length) return;
        state.release = data;
        try { localStorage.setItem(KEY, JSON.stringify({ at: now, data: data })); } catch (e) {}
        render();
      })
      .catch(function () {});
  })();

  // ---------- Languages: a menu next to the theme switch, and a quiet note
  // when the browser prefers another language this site has. Never a
  // redirect: picking a language, or closing the note, is remembered.
  (function languages() {
    var LANG_KEY = 'mothball-lang';
    var info = null;
    try { info = JSON.parse(document.getElementById('mb-langs').textContent); } catch (e) { return; }
    var menu = document.querySelector('.langs');
    function remember(code) { try { localStorage.setItem(LANG_KEY, code); } catch (e) {} }

    if (menu) {
      menu.querySelectorAll('a[data-lang]').forEach(function (a) {
        a.addEventListener('click', function () { remember(a.dataset.lang); });
      });
      document.addEventListener('click', function (e) { if (menu.open && !menu.contains(e.target)) menu.open = false; });
      document.addEventListener('keydown', function (e) { if (e.key === 'Escape' && menu.open) { menu.open = false; menu.querySelector('summary').focus(); } });
    }

    var chosen = null;
    try { chosen = localStorage.getItem(LANG_KEY); } catch (e) {}
    if (chosen) return;
    var wanted = null;
    var prefs = navigator.languages && navigator.languages.length ? navigator.languages : [navigator.language || ''];
    for (var i = 0; i < prefs.length && !wanted; i++) {
      var code = String(prefs[i]).toLowerCase().split(/[-_]/)[0];
      if (info.languages[code]) wanted = code;
    }
    if (!wanted || wanted === info.current) return;

    var l = info.languages[wanted];
    var note = document.createElement('div');
    note.className = 'lang-note';
    note.lang = wanted;
    note.dir = wanted === 'ar' ? 'rtl' : 'ltr';
    note.setAttribute('role', 'region');
    note.setAttribute('aria-label', l.name);
    var text = document.createElement('span');
    text.textContent = l.suggest + ' ';
    var go = document.createElement('a');
    go.href = l.path;
    go.textContent = l.view;
    go.addEventListener('click', function () { remember(wanted); });
    var close = document.createElement('button');
    close.type = 'button';
    close.setAttribute('aria-label', l.close);
    close.title = l.close;
    close.innerHTML = '<svg aria-hidden="true" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><path d="M6 6l12 12M18 6L6 18"/></svg>';
    close.addEventListener('click', function () { remember(info.current); note.remove(); });
    note.appendChild(text);
    note.appendChild(go);
    note.appendChild(close);
    document.body.appendChild(note);
  })();

  // ---------- Download counting (private, no cookies).
  // Each click is sent to GoatCounter as an event such as
  // "download/win/arm64/0.1.3". Only the site owner can see the dashboard.
  document.addEventListener('click', function (e) {
    var a = e.target.closest && e.target.closest('a[data-track]');
    if (!a) return;
    try {
      if (window.goatcounter && window.goatcounter.count) {
        window.goatcounter.count({ path: a.dataset.track, title: a.dataset.track, event: true });
      }
    } catch (err) {}
  });
})();
