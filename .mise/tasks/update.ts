#!/usr/bin/env bun
//MISE description="Update all managed pins in this repository"

if (Bun.argv.length > 2) {
  console.error("update accepts no arguments. Use update:inputs or a target-specific update task.");
  process.exit(1);
}
const root = process.env.MISE_PROJECT_ROOT;
if (!root) {
  console.error("Run this task through mise in the repository.");
  process.exit(1);
}
for (const category of ["inputs", "apps", "skills"]) {
  const child = Bun.spawn(["mise", "run", `update:${category}`], {
    cwd: root,
    stdin: "inherit",
    stdout: "inherit",
    stderr: "inherit",
  });
  const status = await child.exited;
  if (status !== 0) process.exit(status);
}
