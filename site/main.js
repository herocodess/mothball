// Mothball landing page: theme switcher, floating nav, scroll reveals and
// downloads. No dependencies.
(function () {
  'use strict';

  var root = document.documentElement;
  var REPO = 'herocodess/mothball';
  var RELEASES = 'https://github.com/' + REPO + '/releases';

  // ---------- Theme: System (default), Light or Dark, remembered per browser.
  var media = window.matchMedia ? window.matchMedia('(prefers-color-scheme: dark)') : null;
  var themeButtons = document.querySelectorAll('[data-theme-pick]');
  var NAMES = { system: 'System', light: 'Light', dark: 'Dark' };
  var narrow = window.matchMedia ? window.matchMedia('(max-width: 520px)') : { matches: false };

  function applyTheme(pref) {
    var dark = pref === 'dark' || (pref === 'system' && media && media.matches);
    root.dataset.theme = dark ? 'dark' : 'light';
    root.dataset.pref = pref;
    themeButtons.forEach(function (b) {
      b.setAttribute('aria-pressed', b.dataset.themePick === pref ? 'true' : 'false');
      if (narrow.matches) b.setAttribute('aria-label', 'Theme: ' + NAMES[b.dataset.themePick] + '. Tap to change.');
      else b.setAttribute('aria-label', b.dataset.themePick === 'system' ? 'Use system theme' : NAMES[b.dataset.themePick] + ' theme');
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
    version: '0.1.3',
    assets: {
      'Mothball-0.1.3.dmg': 26843546,
      'Mothball-0.1.3-windows-x64-setup.exe': 13002342,
      'Mothball-0.1.3-windows-arm64-setup.exe': 12163481,
      'Mothball-0.1.3-linux-x86_64.AppImage': 13317111,
      'Mothball-0.1.3-linux-aarch64.AppImage': 12582912
    }
  };

  var CATALOG = {
    mac: [
      { key: 'mac', match: /^Mothball-[\d.]+\.dmg$/, title: 'macOS app', fits: 'One download for every Mac: Apple silicon (M1 to M4) and Intel. macOS 11 or later. Signed and notarised.' }
    ],
    win: [
      { key: 'x64', match: /windows-x64-setup\.exe$/, title: 'Windows x64', fits: 'Most Windows PCs: Intel and AMD processors. Windows 10 and 11. Installs for your account, no admin prompt.' },
      { key: 'arm64', match: /windows-arm64-setup\.exe$/, title: 'Windows on Arm', fits: 'Snapdragon laptops and Surface Pro with an Arm chip. Runs natively, not emulated.' }
    ],
    linux: [
      { key: 'x64', match: /linux-x86_64\.AppImage$/, title: 'Linux x64', fits: 'AppImage for any distro: Intel and AMD desktops and laptops. Make it executable and run it; it updates itself.' },
      { key: 'arm64', match: /linux-aarch64\.AppImage$/, title: 'Linux Arm64', fits: 'AppImage for Arm laptops, Raspberry Pi 4 and 5 on a 64-bit OS, and Arm desktops.' }
    ]
  };
  var LABELS = { mac: 'macOS', win: 'Windows', linux: 'Linux' };

  function installFor(os, v, arm) {
    if (os === 'mac') return { title: 'Or with Homebrew', cmd: '$ brew tap herocodess/tap\n$ brew trust herocodess/tap\n$ brew install --cask mothball', note: 'The app includes the mothball command line tool.' };
    if (os === 'win') return { title: 'Or with Scoop', cmd: '> scoop bucket add herocodess https://github.com/herocodess/scoop-bucket\n> scoop install mothball', note: 'The installer also adds the mothball command. Not sure which one? Settings > System > About > System type. If SmartScreen warns you, choose More info, then Run anyway.' };
    var deb = arm ? 'arm64' : 'amd64', rpm = arm ? 'aarch64' : 'x86_64';
    return {
      title: 'Prefer a package?',
      cmd: '$ sudo apt install ./mothball_' + v + '-1_' + deb + '.deb     # Ubuntu, Debian\n$ sudo dnf install ./mothball-' + v + '-1.' + rpm + '.rpm    # Fedora',
      note: 'The .deb and .rpm (x64 and Arm64) are on the release page. Each adds Mothball to your app menu and the mothball command to your terminal.'
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

  function mb(bytes) { return (bytes / 1048576).toFixed(1) + ' MB'; }
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
    detected.textContent = state.os
      ? 'We picked ' + LABELS[state.os] + (state.os === 'mac' ? '' : arm ? ' on Arm' : state.arch === 'x86' ? ' x64' : '') + ' for you. Not right? Choose another.'
      : 'Free and open source, for macOS, Windows and Linux.';

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
      if (mine) top.appendChild(el('span', 'badge', 'Your system'));
      a.appendChild(top);
      a.appendChild(el('span', 'quiet', item.fits));

      var bottom = el('span', 'file-bottom');
      bottom.appendChild(el('span', 'file-name mono', asset.name));
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
