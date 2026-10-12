// Uniform output for every update* task: one header line with counts, then
// only the rows that changed, with versions coloured like nvd/nh (shared
// prefix yellow, old suffix red, new suffix green).

/** One reported item. No `from` = added, no `to` = removed, equal = same version. */
export type Change = { name: string; from?: string; to?: string; note?: string };
export type Row = Change & { depth?: number; error?: string };
export type Counts = { updated: number; current: number; failed?: number; skipped?: number };

const color = !process.env.NO_COLOR && (!!process.env.FORCE_COLOR || !!process.stdout.isTTY);
const sgr = (code: string) => (value: string) =>
  color && value ? `\x1b[${code}m${value}\x1b[0m` : value;
const bold = sgr("1");
const dim = sgr("2");
const red = sgr("31");
const green = sgr("32");
const yellow = sgr("33");

const progress = !!process.stderr.isTTY;

/** Shows a transient status line on an interactive stderr; `status()` clears it. */
export function status(message?: string): void {
  if (!progress) return;
  process.stderr.write(`\r\x1b[2K${message ? dim(message) : ""}`);
}

// Full commit hashes read as noise in a summary; nix and git both show 7.
function display(version: string): string {
  return /^[0-9a-f]{40}$/.test(version) ? version.slice(0, 7) : version;
}

/** Splits two versions after the last separator they share, as nvd does. */
function versionDiff(from: string, to: string): string {
  let shared = 0;
  while (shared < from.length && from[shared] === to[shared]) shared++;
  while (shared > 0 && !/[.\-_+~: ]/.test(from[shared - 1]!)) shared--;
  const prefix = yellow(from.slice(0, shared));
  return `${prefix}${red(from.slice(shared))} → ${prefix}${green(to.slice(shared))}`;
}

function value(row: Row): string {
  if (row.error) {
    const [first, ...rest] = row.error.split("\n");
    return red(`✗ ${first}`) + rest.map((line) => `\n      ${dim(line)}`).join("");
  }
  const from = row.from === undefined ? undefined : display(row.from);
  const to = row.to === undefined ? undefined : display(row.to);
  const text =
    from === undefined
      ? green(`+ ${to}`)
      : to === undefined
        ? red(`− ${from}`)
        : from === to
          ? yellow(from)
          : versionDiff(from, to);
  return row.note ? `${text}  ${dim(`(${row.note})`)}` : text;
}

/** Prints a task section: `task  N updated, N current` then the changed rows. */
export function report(task: string, counts: Counts, rows: Row[]): void {
  status();
  const summary = [
    counts.updated ? green(`${counts.updated} updated`) : "",
    counts.current || !(counts.updated || counts.failed) ? dim(`${counts.current} current`) : "",
    counts.failed ? red(`${counts.failed} failed`) : "",
    counts.skipped ? dim(`${counts.skipped} skipped`) : "",
  ].filter(Boolean);
  const labels = rows.map((row) => `${"  ".repeat((row.depth ?? 0) + 1)}${row.name}`);
  const width = Math.max(0, ...labels.map((label) => label.length));
  const lines = [`${bold(task)}  ${summary.join(dim(", "))}`];
  for (const [index, row] of rows.entries()) {
    lines.push(`${labels[index]!.padEnd(width)}  ${value(row)}`);
  }
  console.log(lines.join("\n"));
}
