import { spawnSync } from "node:child_process";

export interface ProcResult {
  status: number;
  stdout: Buffer;
  stderr: Buffer;
}

export function run(
  cmd: string,
  args: readonly string[],
  cwd: string,
  env?: NodeJS.ProcessEnv,
  stdin?: Buffer,
): ProcResult {
  const result = spawnSync(cmd, args, {
    cwd,
    env: env ?? process.env,
    input: stdin,
    encoding: "buffer",
  });
  const stdout = Buffer.isBuffer(result.stdout) ? result.stdout : Buffer.alloc(0);
  const stderr = Buffer.isBuffer(result.stderr) ? result.stderr : Buffer.alloc(0);
  if (result.error) {
    return { status: result.status ?? 127, stdout, stderr: Buffer.concat([stderr, Buffer.from(result.error.message)]) };
  }
  return { status: result.status ?? 127, stdout, stderr };
}

export function text(value: Buffer): string {
  return value.toString("utf8");
}
