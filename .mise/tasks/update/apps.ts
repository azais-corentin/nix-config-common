#!/usr/bin/env bun
/*
#MISE description="Update pinned applications and the Firefox theme"
#USAGE arg "[targets]" var=#true help="Targets to update (default: all)" {
#USAGE   choices "fastpotify" "mise" "paseo" "ff-ultima"
#USAGE }
*/

import {
  assetHash,
  commit,
  defaultCommit,
  github,
  json,
  latestRelease,
  nixString,
  object,
  one,
  prefetch,
  publish,
  readSource,
  replaceOne,
  runTargets,
  sha256,
  text,
  verifyDownload,
} from "../../lib/update.ts";

const systems = ["x86_64-linux", "aarch64-linux"] as const;

async function fastpotify(root: string): Promise<void> {
  const source = readSource(root, "home/desktop/fastpotify/package.nix");
  const arches = {
    "x86_64-linux": "x86_64-unknown-linux-gnu",
    "aarch64-linux": "aarch64-unknown-linux-gnu",
  };
  const archBlock = one(
    source.body,
    /\barch\s*=\s*\{([^{}]*)\}\s*\.\$\{stdenv\.hostPlatform\.system\}/s,
    "fastpotify architecture map",
  )[1]!;
  if ([...archBlock.matchAll(/=/g)].length !== systems.length)
    throw new Error("Unexpected fastpotify architecture map");
  for (const system of systems) {
    if (nixString(archBlock, system).value !== arches[system])
      throw new Error(`Unexpected fastpotify architecture: ${system}`);
  }
  const versionPin = nixString(source.body, "version");
  text(versionPin.value, "fastpotify pinned version", /^\d+\.\d+\.\d+$/);
  const release = (await latestRelease("crmne/fastpotify"))!;
  const version = text(release.tag, "fastpotify release tag", /^v\d+\.\d+\.\d+$/).slice(1);
  const hashes = await Promise.all(
    systems.map((system) =>
      assetHash(
        root,
        "crmne/fastpotify",
        release,
        `fastpotify-v${version}-${arches[system]}.tar.gz`,
      ),
    ),
  );
  source.body = versionPin.set(version);
  source.body = replaceOne(
    source.body,
    /(\bhash\s*=\s*\{)([^{}]*)(\}\s*\.\$\{stdenv\.hostPlatform\.system\})/s,
    (match) => {
      let block = match[2]!;
      for (const [index, system] of systems.entries()) {
        const pin = nixString(block, system);
        sha256(pin.value, `fastpotify ${system} pin`);
        block = pin.set(hashes[index]!);
      }
      return `${match[1]}${block}${match[3]}`;
    },
    "fastpotify hash map",
  );
  publish([source], `fastpotify ${version}`);
}

async function mise(root: string): Promise<void> {
  const source = readSource(root, "home/cli/mise/source.json");
  const pin = object(JSON.parse(source.body), "mise source pin");
  text(pin.version, "mise pinned version", /^\d{4}\.\d+\.\d+$/);
  const hashes = object(pin.hashes, "mise hashes");
  if (Object.keys(hashes).length !== systems.length)
    throw new Error("Unexpected mise architecture map");
  for (const system of systems) sha256(hashes[system], `mise ${system} pin`);
  const release = (await latestRelease("jdx/mise"))!;
  const version = text(release.tag, "mise release tag", /^v\d{4}\.\d+\.\d+$/).slice(1);
  const arches = { "x86_64-linux": "x64", "aarch64-linux": "arm64" };
  const downloaded = await Promise.all(
    systems.map((system) =>
      assetHash(root, "jdx/mise", release, `mise-v${version}-linux-${arches[system]}-musl.tar.gz`),
    ),
  );
  if (
    pin.version !== version ||
    systems.some((system, index) => hashes[system] !== downloaded[index])
  ) {
    pin.version = version;
    for (const [index, system] of systems.entries()) hashes[system] = downloaded[index]!;
    source.body = JSON.stringify(pin, null, 2) + "\n";
  }
  publish([source], `mise ${version}`);
}

