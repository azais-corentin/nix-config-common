// build.stencil.so serves invite-only products (Tern) to a signed-in Stencil
// session only: unauthenticated downloads redirect to the login page. The
// session cookie is read from the default Firefox profile, so staying signed in
// there is the only credential these tasks need.

import { Database } from "bun:sqlite";
import { copyFileSync, existsSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { basename, isAbsolute, join } from "node:path";
import { command, compareVersions, object, sha256, text } from "./update.ts";

const origin = "https://build.stencil.so";
const cookieName = "__Secure-stencil_session";

export type StencilFile = { name: string; url: string; hash: string };
export type StencilBuild = { id: string; version: string; file: StencilFile };
/** A source.json pin: `url` is a build.stencil.so download, `hash` its flat SRI SHA-256. */
export type StencilPin = { version: string; url: string; hash: string };

// The shared firefox module keeps profiles under XDG; ~/.mozilla is the
// pre-migration location.
function firefoxProfile(): string {
  for (const base of [
    join(homedir(), ".config/mozilla/firefox"),
    join(homedir(), ".mozilla/firefox"),
  ]) {
    const ini = join(base, "profiles.ini");
    if (!existsSync(ini)) continue;
    const sections: Record<string, string>[] = [];
    for (const line of readFileSync(ini, "utf8").split("\n")) {
      const header = /^\[(.+)\]$/.exec(line.trim());
      if (header) sections.push({ "": header[1]! });
      else if (sections.length && line.includes("=")) {
        const [key, ...rest] = line.split("=");
        sections.at(-1)![key!.trim()] = rest.join("=").trim();
      }
    }
    // [Install…] Default= names the profile Firefox opens; older files only
    // flag a [Profile…] with Default=1.
    const installed = sections.find((section) => section[""]!.startsWith("Install"))?.Default;
    const flagged = sections.find(
      (section) => section[""]!.startsWith("Profile") && section.Default === "1",
    );
    const path = installed ?? flagged?.Path;
    if (!path) continue;
    return isAbsolute(path) ? path : join(base, path);
  }
  throw new Error("No default Firefox profile found under ~/.config/mozilla or ~/.mozilla");
}

let cachedCookie: string | undefined;

/** The Stencil session cookie from Firefox; throws when absent or expired. */
export function stencilCookie(): string {
  if (cachedCookie) return cachedCookie;
  const profile = firefoxProfile();
  const database = join(profile, "cookies.sqlite");
  if (!existsSync(database)) throw new Error(`No cookie database in ${profile}`);
  // A running Firefox locks the database and keeps recent writes in the WAL:
  // query a copy of both.
  const scratch = mkdtempSync(join(tmpdir(), "stencil-cookies-"));
  try {
    copyFileSync(database, join(scratch, "cookies.sqlite"));
    if (existsSync(`${database}-wal`))
      copyFileSync(`${database}-wal`, join(scratch, "cookies.sqlite-wal"));
    const db = new Database(join(scratch, "cookies.sqlite"));
    try {
      const row = db
        .query<{ value: string; expiry: number }, [string]>(
          "SELECT value, expiry FROM moz_cookies WHERE host = '.stencil.so' AND name = ? ORDER BY expiry DESC LIMIT 1",
        )
        .get(cookieName);
      // Current Firefox stores expiry in milliseconds, older releases in seconds.
      const expiresMs = row && (row.expiry > 1e12 ? row.expiry : row.expiry * 1000);
      if (!row || expiresMs! <= Date.now())
        throw new Error(`Sign in at ${origin} in Firefox (${basename(profile)} profile) first`);
      cachedCookie = row.value;
      return row.value;
    } finally {
      db.close();
    }
  } finally {
    rmSync(scratch, { recursive: true, force: true });
  }
}

async function stencilFetch(path: string): Promise<Response> {
  const url = new URL(path, origin);
  const response = await fetch(url, {
    headers: { cookie: `${cookieName}=${stencilCookie()}`, "user-agent": "nix-config-update" },
    redirect: "follow",
    signal: AbortSignal.timeout(600_000),
  });
  // A rejected session lands on auth.stencil.so's login page.
  if (new URL(response.url).hostname === "auth.stencil.so")
    throw new Error(`Stencil rejected the Firefox session: sign in at ${origin} again`);
  if (!response.ok) throw new Error(`GET ${url}: ${response.status} ${response.statusText}`);
  return response;
}

/** Latest stable build of `product` and its archive for `platform`/`arch`. */
export async function latestStencilBuild(
  product: string,
  platform: string,
  arch: string,
): Promise<StencilBuild> {
  const body = object(
    await (await stencilFetch(`/api/products/${product}/builds`)).json(),
    `${product} builds`,
  );
  if (!Array.isArray(body.builds)) throw new Error(`${product} builds: missing builds list`);
  const stable = body.builds
    .map((value) => object(value, `${product} build`))
    .filter((build) => build.channel === "stable" && build.published_at);
  if (!stable.length) throw new Error(`${product}: no published stable build`);
  const build = stable.reduce((best, next) =>
    compareVersions(text(next.version, `${product} version`), text(best.version, "")) > 0
      ? next
      : best,
  );
  const version = text(build.version, `${product} version`, /^\d+\.\d+\.\d+$/);
  if (!Array.isArray(build.files)) throw new Error(`${product} ${version}: missing files`);
  const file = build.files
    .map((value) => object(value, `${product} ${version} file`))
    .find(
      (entry) => entry.platform === platform && entry.arch === arch && entry.kind === "archive",
    );
  if (!file) throw new Error(`${product} ${version}: no ${platform} ${arch} archive`);
  const hex = text(file.sha256, `${file.name} sha256`, /^[0-9a-f]{64}$/);
  return {
    id: text(build.id, `${product} ${version} id`),
    version,
    file: {
      name: text(file.name, `${product} ${version} file name`, /^[\w.+-]+$/),
      url: new URL(text(file.url, `${file.name} url`, /^\/d\//), origin).href,
      hash: `sha256-${Buffer.from(hex, "hex").toString("base64")}`,
    },
  };
}

/** Parses a source.json pin, validating that it points at build.stencil.so. */
export function stencilPin(value: unknown, label: string): StencilPin {
  const pin = object(value, label);
  return {
    version: text(pin.version, `${label} version`, /^\d+\.\d+\.\d+$/),
    url: text(pin.url, `${label} url`, /^https:\/\/build\.stencil\.so\/d\/[\w./+-]+$/),
    hash: sha256(pin.hash, `${label} hash`),
  };
}

/**
 * Adds a pinned download to the Nix store under the fixed path `requireFile`
 * expects (flat SHA-256, named after the file). Returns false when it is
 * already there.
 */
export async function addStencilFile(root: string, pin: StencilPin): Promise<boolean> {
  const name = basename(new URL(pin.url).pathname);
  const fixed = (
    await command(root, ["nix-store", "--print-fixed-path", "sha256", pin.hash, name])
  ).stdout.trim();
  if ((await command(root, ["nix-store", "--check-validity", fixed], true)).exitCode === 0)
    return false;
  const scratch = mkdtempSync(join(tmpdir(), "stencil-"));
  try {
    const path = join(scratch, name);
    const response = await stencilFetch(pin.url);
    const hasher = new Bun.CryptoHasher("sha256");
    const writer = Bun.file(path).writer();
    for await (const chunk of response.body!) {
      hasher.update(chunk);
      writer.write(chunk);
    }
    await writer.end();
    const got = `sha256-${hasher.digest("base64")}`;
    if (got !== pin.hash) throw new Error(`${name}: got ${got}, pinned ${pin.hash}`);
    const added = (await command(root, ["nix-store", "--add-fixed", "sha256", path])).stdout.trim();
    if (added !== fixed) throw new Error(`${name}: added as ${added}, expected ${fixed}`);
    return true;
  } finally {
    rmSync(scratch, { recursive: true, force: true });
  }
}
