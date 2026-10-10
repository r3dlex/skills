import { spawnSync } from "node:child_process";
export function run(cmd, args, cwd, env, stdin) {
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
export function text(value) {
    return value.toString("utf8");
}
//# sourceMappingURL=proc.mjs.map