async function paseo(root: string): Promise<void> {
  const source = readSource(root, "home/cli/mise/paseo.nix");
  one(source.body, /\bnode\s*=\s*lib\.mkDefault\s+"24"\s*;/, "Paseo Node 24 declaration");
  const packagePattern = /("npm:@getpaseo\/cli"\s*=\s*\{)([^{}]*)(\}\s*;)/;
  const block = one(source.body, packagePattern, "Paseo npm declaration")[2]!;
  text(nixString(block, "version").value, "Paseo pinned version", /^\d+\.\d+\.\d+$/);
  const release = object(
    await json("https://registry.npmjs.org/@getpaseo%2fcli/latest"),
    "Paseo npm release",
  );
  if (release.name !== "@getpaseo/cli") throw new Error("Unexpected npm package for Paseo");
  const version = text(release.version, "Paseo stable version", /^\d+\.\d+\.\d+$/);
  const dist = object(release.dist, "Paseo npm distribution");
  const url = text(dist.tarball, "Paseo npm tarball");
  if (url !== `https://registry.npmjs.org/@getpaseo/cli/-/cli-${version}.tgz`)
    throw new Error(`Unexpected Paseo tarball URL: ${url}`);
  await verifyDownload(url, text(dist.integrity, "Paseo npm integrity"));
  source.body = replaceOne(
    source.body,
    packagePattern,
    (match) => `${match[1]}${nixString(match[2]!, "version").set(version)}${match[3]}`,
    "Paseo npm declaration",
  );
  publish([source], `paseo ${version}`);
}

async function ffUltima(root: string): Promise<void> {
  const source = readSource(root, "home/desktop/firefox.nix");
  const pattern = /(\bultimaTheme\s*=\s*pkgs\.fetchFromGitHub\s*\{)([^{}]*)(\}\s*;)/;
  const block = one(source.body, pattern, "FF Ultima source")[2]!;
  if (
    nixString(block, "owner").value !== "soulhotel" ||
    nixString(block, "repo").value !== "FF-ULTIMA"
  ) {
    throw new Error("Unexpected FF Ultima repository");
  }
  const current = text(nixString(block, "rev").value, "FF Ultima pinned commit", /^[a-f0-9]{40}$/);
  sha256(nixString(block, "sha256").value, "FF Ultima pinned hash");
  const repo = "soulhotel/FF-ULTIMA";
  const release = await latestRelease(repo, true);
  let revision: string | undefined;
  if (release) {
    const released = await commit(repo, release.tag);
    if (released === current) revision = released;
    else {
      const comparison = object(
        await github(repo, `/compare/${current}...${released}`),
        "FF Ultima release comparison",
      );
      const status = text(
        comparison.status,
        "FF Ultima release ancestry",
        /^(ahead|behind|identical|diverged)$/,
      );
      // A Git pin can contain fixes newer than the latest stable release.
      if (status === "ahead" || status === "identical") revision = released;
    }
  }
  revision ??= await defaultCommit(repo);
  const fetched = await prefetch(
    root,
    `https://github.com/${repo}/archive/${revision}.tar.gz`,
    true,
  );
  if (!(await Bun.file(`${fetched.storePath}/userChrome.css`).exists())) {
    throw new Error(`FF Ultima ${revision} is missing userChrome.css`);
  }
  source.body = replaceOne(
    source.body,
    pattern,
    (match) => {
      const updated = nixString(match[2]!, "rev").set(revision);
      return `${match[1]}${nixString(updated, "sha256").set(fetched.hash)}${match[3]}`;
    },
    "FF Ultima source",
  );
  publish([source], `ff-ultima ${revision}`);
}

await runTargets("update:apps", { fastpotify, mise, paseo, "ff-ultima": ffUltima });
