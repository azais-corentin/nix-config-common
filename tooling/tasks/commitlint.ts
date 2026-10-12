#!/usr/bin/env bun
/*
#MISE description="Lint a commit message file"
#MISE hide=true
#USAGE arg "<file>" help="File containing the commit message"
*/

import lint from "@commitlint/lint";
import load from "@commitlint/load";
import path from "node:path";

const file = process.env.usage_file ?? Bun.argv[2];
if (!file) {
  console.error("Usage: commitlint <file>");
  process.exit(1);
}
const message = (await Bun.file(file).text()).trim();

if (!message) {
  console.error("Commit message file is empty.");
  process.exit(1);
}

// Resolve @commitlint/config-conventional from the tooling bundle's
// node_modules (built by Nix from package-lock.json, next to tasks/) rather
// than process.cwd() (the consumer repo root, which has no node_modules).
const toolingDir = path.dirname(import.meta.dir);
const config = await load(
  {
    extends: ["@commitlint/config-conventional"],
    rules: {
      // Scopes carry separators (e.g. host:common, pkgs/rpiboot) which lodash
      // lowerCase strips — disable scope-case to avoid false positives.
      "scope-case": [0],
    },
  },
  { cwd: toolingDir },
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
// Manually enforce a scope shape wide enough for package scopes
// (at1000-interface, pkgs/rpiboot) while still rejecting uppercase and spaces.
const scopeMatch = message.match(/^\w+\(([^)]+)\)[!:]/);
if (scopeMatch) {
  const scope = scopeMatch[1]!;
  if (!/^[a-z0-9][a-z0-9:/-]*$/.test(scope)) {
    const subject = message.split("\n")[0];
    console.error(`❌ Commit message failed conventional commit lint:`);
    console.error(`  ${subject}`);
    console.error(
      `    scope-format: scope must start with a lowercase letter or digit and contain only lowercase letters, digits, ':', '/', and '-'`,
    );
    process.exit(1);
  }
}
