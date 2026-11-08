#!/usr/bin/env bash
# Renders every fixture (or the ones named) into $OUT (default /tmp/cue-widget-shots):
#   fixtures/shoot.sh [fixture…]
# Per fixture: <fixture>-panel.png (compact representation), -popup.png (full representation)
# and -tooltip.png. A scratch copy of the plasmoid grabs its own representation with
# grabToImage on Qt's offscreen platform, so nothing shows on screen and no window needs
# focus; the transparent grab is flattened onto a dark background like the Plasma popup's.
# The offscreen screen is 800 px high, so long popups show their scrolling state.
set -euo pipefail
export QT_QPA_PLATFORM=${QT_QPA_PLATFORM:-offscreen}
dir=$(dirname "$(readlink -f "$0")")
out=${OUT:-/tmp/cue-widget-shots}
bg=${BG:-#202326}
mkdir -p "$out"
viewer=$(nix build --no-link --print-out-paths nixpkgs#kdePackages.plasma-sdk)/bin/plasmoidviewer
magick=$(nix build --no-link --print-out-paths nixpkgs#imagemagick)/bin/magick
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
if (($# == 0)); then
  set -- $(cd "$dir" && ls *.json | sed 's/\.json$//')
fi

# A timer that grabs an item at 2x, after the first poll has landed.
grab() { # <item id> <png>
  printf '        Timer { interval: 3000; running: true; onTriggered: %s.grabToImage(r => r.saveToFile("%s"), Qt.size(%s.width * 2, %s.height * 2)) }\n' "$1" "$2" "$1" "$1"
}

for fixture in "$@"; do
  for mode in panel popup tooltip; do
    png="$scratch/$fixture-$mode.png"
    pkg="$scratch/$fixture-$mode"
    cp -r "$dir/../org.nelieru.claudeusage" "$pkg"
    qml="$pkg/contents/ui/main.qml"
    case $mode in
      panel)
        args=(-f horizontal -l bottomedge -s 700x220)
        awk -v g="$(grab compactRoot "$png")" '{print} /^    compactRepresentation: MouseArea \{$/ {print g}' "$qml" >"$qml.new"
        ;;
      popup)
        # Under the content, the popup's background (a transparent grab of it comes out black).
        args=(-f planar -s 1400x1400)
        awk -v g="$(grab full "$png")" -v bg="        Rectangle { anchors.fill: parent; color: \"$bg\" }" \
          '{print} /^    fullRepresentation: Item \{$/ {print g; print bg}' "$qml" >"$qml.new"
        ;;
      tooltip)
        # The tooltip's content, at its own height, in place of the popup's.
        args=(-f planar -s 600x600)
        awk -v g="$(grab content "$png")" '
          /^        implicitWidth: content.outerWidth/ { sub(/content.outerWidth/, "300") }
          /^        PopupContent \{$/ { sub(/PopupContent/, "TooltipContent") }
          /^            height: full.height - full.topPad - full.bottomPad$/ { next }
          {print} /^    fullRepresentation: Item \{$/ {print g}' "$qml" >"$qml.new"
        ;;
    esac
    mv "$qml.new" "$qml"
    CUE_FIXTURE=$fixture PATH="$dir:$PATH" "$viewer" -a "$pkg" "${args[@]}" >"$out/$fixture-$mode.log" 2>&1 &
    pid=$!
    for _ in $(seq 100); do
      [[ -s $png ]] && break
      sleep 0.1
    done
    sleep 0.5
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    if [[ -s $png ]]; then
      "$magick" "$png" -bordercolor "$bg" -border 24 -background "$bg" -flatten "$out/$fixture-$mode.png"
    else
      echo "no grab for $fixture $mode, see $out/$fixture-$mode.log" >&2
    fi
  done
done
ls "$out"/*.png
