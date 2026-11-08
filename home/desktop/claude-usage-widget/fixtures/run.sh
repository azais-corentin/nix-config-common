#!/usr/bin/env bash
# Runs the plasmoid from the source tree against a view fixture:
#   fixtures/run.sh <fixture> [panel|popup]
# panel: the compact representation in a horizontal panel; popup: the full representation.
set -euo pipefail
dir=$(dirname "$(readlink -f "$0")")
fixture=${1:-runs-out}
mode=${2:-popup}
[[ -f "$dir/$fixture.json" ]] || { echo "no fixture $dir/$fixture.json" >&2; exit 2; }
export CUE_FIXTURE=$fixture
export PATH="$dir:$PATH"
args=(-a "$dir/../org.nelieru.claudeusage")
case $mode in
  panel) args+=(-f horizontal -l bottomedge -s 560x220) ;;
  popup) args+=(-f planar -s 1100x1000) ;;
  *) echo "mode must be panel or popup" >&2; exit 2 ;;
esac
exec nix shell nixpkgs#kdePackages.plasma-sdk -c plasmoidviewer "${args[@]}"
