# The no-slop prose skill (saschb2b/skills), pinned and patched for bun.
#
# Upstream SKILL.md drives its bundled linter as `node slop-lint.mjs` and tells
# the agent to skip the lint step when node is missing. Only bun is on PATH here
# (see the global tools in ./default.nix) and it runs the script unchanged, so
# rewrite the invocations instead of installing a second JS runtime.
# Bump: point `rev` at a newer saschb2b/skills commit.
pkgs:
let
  src = builtins.fetchGit {
    url = "https://github.com/saschb2b/skills";
    rev = "8807494d7c0f2ad277f81d22c9fd261831128fc4";
  };
in
pkgs.runCommandLocal "no-slop-skill" { } ''
  cp -r ${src}/skills/productivity/no-slop $out
  chmod -R u+w $out
  substituteInPlace $out/SKILL.md \
    --replace-fail 'node slop-lint.mjs' 'bun slop-lint.mjs' \
    --replace-fail '`node` is unavailable' '`bun` is unavailable'
  substituteInPlace $out/slop-lint.mjs \
    --replace-fail '#!/usr/bin/env node' '#!/usr/bin/env bun' \
    --replace-fail 'node slop-lint.mjs' 'bun slop-lint.mjs'
''
