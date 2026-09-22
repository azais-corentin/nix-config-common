#!/usr/bin/env bun
//MISE description="Pin nix-config-common reusable workflows to the flake.lock revision"

import { readdirSync } from "node:fs";
import { join } from "node:path";
import { object, publish, readSource, runTargets, text } from "../../../lib/update.ts";

const workflow =
  /(uses:\s*azais-corentin\/nix-config-common\/\.github\/workflows\/[\w.-]+\.ya?ml@)[0-9a-f]{40}/g;

async function workflows(root: string): Promise<void> {
  const lock = object(JSON.parse(readSource(root, "flake.lock").body), "flake.lock");
  const nodes = object(lock.nodes, "flake.lock nodes");
  const rootNode = object(nodes[text(lock.root, "flake.lock root")], "flake.lock root node");
  const name = text(
    object(rootNode.inputs, "flake.lock root inputs")["nix-config-common"],
    "nix-config-common lock node",
  );
  const locked = object(object(nodes[name], "nix-config-common node").locked, "locked input");
  const rev = text(locked.rev, "nix-config-common locked rev", /^[a-f0-9]{40}$/);
  const directory = ".github/workflows";
  const sources = readdirSync(join(root, directory))
    .filter((file) => /\.ya?ml$/.test(file))
    .map((file) => readSource(root, `${directory}/${file}`));
  for (const source of sources) source.body = source.body.replace(workflow, `$1${rev}`);
  publish(sources, `nix-config-common workflows ${rev}`);
}

await runTargets("update:workflows", { workflows });
