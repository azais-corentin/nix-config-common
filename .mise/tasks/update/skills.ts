#!/usr/bin/env bun
/*
#MISE description="Update pinned OMP and jcode skills by upstream source"
#USAGE arg "[targets]" var=#true help="Skill sources to update (default: all)" {
#USAGE   choices "anthropics" "wshobson" "apollographql" "antfu"
#USAGE }
*/

import {
  defaultCommit,
  escapeRegex,
  githubFile,
  publish,
  readSource,
  runTargets,
  text,
} from "../../lib/update.ts";

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
  const sources = [
    readSource(root, "home/cli/mise/oh-my-pi.nix"),
    readSource(root, "home/cli/mise/jcode.nix"),
  ];
  const pattern = new RegExp(
    `"github:${escapeRegex(repo)}((?:/[^"@\\r\\n]+)?)(?:@([^"\\r\\n]+))?"`,
    "g",
  );
  const paths = new Set<string>();
  for (const source of sources) {
    for (const match of source.body.matchAll(pattern)) {
      paths.add(skillPath(match[1]!.replace(/^\//, "")));
      text(match[2], `${source.name} ${repo} pin`, /^[a-f0-9]{40}$/);
    }
  }

  if (!paths.size) throw new Error(`No skill declarations found for ${name}`);

  const revision = await defaultCommit(repo);
  await Promise.all(
    [...paths].map(async (path) => {
      const file = path ? `${path}/SKILL.md` : "SKILL.md";
      // A missing SKILL.md also rejects moved directories before either consumer changes.
      await githubFile(repo, revision, file);
    }),
  );
  for (const source of sources) {
    source.body = source.body.replace(
      pattern,
      (_match, path: string) => `"github:${repo}${path}@${revision}"`,
    );
  }
  publish(sources, `${name} ${revision}`);
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
