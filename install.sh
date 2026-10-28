#!/bin/bash
# Installs Sam's plug-ins and apps on a Mac, and keeps them up to date:
#     curl -fsSL https://samsegan.github.io/plugins/install.sh | bash                   # everything
#     curl -fsSL https://samsegan.github.io/plugins/install.sh | bash -s -- --plugins   # the plug-ins only
#
# The plug-ins (AU and VST3) come from the newest release of
# https://github.com/samsegan/plugins. That release's update-plugins.sh
# installs them into ~/Library/Audio/Plug-Ins, then stays as an agent that
# installs each new release by itself, at login and every 30 minutes. The apps
# (REF, Combiner, Plug, Preseterizer) come from their own pages' newest DMGs, go into
# /Applications (~/Applications if that isn't writable), open, and update
# themselves. An app this Mac can't run (too old a macOS, or an Intel Mac for
# an Apple silicon app) is skipped. Running it again brings anything that's
# behind up to date and leaves the rest alone.
#
# A download made by curl isn't quarantined, so macOS doesn't ask you to
# approve each plug-in and app the way it does for a browser download.
#
# Published from plugins/site in the (private) music-plugins repository by
# scripts/release-plugins.sh.
set -euo pipefail

# MUSIC_PLUGINS_GITHUB points a test at a stand-in for github.com.
GITHUB="${MUSIC_PLUGINS_GITHUB:-https://github.com}"
PLUGINS_REPO="samsegan/plugins"
UPDATER="update-plugins.sh"
# The plug-ins' deployment target (CMAKE_OSX_DEPLOYMENT_TARGET in plugins.yml).
PLUGINS_MIN_MACOS="11.0"
# Each app: the name of its .dmg and .app, then the public repo it's released from.
APPS=("REF samsegan/ref" "Combiner samsegan/combiner" "Plug samsegan/plug" "Preseterizer samsegan/preseterizer")
QUIT_WAIT_SECONDS=10

# Whether macOS version $1 is $2 or later (14.10 is later than 14.9).
at_least() {
    [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n 1)" == "$2" ]]
}

plist() {
    /usr/libexec/PlistBuddy -c "Print :$2" "$1"
}

