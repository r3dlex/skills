import { type FileStat, type Measured } from "./freeze-types.mjs";
export declare function measureC901(root: string, files: readonly string[]): FileStat[];
export declare function measureXenon(root: string, files: readonly string[]): {
    blocks: FileStat[];
    averageOk: boolean;
};
export declare function measureMypy(root: string, files: readonly string[]): FileStat[];
export declare function measureShellcheck(root: string, files: readonly string[]): FileStat[];
export declare function measureShfmt(root: string, files: readonly string[]): string[];
export declare function measureBashN(root: string, files: readonly string[]): string[];
export declare function measure(root: string, py: readonly string[], sh: readonly string[]): Measured;
