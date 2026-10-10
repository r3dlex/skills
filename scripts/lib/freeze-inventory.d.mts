import { type Baseline, type LedgerClass, type LedgerEntry } from "./freeze-types.mjs";
export declare function excluded(path: string, patterns: readonly string[]): boolean;
export declare function embedsPython(text: string): boolean;
export declare function tracked(root: string): string[];
export declare function inventoryPaths(root: string, baseline: Baseline): string[];
export declare function entryProblems(entry: LedgerEntry): string[];
export declare function compareInventory(present: ReadonlySet<string>, entries: readonly LedgerEntry[]): string[];
export declare function classOf(entries: readonly LedgerEntry[], path: string): LedgerClass | undefined;
export declare function classChanges(previous: readonly LedgerEntry[], current: readonly LedgerEntry[], present: ReadonlySet<string>): string[];
