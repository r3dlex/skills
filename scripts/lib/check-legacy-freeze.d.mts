import type { Baseline } from "./freeze-types.mjs";
export declare function loadBaseline(root: string, path?: string): Baseline;
export declare function check(root: string, baseline?: Baseline, previous?: Baseline): string[];
export declare function main(argv: readonly string[]): number;
