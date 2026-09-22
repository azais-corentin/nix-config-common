#!/usr/bin/env bun
//MISE description="Update named flake inputs, or all inputs when omitted"
//USAGE arg "[inputs]" var=#true help="Flake input names; omit to update all"

const root = process.env.MISE_PROJECT_ROOT;
if (!root) {
  console.error("Run this task through mise in the repository.");
  process.exit(1);
}

const raw = process.env.usage_inputs;
const inputs = raw === undefined ? Bun.argv.slice(2) : raw.trim().split(/\s+/).filter(Boolean);
if (inputs.some((name) => !/^[a-zA-Z_][a-zA-Z0-9_-]*$/.test(name))) {
  console.error("Input names must contain only letters, digits, underscores, and hyphens.");
  process.exit(1);
}
const child = Bun.spawn(["nix", "flake", "update", ...inputs], {
  cwd: root,
  stdin: "inherit",
  stdout: "inherit",
  stderr: "inherit",
});
process.exit(await child.exited);
