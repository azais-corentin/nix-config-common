import { createHash } from "node:crypto";
import {
  chmodSync,
  lstatSync,
  readFileSync,
  realpathSync,
  renameSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { isAbsolute, relative, resolve, sep } from "node:path";

export type Source = { path: string; name: string; original: string; body: string; mode: number };
export type Release = { tag: string; assets: unknown[] };
type Target = (root: string) => Promise<void>;

export function object(value: unknown, label: string): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(`Invalid ${label}: expected an object`);
  }
  return value as Record<string, unknown>;
}

export function text(value: unknown, label: string, pattern?: RegExp): string {
  if (typeof value !== "string" || !value || (pattern && !pattern.test(value))) {
    throw new Error(`Invalid ${label}: ${JSON.stringify(value)}`);
  }
  return value;
}

// mise encodes variadic arguments as shell words. Decode quotes without shell expansion.
function shellWords(input: string): string[] {
  const words: string[] = [];
  let word = "";
  let quote = "";
  let started = false;
  for (let index = 0; index < input.length; index++) {
    const char = input[index]!;
    if (char === "\\" && quote !== "'") {
      const next = input[++index];
      if (next === undefined) throw new Error("Invalid target arguments: trailing backslash");
      if (quote === '"' && !["$", "`", '"', "\\", "\n"].includes(next)) word += "\\";
      if (next !== "\n") word += next;
      started = true;
    } else if (quote) {
      if (char === quote) quote = "";
      else word += char;
    } else if (char === "'" || char === '"') {
      quote = char;
      started = true;
    } else if (/\s/.test(char)) {
      if (started) words.push(word);
      word = "";
      started = false;
    } else {
      word += char;
      started = true;
    }
  }
  if (quote) throw new Error("Invalid target arguments: unclosed quote");
  if (started) words.push(word);
  return words;
}

export async function runTargets(task: string, targets: Record<string, Target>): Promise<void> {
  try {
    const names = Object.keys(targets);
    const args =
      process.env.usage_targets === undefined
        ? Bun.argv.slice(2)
        : shellWords(process.env.usage_targets);
    if (args.length === 1 && (args[0] === "--help" || args[0] === "-h")) {
      console.log(
        `Usage: mise run ${task} [targets...]\nTargets: ${names.join(", ")}\nOmit targets to update all.`,
      );
      return;
    }
    if (args[0] === "--") args.shift();
    const unknown = args.filter((name) => !Object.hasOwn(targets, name));
    if (unknown.length)
      throw new Error(
        `Unknown targets: ${unknown.map((name) => JSON.stringify(name)).join(", ")}. Choose: ${names.join(", ")}`,
      );
    const configuredRoot = text(process.env.MISE_PROJECT_ROOT, "MISE_PROJECT_ROOT");
    if (!isAbsolute(configuredRoot)) throw new Error("MISE_PROJECT_ROOT must be an absolute path");
    const root = realpathSync(configuredRoot);
    for (const name of new Set(args.length ? args : names)) {
      console.error(`${task}: ${name}`);
      await targets[name]!(root);
    }
  } catch (error) {
    console.error(`error: ${error instanceof Error ? error.message : String(error)}`);
    process.exitCode = 1;
  }
}

export function readSource(root: string, name: string): Source {
  const path = resolve(root, name);
  const resolved = realpathSync(path);
  const fromRoot = relative(root, resolved);
  if (!fromRoot || fromRoot === ".." || fromRoot.startsWith(`..${sep}`) || isAbsolute(fromRoot)) {
    throw new Error(`Source is outside MISE_PROJECT_ROOT: ${name}`);
  }
  const stat = lstatSync(path);
  if (!stat.isFile()) throw new Error(`Source must be a regular file: ${name}`);
  const original = readFileSync(resolved, "utf8");
  return { path: resolved, name, original, body: original, mode: stat.mode & 0o777 };
}

export function one(body: string, pattern: RegExp, label: string): RegExpMatchArray {
  const matches = [
    ...body.matchAll(new RegExp(pattern.source, pattern.flags.replaceAll("g", "") + "g")),
  ];
  if (matches.length !== 1) throw new Error(`Expected one ${label}, found ${matches.length}`);
  return matches[0]!;
}

export function replaceOne(
  body: string,
  pattern: RegExp,
  replacement: (match: RegExpMatchArray) => string,
  label: string,
): string {
  const match = one(body, pattern, label);
  return (
    body.slice(0, match.index) + replacement(match) + body.slice(match.index! + match[0].length)
  );
}

