#!/bin/zsh
# Builds Motiv.app with Xcode into ./build and installs it to /Applications.
# Usage: ./build.sh [--no-install]
set -euo pipefail
cd "${0:A:h}"

install=true
[[ "${1:-}" == "--no-install" ]] && install=false

# Local build without a developer account: ad-hoc signed, with the same sandbox as in the App Store.
mkdir -p .build
if ! xcodebuild -project Motiv.xcodeproj -scheme Motiv -configuration Release \
    -derivedDataPath .build/xcode \
    CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
    build > .build/xcodebuild.log 2>&1; then
    grep -E "error:" .build/xcodebuild.log >&2 || tail -20 .build/xcodebuild.log >&2
    echo "Build fehlgeschlagen, vollständiges Protokoll: $PWD/.build/xcodebuild.log" >&2
    exit 1
fi

app=build/Motiv.app
built=.build/xcode/Build/Products/Release/Motiv.app
rm -rf "$app"
mkdir -p build
ditto "$built" "$app"

# Build copies must not take over opening images and folders from the installed app.
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$lsregister" -u "$built" 2>/dev/null || true
"$lsregister" -u "$app" 2>/dev/null || true

# The build number comes from Config/Motiv.xcconfig, the same source Xcode reads.
build_number=$(sed -n 's/^CURRENT_PROJECT_VERSION = \([0-9][0-9]*\)$/\1/p' Config/Motiv.xcconfig)
echo "Gebaut: $PWD/$app (Build ${build_number:-?})"

$install || exit 0

target=/Applications/Motiv.app
# The installed Motiv has to quit before it can be replaced; it is reopened afterwards.
# Other copies, e.g. one started from Xcode, are left alone.
is_running() { pgrep -qf "^$target/Contents/MacOS/Motiv"; }
was_running=false
if is_running; then
    was_running=true
    osascript -e "quit app \"$target\"" >/dev/null 2>&1 || true
    for _ in {1..50}; do is_running || break; sleep 0.1; done
    if is_running; then
        echo "Motiv lässt sich nicht beenden (vielleicht ist noch ein Dialog offen)." >&2
        echo "Bitte Motiv von Hand beenden und erneut bauen. Gebaut ist die neue Version schon: $PWD/$app" >&2
        exit 1
    fi
fi

rm -rf "$target"
ditto "$app" "$target"
# ditto keeps the bundle's old date; macOS caches app and document icons by that date and would
# go on showing icons from an earlier build.
touch "$target"
"$lsregister" -f "$target"
echo "Installiert: $target"

$was_running && open "$target"
exit 0
