#!/usr/bin/env bun
/*
#MISE description="Update pinned OMP skill sources"
#USAGE arg "[targets]" var=#true help="Skill sources to update (default: all)" {
#USAGE   choices "anthropics" "wshobson" "apollographql" "antfu"
#USAGE }
*/

import {
  defaultCommit,
  nixString,
  one,
  prefetch,
  publish,
  readSource,
  replaceOne,
  runTargets,
  sha256,
  text,
} from "../../../tooling/lib/update.ts";

const repositories: Record<string, string> = {
  anthropics: "anthropics/skills",
  wshobson: "wshobson/agents",
  apollographql: "apollographql/skills",
  antfu: "antfu/skills",
};

function skillPath(path: string): string {
  if (
    path &&
    (!/^[A-Za-z0-9_.-]+(?:\/[A-Za-z0-9_.-]+)*$/.test(path) ||
      path.split("/").some((part) => part === "." || part === ".."))
  ) {
    throw new Error(`Invalid skill path: ${path}`);
  }
  return path;
}

async function updateSource(root: string, name: string, repo: string): Promise<void> {
  const source = readSource(root, "home/cli/mise/oh-my-pi.nix");
  const pattern = new RegExp(
    String.raw`(\b${name}\s*=\s*pkgs\.fetchFromGitHub\s*\{)([^{}]*)(\}\s*;)`,
  );
  const block = one(source.body, pattern, `${name} skill source`)[2]!;
  if (`${nixString(block, "owner").value}/${nixString(block, "repo").value}` !== repo)
    throw new Error(`Unexpected ${name} skill repository`);
  text(nixString(block, "rev").value, `${name} pinned commit`, /^[a-f0-9]{40}$/);
  sha256(nixString(block, "hash").value, `${name} pinned hash`);

  const uses = new RegExp(String.raw`\bskill\s+"${name}"\s+"([^"\r\n]*)"`, "g");
  const paths = new Set([...source.body.matchAll(uses)].map((match) => skillPath(match[1]!)));
  if (!paths.size) throw new Error(`No skill declarations found for ${name}`);

  const revision = await defaultCommit(repo);
  const fetched = await prefetch(
    root,
    `https://github.com/${repo}/archive/${revision}.tar.gz`,
    true,
  );
  for (const path of paths) {
    const file = path ? `${path}/SKILL.md` : "SKILL.md";
    // A missing SKILL.md also rejects moved directories before the pin changes.
    if (!(await Bun.file(`${fetched.storePath}/${file}`).exists()))
      throw new Error(`${repo} ${revision} is missing ${file}`);
  }
  source.body = replaceOne(
    source.body,
    pattern,
    (match) => {
      const updated = nixString(match[2]!, "rev").set(revision);
      return `${match[1]}${nixString(updated, "hash").set(fetched.hash)}${match[3]}`;
    },
    `${name} skill source`,
  );
  publish([source], `${name} ${revision}`);
}

await runTargets(
  "update:skills",
  Object.fromEntries(
    Object.entries(repositories).map(([name, repo]) => [
      name,
      (root: string) => updateSource(root, name, repo),
    ]),
  ),
);
