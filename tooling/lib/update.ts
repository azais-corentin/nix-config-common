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
export type VersionedRelease = Release & { version: string; prerelease: boolean };
export type Commit = { rev: string; date: string };
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

// Runs a command in root and captures its output. Nix commands get the GitHub
// token as an access token so tarball fetches share the API rate limit.
export async function command(
  root: string,
  args: string[],
  allowFailure = false,
): Promise<{ stdout: string; stderr: string; exitCode: number }> {
  const env: NodeJS.ProcessEnv = { ...process.env, NO_COLOR: "1" };
  const token = process.env.GH_TOKEN || process.env.GITHUB_TOKEN;
  if (args[0] === "nix" && token) {
    if (/[\s#]/.test(token)) throw new Error("GitHub token contains invalid characters");
    env.NIX_CONFIG = `${env.NIX_CONFIG ?? ""}\nextra-access-tokens = github.com=${token}\n`;
  }
  const child = Bun.spawn(args, {
    cwd: root,
    stdin: "ignore",
    stdout: "pipe",
    stderr: "pipe",
    env,
  });
  const [stdout, stderr, exitCode] = await Promise.all([
    new Response(child.stdout).text(),
    new Response(child.stderr).text(),
    child.exited,
  ]);
  if (exitCode !== 0 && !allowFailure)
    throw new Error(`${args[0]} failed (${exitCode}):\n${stderr.trim() || stdout.trim()}`);
  return { stdout, stderr, exitCode };
}

// Unpacked prefetches are named `source`, like fetchFromGitHub's output (the
// NAR hash itself does not depend on the name).
export async function prefetch(
  root: string,
  url: string,
  unpack = false,
): Promise<{ hash: string; storePath: string }> {
  const args = [
    "nix",
    "--extra-experimental-features",
    "nix-command",
    "store",
    "prefetch-file",
    "--json",
    "--hash-type",
    "sha256",
  ];
  if (unpack) args.push("--unpack", "--name", "source");
  args.push(url);
  const { stdout } = await command(root, args);
  const raw = object(JSON.parse(stdout), "Nix prefetch output");
  return {
    hash: sha256(raw.hash, `${url} hash`),
    storePath: text(raw.storePath, "Nix store path", /^\//),
  };
}

export function prefetchSource(
  root: string,
  repo: string,
  ref: string,
  tag = false,
): Promise<{ hash: string; storePath: string }> {
  const revision = tag ? `refs/tags/${ref}` : ref;
  return prefetch(root, `https://github.com/${repo}/archive/${revision}.tar.gz`, true);
}

export function version(tag: string): string {
  const value = tag.replace(/^v/, "");
  if (!/^\d+\.\d+\.\d+(?:-[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?$/.test(value)) {
    throw new Error(`Unsupported release version: ${tag}`);
  }
  return value;
}

export function compareVersions(left: string, right: string): number {
  const [leftCore, ...leftPre] = version(left).split("-");
  const [rightCore, ...rightPre] = version(right).split("-");
  const a = leftCore!.split(".").map(Number);
  const b = rightCore!.split(".").map(Number);
  for (let i = 0; i < 3; i++) if (a[i] !== b[i]) return a[i]! - b[i]!;
  if (!leftPre.length || !rightPre.length)
    return Number(!leftPre.length) - Number(!rightPre.length);
  // Accept beta9/beta10 as well as SemVer's beta.9/beta.10 spelling.
  const x = leftPre.join("-").match(/[0-9]+|[A-Za-z]+/g)!;
  const y = rightPre.join("-").match(/[0-9]+|[A-Za-z]+/g)!;
  for (let i = 0; i < Math.max(x.length, y.length); i++) {
    if (x[i] === y[i]) continue;
    if (x[i] === undefined) return -1;
    if (y[i] === undefined) return 1;
    if (/^\d+$/.test(x[i]!) && /^\d+$/.test(y[i]!)) return Number(x[i]) - Number(y[i]);
    return x[i]! < y[i]! ? -1 : 1;
  }
  return 0;
}

// Parses a published (non-draft) GitHub release, stable or prerelease.
export function versionedRelease(value: unknown, repo: string): VersionedRelease {
  const raw = object(value, `${repo} release`);
  if (raw.draft !== false || typeof raw.prerelease !== "boolean" || !Array.isArray(raw.assets)) {
    throw new Error(`Invalid published release from ${repo}`);
  }
  const tag = text(raw.tag_name, `${repo} release tag`, /^[A-Za-z0-9][A-Za-z0-9._-]*$/);
  return { tag, version: version(tag), prerelease: raw.prerelease, assets: raw.assets };
}

export async function stableRelease(repo: string): Promise<VersionedRelease> {
  const result = versionedRelease(await github(repo, "/releases/latest"), repo);
  if (result.prerelease || result.version.includes("-"))
    throw new Error(`No stable release returned for ${repo}`);
  return result;
}

export function noDowngrade(current: string, next: string): void {
  if (compareVersions(next, current) < 0)
    throw new Error(`Refusing to downgrade ${current} to ${next}`);
}

export function releaseAsset(repo: string, release: Release, name: string): string {
  const assets = release.assets
    .map((value) => object(value, `${repo} release asset`))
    .filter((asset) => asset.name === name);
  if (assets.length !== 1)
    throw new Error(`Release ${repo}@${release.tag} must contain one ${name} asset`);
  const asset = assets[0]!;
  if (asset.state !== "uploaded" || typeof asset.size !== "number" || asset.size <= 0) {
    throw new Error(`Release asset is not available: ${repo}@${release.tag}/${name}`);
  }
  const url = text(asset.browser_download_url, `${name} download URL`);
  const expected = `https://github.com/${repo}/releases/download/${release.tag}/${name}`;
  if (url !== expected) throw new Error(`Unexpected release asset URL: ${url}`);
  return url;
}

// Latest default-branch commit, optionally the last one touching `file`.
export async function latestCommit(repo: string, file?: string): Promise<Commit> {
  const repository = object(await github(repo), `${repo} repository`);
  const branch = text(repository.default_branch, `${repo} default branch`);
  const query = new URLSearchParams({ sha: branch, per_page: "1" });
  if (file) query.set("path", file);
  const values = await github(repo, `/commits?${query}`);
  if (!Array.isArray(values) || values.length !== 1)
    throw new Error(`No upstream commit found for ${repo}${file ? `/${file}` : ""}`);
  const data = object(values[0], `${repo} commit`);
  const rev = text(data.sha, `${repo} commit SHA`, /^[a-f0-9]{40}$/);
  const details = object(data.commit, `${repo} commit details`);
  const committer = object(details.committer, `${repo} committer`);
  const timestamp = text(committer.date, `${repo} commit date`, /^\d{4}-\d{2}-\d{2}T/);
  if (Number.isNaN(Date.parse(timestamp))) throw new Error(`Invalid commit date from ${repo}`);
  return { rev, date: timestamp.slice(0, 10) };
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
