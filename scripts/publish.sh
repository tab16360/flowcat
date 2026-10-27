#!/bin/bash
# Run in a normal macOS terminal with GitHub CLI authenticated.
set -euo pipefail
cd "$(dirname "$0")/.."
command -v gh >/dev/null || { echo 'Install GitHub CLI first: brew install gh' >&2; exit 1; }
owner=$(gh api user --jq .login)
repo="$owner/flowcat"
if git remote get-url origin >/dev/null 2>&1; then
  echo 'origin already exists; follow docs/releasing.md to continue without creating another repository.' >&2
  exit 1
fi
if [ -n "$(git status --porcelain)" ]; then
  echo 'Working tree must be clean before publishing.' >&2
  exit 1
fi
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)
if [ "$owner" != tab16360 ]; then
  python3 - "$owner" <<'PY'
from pathlib import Path
import sys
owner = sys.argv[1]
for filename in ['README.md', 'README.zh-CN.md', 'docs/index.html', 'docs/zh/index.html', 'Sources/Core.swift', '.github/FUNDING.yml']:
    p = Path(filename)
    p.write_text(p.read_text().replace('github.com/tab16360/', f'github.com/{owner}/').replace('github.com/sponsors/tab16360', f'github.com/sponsors/{owner}').replace('tab16360.github.io', f'{owner}.github.io').replace('github: tab16360', f'github: {owner}'))
PY
  git add README.md README.zh-CN.md docs/index.html docs/zh/index.html Sources/Core.swift .github/FUNDING.yml
  git commit -m 'Set project publishing links'
fi
bash scripts/test.sh
bash scripts/package.sh
gh repo create "$repo" --public --source . --remote origin --push --description 'FlowCat - Network & Disk Monitor for Mac: live speed, per-process disk writes and SMART health in the menu bar'
gh api --method POST "repos/$repo/pages" -f build_type=workflow >/dev/null
gh repo edit "$repo" --homepage "https://$owner.github.io/flowcat/"
gh workflow run pages.yml --repo "$repo" --ref main
git tag -a "v$version" -m "Release $version"
git push origin "v$version"
echo "Repository: https://github.com/$repo"
echo "Actions: https://github.com/$repo/actions"
echo "Release and Pages have been triggered; check Actions for completion."
