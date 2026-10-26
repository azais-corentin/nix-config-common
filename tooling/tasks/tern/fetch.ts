#!/usr/bin/env bun
//MISE description="Add the pinned Tern archive to the Nix store (needs a build.stencil.so sign-in in Firefox)"
//MISE quiet=true

// Tern's archive is invite-only, so its package uses requireFile: every machine
// adds the pinned archive to its store once per version before building.

import { join } from "node:path";
import { addStencilFile, stencilPin } from "../../lib/stencil.ts";
import { command, object, text } from "../../lib/update.ts";

const task = "tern:fetch";
const pinPath = "home/desktop/tern/source.json";

const root = process.env.MISE_PROJECT_ROOT;
if (!root) {
  console.error("Run this task through mise in the repository.");
  process.exit(1);
}

// A consumer builds the nix-config-common revision its flake.lock pins;
// nix-config-common itself builds its working tree.
async function pinFile(): Promise<string> {
  const lock = object(await Bun.file(join(root!, "flake.lock")).json(), "flake.lock");
  if (!Object.hasOwn(object(lock.nodes, "flake.lock nodes"), "nix-config-common"))
    return join(root!, pinPath);
  const { stdout } = await command(root!, ["nix", "flake", "archive", "--json", "--dry-run", "."]);
  const inputs = object(object(JSON.parse(stdout), "flake archive").inputs, "flake inputs");
  const common = object(inputs["nix-config-common"], "nix-config-common input");
  return join(text(common.path, "nix-config-common store path", /^\/nix\/store\//), pinPath);
}

try {
  const pin = stencilPin(await Bun.file(await pinFile()).json(), "tern source pin");
  const added = await addStencilFile(root, pin);
  console.log(
    `${task}  tern ${pin.version} ${added ? "added to the store" : "already in the store"}`,
  );
} catch (error) {
  console.error(`${task}  error: ${error instanceof Error ? error.message : String(error)}`);
  process.exit(1);
}
