#!/usr/bin/env bun
/*
#MISE description="Lint a commit message from stdin"
*/

import lint from "@commitlint/lint";
import load from "@commitlint/load";
import path from "node:path";

const file = Bun.argv[2];
if (!file) {
  console.error("Usage: commitlint <file>");
  process.exit(1);
}
const message = (await Bun.file(file).text()).trim();

if (!message) {
  console.error("No commit message provided on stdin.");
  process.exit(1);
}

// Resolve @commitlint/config-conventional from .mise/node_modules (this
// task's own dep tree) rather than process.cwd() (the repo root, which has
// no node_modules). Without this, Bun auto-installs a mismatched
// config-conventional into its global cache whose transitive deps are absent,
// crashing the resolver.
const miseDir = path.dirname(import.meta.dir);
const config = await load(
  {
    extends: ["@commitlint/config-conventional"],
    rules: {
      // Scopes use colons (e.g. host:common, host:desktop) which lodash
      // lowerCase strips — disable scope-case to avoid false positives.
      "scope-case": [0],
    },
  },
  { cwd: miseDir },
);

const result = await lint(
  message,
  config.rules,
  config.parserPreset ? { parserOpts: config.parserPreset.parserOpts as object } : {},
);

if (!result.valid) {
  const subject = message.split("\n")[0];
  console.error(`❌ Commit message failed conventional commit lint:`);
  console.error(`  ${subject}`);
  for (const e of result.errors) {
    console.error(`    ${e.name}: ${e.message}`);
  }
  process.exit(1);
}

// scope-case is disabled above because lodash lowerCase strips colons.
// Manually enforce: scope must be lowercase letters and ':' only.
const scopeMatch = message.match(/^\w+\(([^)]+)\)[!:]/);
if (scopeMatch) {
  const scope = scopeMatch[1];
  if (!/^[a-z:]+$/.test(scope)) {
    const subject = message.split("\n")[0];
    console.error(`❌ Commit message failed conventional commit lint:`);
    console.error(`  ${subject}`);
    console.error(`    scope-format: scope must contain only lowercase letters and ':'`);
    process.exit(1);
  }
}
