#!/usr/bin/env bun
//MISE description="Update named flake inputs, or all inputs when omitted"
//MISE quiet=true
//USAGE arg "[inputs]" var=#true help="Flake input names; omit to update all"

import { join } from "node:path";
import { object } from "../../lib/update.ts";
import { report, status, type Row } from "../../lib/report.ts";

const task = "update:inputs";
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

type Locked = Record<string, unknown>;

// Maps every input path ("home-manager/nixpkgs") to its locked reference.
// `follows` entries alias another node and are skipped; breadth-first order
// names a node shared by several parents by its shortest path.
async function lockedInputs(): Promise<Map<string, Locked>> {
  const file = Bun.file(join(root!, "flake.lock"));
  const result = new Map<string, Locked>();
  if (!(await file.exists())) return result;
  const lock = object(await file.json(), "flake.lock");
  const nodes = object(lock.nodes, "flake.lock nodes");
  const seen = new Set<string>();
  const queue: [string, string][] = [["", String(lock.root)]];
  for (const [prefix, key] of queue) {
    const node = object(nodes[key], `flake.lock node ${key}`);
    for (const [name, target] of Object.entries(object(node.inputs ?? {}, `${key} inputs`))) {
      if (typeof target !== "string" || seen.has(target)) continue;
      seen.add(target);
      const path = prefix + name;
      result.set(path, object(object(nodes[target], path).locked, `${path} locked`));
      queue.push([`${path}/`, target]);
    }
  }
  return result;
}

const revision = (locked: Locked) =>
  typeof locked.rev === "string" ? locked.rev : String(locked.narHash ?? "?").slice(7, 14);
const date = (locked: Locked) =>
  typeof locked.lastModified === "number"
    ? new Date(locked.lastModified * 1000).toISOString().slice(0, 10)
    : undefined;

const before = await lockedInputs();
status(`${task}  nix flake update${inputs.length ? ` ${inputs.join(" ")}` : ""}…`);
const child = Bun.spawn(["nix", "flake", "update", ...inputs], {
  cwd: root,
  stdin: "inherit",
  stdout: "pipe",
  stderr: "pipe",
});
const [stdout, stderr, code] = await Promise.all([
  new Response(child.stdout).text(),
  new Response(child.stderr).text(),
  child.exited,
]);
if (code !== 0) {
  // Drop the notices nix prints before its error (saved settings, dirty tree).
  const output = stderr.trim() || stdout.trim();
  const error = output.slice(Math.max(0, output.search(/^error:/m))).replace(/^error:\s*/, "");
  report(task, { updated: 0, current: 0, failed: 1 }, [{ name: "nix flake update", error }]);
  process.exit(code);
}
const after = await lockedInputs();

const rows: Row[] = [];
for (const path of [...new Set([...before.keys(), ...after.keys()])].sort()) {
  const was = before.get(path);
  const now = after.get(path);
  if (was && now && Bun.deepEquals(was, now)) continue;
  const dates = [was && date(was), now && date(now)].filter(Boolean);
  rows.push({
    name: path,
    from: was && revision(was),
    to: now && revision(now),
    note: dates[0] === dates[1] ? dates[0] : dates.join(" → ") || undefined,
  });
}
// nix only warns about a name that matches no input, so fail on it here.
const unknown = inputs.filter((name) => !after.has(name));
for (const name of unknown) rows.push({ name, error: "no such flake input" });
const unchanged = (inputs.length ? inputs : [...after.keys()]).filter(
  (path) => after.has(path) && !rows.some((row) => row.name === path),
);
report(
  task,
  { updated: rows.length - unknown.length, current: unchanged.length, failed: unknown.length },
  rows,
);
if (unknown.length) process.exitCode = 1;