# Its arguments as "a, b and c".
listing() {
    local out="" i
    for ((i = 1; i <= $#; i++)); do
        if [[ "$i" -eq 1 ]]; then out="${!i}"
        elif [[ "$i" -eq $# ]]; then out="$out and ${!i}"
        else out="$out, ${!i}"; fi
    done
    printf '%s' "$out"
}

# Unmounts every DMG mounted, and removes the downloads.
cleanup() {
    local mount
    for mount in ${mounts[@]+"${mounts[@]}"}; do hdiutil detach "$mount" -quiet 2>/dev/null || true; done
    rm -rf "$TMP"
}

# The plug-ins, with the newest release's own updater: it installs them now
# (or says they're up to date), then stays as the agent that keeps them so.
install_plugins() {
    local updater="$TMP/$UPDATER"
    echo "== The plug-ins"
    if ! at_least "$MACOS" "$PLUGINS_MIN_MACOS"; then
        echo "They need macOS $PLUGINS_MIN_MACOS or later (this Mac has $MACOS): skipped."
        skipped+=("the plug-ins")
        return 0
    fi
    curl -fsSL -o "$updater" "$GITHUB/$PLUGINS_REPO/releases/latest/download/$UPDATER" || return 1
    bash "$updater" </dev/null || return 1
    bash "$updater" --install-agent </dev/null >/dev/null || return 1
    done_list+=("the plug-ins")
    plugins_done=1
}

# Asks the app with bundle id $1 to quit, and waits a while for executable $2 to stop.
quit_app() {
    local id="$1" exe="$2" waited
    pgrep -f "$exe" >/dev/null || return 0
    osascript -e "tell application id \"$id\" to quit" </dev/null >/dev/null 2>&1 || true
    for ((waited = 0; waited < QUIT_WAIT_SECONDS; waited++)); do
        pgrep -f "$exe" >/dev/null || return 0
        sleep 1
    done
}

# App $1 from the newest $1.dmg released in repo $2: into $APP_DIR, replacing
# (and first quitting) an older copy there, then opened.
install_app() {
    local name="$1" repo="$2" dir="$TMP/$1" app info min exe id version dest have
    echo "== $name"
    mkdir -p "$dir/mount"
    curl -fL --progress-bar -o "$dir/$name.dmg" "$GITHUB/$repo/releases/latest/download/$name.dmg" || return 1
    hdiutil attach "$dir/$name.dmg" -nobrowse -readonly -quiet -mountpoint "$dir/mount" </dev/null || return 1
    mounts+=("$dir/mount")
    app="$dir/mount/$name.app"
    info="$app/Contents/Info.plist"
    min="$(plist "$info" LSMinimumSystemVersion)" || return 1
    exe="$(plist "$info" CFBundleExecutable)" || return 1
    id="$(plist "$info" CFBundleIdentifier)" || return 1
    version="$(plist "$info" CFBundleShortVersionString)" || return 1
    if ! at_least "$MACOS" "$min"; then
        echo "$name needs macOS $min or later (this Mac has $MACOS): skipped."
        skipped+=("$name")
        return 0
    fi
    if [[ "$APPLE_SILICON" != 1 && "$(file -b "$app/Contents/MacOS/$exe")" != *x86_64* ]]; then
        echo "$name needs a Mac with Apple silicon (M1 or newer): skipped."
        skipped+=("$name")
        return 0
    fi
    dest="$APP_DIR/$name.app"
    have="$(plist "$dest/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || true)"
    if [[ "$have" == "$version" ]]; then
        echo "$name $version is installed already."
    else
        mkdir -p "$APP_DIR"
        quit_app "$id" "$dest/Contents/MacOS/$exe"
        rm -rf "$dest"
        ditto "$app" "$dest" || return 1
        echo "Installed $name $version in $APP_DIR. Opening it."
        open "$dest" </dev/null || true
    fi
    done_list+=("$name $version")
    apps_done=1
}

main() {
    local want_apps=1 arg entry name repo
    for arg in "$@"; do
        case "$arg" in
            --plugins) want_apps=0 ;;
            *) echo "Usage: install.sh [--plugins]   (no option: the plug-ins and every app)" >&2; exit 2 ;;
        esac
    done
    if [[ "$(uname -s)" != Darwin ]]; then
        echo "These are Mac plug-ins and apps. (REF for Windows: https://samsegan.github.io/ref)" >&2
        exit 1
    fi

    MACOS="$(sw_vers -productVersion)"
    # Apple silicon, even when this shell runs under Rosetta (where uname -m says x86_64).
    APPLE_SILICON="$(sysctl -n hw.optional.arm64 2>/dev/null || echo 0)"
    APP_DIR="/Applications"
    [[ -w "$APP_DIR" ]] || APP_DIR="$HOME/Applications"
    TMP="$(mktemp -d)"
    mounts=()
    trap cleanup EXIT
    done_list=()
    skipped=()
    failed=()
    plugins_done=0
    apps_done=0

    install_plugins || failed+=("the plug-ins")
    if [[ "$want_apps" -eq 1 ]]; then
        for entry in "${APPS[@]}"; do
            read -r name repo <<<"$entry"
            install_app "$name" "$repo" || failed+=("$name")
        done
    fi

    echo
    if [[ "${#done_list[@]}" -gt 0 ]]; then
        echo "Done: $(listing "${done_list[@]}")."
    fi
    if [[ "$plugins_done" -eq 1 ]]; then
        echo "Quit and reopen your DAW (Logic, Live, ...) to load new plug-ins. They update"
        echo "themselves from now on: a check at login and every 30 minutes, and a"
        echo "notification when a new version is in."
    fi
    if [[ "$apps_done" -eq 1 ]]; then
        echo "The apps update themselves too: each checks once a day."
    fi
    if [[ "${#skipped[@]}" -gt 0 ]]; then
        echo "Skipped $(listing "${skipped[@]}"): this Mac can't run them."
    fi
    if [[ "${#failed[@]}" -gt 0 ]]; then
        echo "Couldn't install $(listing "${failed[@]}"). Check the connection and run the same line again." >&2
        exit 1
    fi
    [[ "${#done_list[@]}" -gt 0 ]]
}

# Last, so a download cut short runs nothing: bash reads the whole of main first.
main "$@"