export function nixString(
  body: string,
  attribute: string,
): { value: string; set: (value: string) => string } {
  const pattern = new RegExp(
    `(^[ \\t]*${escapeRegex(attribute)}\\s*=\\s*")([^"\\r\\n]*)("\\s*;)`,
    "m",
  );
  const match = one(body, pattern, `Nix attribute ${attribute}`);
  return {
    value: match[2]!,
    set: (value) => {
      if (/["\\\r\n]|\$\{/.test(value)) throw new Error(`Unsafe Nix string for ${attribute}`);
      return replaceOne(body, pattern, (parts) => `${parts[1]}${value}${parts[3]}`, attribute);
    },
  };
}

export function escapeRegex(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

// Stage every file before publishing. Synchronous renames allow rollback on a failed publication.
export function publish(sources: Source[], label: string): void {
  const changed = sources.filter((source) => source.body !== source.original);
  if (!changed.length) {
    console.error(`${label}: already current`);
    return;
  }
  const staged: {
    source: Source;
    next: string;
    backup: string;
    published: boolean;
    keepBackup: boolean;
  }[] = [];
  try {
    for (const source of changed) {
      const suffix = `.update-${crypto.randomUUID()}`;
      const entry = {
        source,
        next: source.path + suffix,
        backup: source.path + suffix + ".bak",
        published: false,
        keepBackup: false,
      };
      staged.push(entry);
      writeFileSync(entry.next, source.body, { flag: "wx", mode: source.mode });
      chmodSync(entry.next, source.mode);
      writeFileSync(entry.backup, source.original, { flag: "wx", mode: source.mode });
      chmodSync(entry.backup, source.mode);
    }
    for (const source of sources) {
      if (
        !lstatSync(source.path).isFile() ||
        readFileSync(source.path, "utf8") !== source.original
      ) {
        throw new Error(`Source changed during update: ${source.name}`);
      }
    }
    for (const entry of staged) {
      renameSync(entry.next, entry.source.path);
      entry.published = true;
    }
  } catch (error) {
    const failures: string[] = [];
    for (const entry of staged.toReversed()) {
      if (!entry.published) continue;
      try {
        if (readFileSync(entry.source.path, "utf8") !== entry.source.body) {
          throw new Error("source changed after publication");
        }
        renameSync(entry.backup, entry.source.path);
      } catch (rollbackError) {
        entry.keepBackup = true;
        failures.push(
          `${entry.source.name}: ${String(rollbackError)}; original saved at ${entry.backup}`,
        );
      }
    }
    if (failures.length)
      throw new Error(`${String(error)}. Rollback failed: ${failures.join("; ")}`);
    throw error;
  } finally {
    for (const entry of staged) {
      rmSync(entry.next, { force: true });
      if (!entry.keepBackup) rmSync(entry.backup, { force: true });
    }
  }
  console.error(`${label}: updated ${changed.map((source) => source.name).join(", ")}`);
}

async function request(url: string, missingIsNull = false): Promise<Response | null> {
  const headers: Record<string, string> = { "user-agent": "nix-config-update" };
  if (new URL(url).hostname === "api.github.com") {
    headers.accept = "application/vnd.github+json";
    const token = process.env.GH_TOKEN || process.env.GITHUB_TOKEN;
    if (token) headers.authorization = `Bearer ${token}`;
  }
  const response = await fetch(url, { headers, signal: AbortSignal.timeout(120_000) });
  if (missingIsNull && response.status === 404) return null;
  if (!response.ok) throw new Error(`GET ${url}: ${response.status} ${response.statusText}`);
  return response;
}

export async function json(url: string, missingIsNull = false): Promise<unknown> {
  const response = await request(url, missingIsNull);
  return response ? response.json() : null;
}

export function github(repo: string, endpoint = "", missingIsNull = false): Promise<unknown> {
  return json(`https://api.github.com/repos/${repo}${endpoint}`, missingIsNull);
}

export async function latestRelease(repo: string, optional = false): Promise<Release | null> {
  const value = await github(repo, "/releases/latest", optional);
  if (value === null && optional) return null;
  const raw = object(value, `${repo} release`);
  if (raw.draft !== false || raw.prerelease !== false || !Array.isArray(raw.assets)) {
    throw new Error(`Invalid stable release from ${repo}`);
  }
  return {
    tag: text(raw.tag_name, `${repo} release tag`, /^[A-Za-z0-9][A-Za-z0-9._-]*$/),
    assets: raw.assets,
  };
}

export async function commit(repo: string, ref: string): Promise<string> {
  const raw = object(await github(repo, `/commits/${encodeURIComponent(ref)}`), `${repo} commit`);
  return text(raw.sha, `${repo} commit SHA`, /^[a-f0-9]{40}$/);
}

export async function defaultCommit(repo: string): Promise<string> {
  const raw = object(await github(repo), `${repo} metadata`);
  return commit(repo, text(raw.default_branch, `${repo} default branch`));
}

export function sha256(value: unknown, label: string): string {
  const hash = text(value, label, /^sha256-[A-Za-z0-9+/]{43}=$/);
  if (`sha256-${Buffer.from(hash.slice(7), "base64").toString("base64")}` !== hash) {
    throw new Error(`Invalid SHA-256 encoding: ${label}`);
  }
  return hash;
}

export async function prefetch(
  root: string,
  url: string,
  unpack = false,
): Promise<{ hash: string; storePath: string }> {
  const command = [
    "nix",
    "--extra-experimental-features",
    "nix-command",
    "store",
    "prefetch-file",
    "--json",
    "--hash-type",
    "sha256",
  ];
  if (unpack) command.push("--unpack");
  command.push(url);
  const process = Bun.spawn(command, { cwd: root, stdout: "pipe", stderr: "inherit" });
  const [stdout, status] = await Promise.all([new Response(process.stdout).text(), process.exited]);
  if (status !== 0) throw new Error(`Nix prefetch failed (${status}): ${url}`);
  const raw = object(JSON.parse(stdout), "Nix prefetch output");
  return {
    hash: sha256(raw.hash, `${url} hash`),
    storePath: text(raw.storePath, "Nix store path", /^\//),
  };
}

export async function assetHash(
  root: string,
  repo: string,
  release: Release,
  name: string,
): Promise<string> {
  const matches = release.assets
    .map((asset) => object(asset, `${repo} release asset`))
    .filter((asset) => asset.name === name);
  if (matches.length !== 1)
    throw new Error(`Expected one ${repo} release asset ${name}, found ${matches.length}`);
  const asset = matches[0]!;
  const url = `https://github.com/${repo}/releases/download/${release.tag}/${name}`;
  if (asset.browser_download_url !== url || asset.state !== "uploaded")
    throw new Error(`Invalid release asset: ${name}`);
  let expected: string | undefined;
  if (asset.digest !== undefined && asset.digest !== null) {
    const digest = text(asset.digest, `${name} digest`, /^sha256:[a-fA-F0-9]{64}$/);
    expected = `sha256-${Buffer.from(digest.slice(7), "hex").toString("base64")}`;
  }
  const { hash } = await prefetch(root, url);
  if (expected && expected !== hash)
    throw new Error(`SHA-256 mismatch for ${name}: expected ${expected}, downloaded ${hash}`);
  return hash;
}

export async function verifyDownload(url: string, integrity: string): Promise<void> {
  const match = /^(sha256|sha512)-([A-Za-z0-9+/]+={0,2})$/.exec(integrity);
  if (!match) throw new Error(`Unsupported download integrity: ${integrity}`);
  const expected = Buffer.from(match[2]!, "base64");
  if (
    expected.length !== (match[1] === "sha512" ? 64 : 32) ||
    expected.toString("base64") !== match[2]
  ) {
    throw new Error(`Invalid download integrity: ${integrity}`);
  }
  const response = await request(url);
  if (!response?.body) throw new Error(`Empty download response: ${url}`);
  const hash = createHash(match[1]!);
  for await (const chunk of response.body) hash.update(chunk);
  if (!hash.digest().equals(expected)) throw new Error(`Download integrity mismatch: ${url}`);
}

export async function githubFile(repo: string, rev: string, path: string): Promise<string> {
  const endpoint = `/contents/${path.split("/").map(encodeURIComponent).join("/")}?ref=${rev}`;
  const raw = object(await github(repo, endpoint), `${repo}/${path} at ${rev}`);
  if (raw.type !== "file" || raw.encoding !== "base64")
    throw new Error(`Expected a file: ${repo}/${path} at ${rev}`);
  return Buffer.from(text(raw.content, `${repo}/${path} content`), "base64").toString("utf8");
}
