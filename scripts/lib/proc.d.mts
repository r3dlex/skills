export interface ProcResult {
    status: number;
    stdout: Buffer;
    stderr: Buffer;
}
export declare function run(cmd: string, args: readonly string[], cwd: string, env?: NodeJS.ProcessEnv, stdin?: Buffer): ProcResult;
export declare function text(value: Buffer): string;
