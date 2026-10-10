import { type FileStat, type Measured } from "./freeze-types.mjs";
export declare function compareStats(measured: readonly FileStat[], allowed: readonly FileStat[], kind: string): string[];
export declare function comparePaths(measured: readonly string[], allowed: readonly string[], kind: string): string[];
export declare function compareMeasured(measured: Measured, allowed: Measured): string[];
