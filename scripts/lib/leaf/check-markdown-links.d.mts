import { type CatalogPayload, type SkillEntry } from "./catalog-model.mjs";
export declare function logicalTarget(root: string, sourceName: string, target: string, byName: ReadonlyMap<string, SkillEntry>): {
    path: string;
    installed: boolean;
};
export declare function failures(root: string, files: readonly string[], catalog: CatalogPayload): string[];
export declare function main(argv: readonly string[], fallback?: string): number;
