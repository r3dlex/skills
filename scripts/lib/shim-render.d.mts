export declare const NODE_FLAGS: readonly ["--disable-proto=throw"];
export declare const PYTHON_FLAGS: readonly ["-I", "-B"];
export declare const BASE_ALLOW: readonly ["PATH", "HOME", "LANG", "LC_ALL", "TMPDIR"];
export declare class ShimRenderError extends Error {
    constructor(message: string);
}
export declare function assertAllowNames(names: readonly string[]): void;
export declare function renderBash(entrypoint: string, names: readonly string[]): string;
export declare function renderPython(entrypoint: string, names: readonly string[]): string;
export declare function main(argv: readonly string[]): number;
