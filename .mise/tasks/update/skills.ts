#!/usr/bin/env bun
/*
#MISE description="Update pinned OMP and jcode skills by upstream source"
#USAGE arg "[targets]" var=#true help="Skill sources to update (default: all)" {
#USAGE   choices "anthropics" "wshobson" "apollographql" "antfu" "boileau" "no-slop"
#USAGE }
*/

import {
  defaultCommit,
  escapeRegex,
  githubFile,
  nixString,
  one,
  publish,
  readSource,
  replaceOne,
  runTargets,
  text,
} from "../../lib/update.ts";

const repositories: Record<string, string> = {
  anthropics: "anthropics/skills",
  wshobson: "wshobson/agents",
  apollographql: "apollographql/skills",
  antfu: "antfu/skills",
  boileau: "alxbd/boileau",
  "no-slop": "saschb2b/skills",
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

  const patched =
    name === "no-slop" ? readSource(root, "home/cli/mise/no-slop-skill.nix") : undefined;
  const fetchPattern = /(\bsrc\s*=\s*builtins\.fetchGit\s*\{)([^{}]*)(\}\s*;)/;
  let patchedPath: string | undefined;
  if (patched) {
    const block = one(patched.body, fetchPattern, "no-slop Git source")[2]!;
    if (nixString(block, "url").value !== `https://github.com/${repo}`)
      throw new Error("Unexpected no-slop repository");
    text(nixString(block, "rev").value, "no-slop pinned commit", /^[a-f0-9]{40}$/);
    patchedPath = skillPath(
      one(patched.body, /\bcp\s+-r\s+\$\{src\}\/([^\s]+)\s+\$out/, "no-slop skill directory")[1]!,
    );
    paths.add(patchedPath);
    sources.push(patched);
  }
  if (!paths.size) throw new Error(`No skill declarations found for ${name}`);

  const revision = await defaultCommit(repo);
  const skills = await Promise.all(
    [...paths].map(async (path) => {
      const file = path ? `${path}/SKILL.md` : "SKILL.md";
      // A missing SKILL.md also rejects moved directories before either consumer changes.
      return { path, content: await githubFile(repo, revision, file) };
    }),
  );
  if (patched && patchedPath) {
    const content = skills.find((skill) => skill.path === patchedPath)!.content;
    const script = await githubFile(repo, revision, `${patchedPath}/slop-lint.mjs`);
    for (const [file, body, required] of [
      ["SKILL.md", content, ["node slop-lint.mjs", "`node` is unavailable"]],
      ["slop-lint.mjs", script, ["#!/usr/bin/env node", "node slop-lint.mjs"]],
    ] as const) {
      for (const phrase of required) {
        if (!body.includes(phrase))
          throw new Error(
            `no-slop ${revision}: ${file} no longer supports the Bun patch (${phrase})`,
          );
      }
    }
    patched.body = replaceOne(
      patched.body,
      fetchPattern,
      (match) => `${match[1]}${nixString(match[2]!, "rev").set(revision)}${match[3]}`,
      "no-slop Git source",
    );
  }
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
