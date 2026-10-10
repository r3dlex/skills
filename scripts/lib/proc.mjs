import { spawnSync } from "node:child_process";
export function run(cmd, args, cwd, env) {
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
//# sourceMappingURL=proc.mjs.map