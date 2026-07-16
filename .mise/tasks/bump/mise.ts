#!/usr/bin/env -S bun run
//MISE description="Refresh home/cli/mise/source.json from the latest GitHub release"
//
// Queries the jdx/mise GitHub "latest" release, derives the SRI hash of each
// musl release asset (from its `digest` field, or a nix prefetch fallback),
// and rewrites the pin atomically. Exits cleanly when already current.

import { $ } from "bun";
import { rename } from "node:fs/promises";

const repoRoot = process.env.MISE_PROJECT_ROOT;
if (!repoRoot) {
  console.error("error: MISE_PROJECT_ROOT not set");
  process.exit(1);
}

const relPath = "home/cli/mise/source.json";
const pin = `${repoRoot}/${relPath}`;

const apiUrl = "https://api.github.com/repos/jdx/mise/releases/latest";
const res = await fetch(apiUrl, {
  headers: { "user-agent": "bump-mise", accept: "application/vnd.github+json" },
});
if (!res.ok) {
  console.error(`error: GET ${apiUrl} failed: ${res.status} ${res.statusText}`);
  process.exit(1);
}

// GitHub's release payload is external input: narrow every field at the
// boundary rather than asserting a shape the compiler can't verify.
const raw: unknown = await res.json();
if (
  !raw ||
  typeof raw !== "object" ||
  !("tag_name" in raw) ||
  typeof raw.tag_name !== "string" ||
  !("assets" in raw) ||
  !Array.isArray(raw.assets)
) {
  console.error(`error: unexpected release schema from ${apiUrl}`);
  process.exit(1);
}
const tagName = raw.tag_name;
const assets = raw.assets;

const version = tagName.replace(/^v/, "");
if (!/^\d{4}\.\d+\.\d+$/.test(version)) {
  console.error(`error: unexpected version from tag_name: ${tagName}`);
  process.exit(1);
}
console.error(`upstream: version=${version}`);

const targets: [string, string][] = [
  ["x86_64-linux", "x64"],
  ["aarch64-linux", "arm64"],
];

const hashes: Record<string, string> = {};
for (const [nixSystem, arch] of targets) {
  const assetName = `mise-v${version}-linux-${arch}-musl.tar.gz`;
  const asset: unknown = assets.find(
    (a) => !!a && typeof a === "object" && "name" in a && a.name === assetName,
  );
  if (!asset || typeof asset !== "object") {
    console.error(`error: release asset not found: ${assetName}`);
    process.exit(1);
  }

  const digest = "digest" in asset && typeof asset.digest === "string" ? asset.digest : null;

  let sri: string;
  if (digest && digest.startsWith("sha256:")) {
    const hex = digest.slice("sha256:".length);
    sri = `sha256-${Buffer.from(hex, "hex").toString("base64")}`;
  } else {
    const url =
      "browser_download_url" in asset && typeof asset.browser_download_url === "string"
        ? asset.browser_download_url
        : null;
    if (!url) {
      console.error(`error: asset ${assetName} missing browser_download_url`);
      process.exit(1);
    }
    console.error(`         ${assetName}: no digest, prefetching…`);
    const pf = await $`nix store prefetch-file --json ${url}`.quiet();
    const parsed: unknown = JSON.parse(pf.stdout.toString());
    if (
      !parsed ||
      typeof parsed !== "object" ||
      !("hash" in parsed) ||
      typeof parsed.hash !== "string"
    ) {
      console.error(`error: unexpected nix prefetch output for ${url}`);
      process.exit(1);
    }
    sri = parsed.hash;
  }
  console.error(`         ${nixSystem}: ${sri}`);
  hashes[nixSystem] = sri;
}

const newBody = JSON.stringify({ version, hashes }, null, 2) + "\n";

const pinFile = Bun.file(pin);
const existing = (await pinFile.exists()) ? await pinFile.text() : "";
if (newBody === existing) {
  console.error(`source.json is already current (${version}).`);
  process.exit(0);
}

const tmp = `${pin}.tmp-${crypto.randomUUID().slice(0, 8)}`;
await Bun.write(tmp, newBody);
await rename(tmp, pin);

console.error(`updated ${pin}:`);
const prev = await $`git -C ${repoRoot} show HEAD:${relPath}`.nothrow().quiet();
const prevText = prev.exitCode === 0 ? prev.stdout.toString() : "";
await $`diff -u - ${pin} < ${new Response(prevText)}`.nothrow();
