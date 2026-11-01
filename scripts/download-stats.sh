#!/bin/sh
# Prints how many times each release file has been downloaded from GitHub.
# This counts every download, whether it came from the website, Homebrew,
# Scoop, the in-app updater or a direct link.
#
#   scripts/download-stats.sh            all releases
#   scripts/download-stats.sh v0.1.3     one release
#
# Needs curl and python3. Uses GITHUB_TOKEN if set (higher rate limit).
set -eu
REPO=herocodess/mothball
URL="https://api.github.com/repos/$REPO/releases?per_page=100"
[ $# -gt 0 ] && URL="https://api.github.com/repos/$REPO/releases/tags/$1"
AUTH=""
[ -n "${GITHUB_TOKEN:-}" ] && AUTH="Authorization: Bearer $GITHUB_TOKEN"
curl -fsSL -H "Accept: application/vnd.github+json" ${AUTH:+-H "$AUTH"} "$URL" | python3 -c '
import json, re, sys
data = json.load(sys.stdin)
releases = data if isinstance(data, list) else [data]

def platform(name):
    n = name.lower()
    if n.startswith("checksums"): return None
    if n.endswith(".dmg"): return "macOS app"
    if "macos" in n: return "macOS CLI"
    if "setup.exe" in n: return "Windows installer (" + ("Arm" if "arm64" in n else "x64") + ")"
    if n.endswith(".zip") and "windows" in n: return "Windows zip (Scoop)"
    if "windows" in n: return "Windows CLI"
    if n.endswith(".appimage"): return "Linux AppImage (" + ("Arm" if "aarch64" in n else "x64") + ")"
    if n.endswith(".deb"): return "Linux .deb"
    if n.endswith(".rpm"): return "Linux .rpm"
    if "linux" in n: return "Linux CLI"
    return "Other"

totals, grand = {}, 0
for r in releases:
    rows = [(a["name"], a["download_count"]) for a in r.get("assets", []) if platform(a["name"])]
    sub = sum(c for _, c in rows)
    grand += sub
    tag, date = r["tag_name"], r["published_at"][:10]
    print(f"\n{tag}  ({date})  {sub} downloads")
    for name, c in sorted(rows, key=lambda x: -x[1]):
        print(f"  {c:>7}  {name}")
        totals[platform(name)] = totals.get(platform(name), 0) + c

print("\nBy platform")
for p, c in sorted(totals.items(), key=lambda x: -x[1]):
    print(f"  {c:>7}  {p}")
print(f"\nTotal: {grand}")
'
