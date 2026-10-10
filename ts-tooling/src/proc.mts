import { spawnSync } from "node:child_process";

export interface ProcResult {
  status: number;
  stdout: string;
  stderr: string;
}

export function run(cmd: string, args: readonly string[], cwd: string, env?: NodeJS.ProcessEnv): ProcResult {
  const result = spawnSync(cmd, args, {
    cwd,
    env: env ?? process.env,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  });
  return {
    status: result.status ?? 127,
    stdout: result.stdout ?? "",
    stderr: result.error ? `${result.stderr ?? ""}${result.error.message}` : (result.stderr ?? ""),
  };
}
