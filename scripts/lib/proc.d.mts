export interface ProcResult {
    status: number;
    stdout: string;
    stderr: string;
}
export declare function run(cmd: string, args: readonly string[], cwd: string, env?: NodeJS.ProcessEnv): ProcResult;
