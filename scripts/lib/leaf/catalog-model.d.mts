export declare const LIFECYCLES: Set<string>;
export declare const HOSTS: Set<string>;
export declare const DEFAULT_LIFECYCLES: Set<string>;
export declare class CatalogError extends Error {
    constructor(message: string);
}
export interface SkillEntry {
    name: string;
    source_path: string;
    owner_phase: string;
    applies_to_phases: string[];
    lifecycle: string;
    supported_hosts: string[];
}
export interface CatalogPayload {
    schema_version: string;
    phases: string[];
    skills: SkillEntry[];
}
export declare function loadCatalog(root: string): CatalogPayload;
export declare function select(payload: CatalogPayload, host: string, included?: ReadonlySet<string>, name?: string): SkillEntry[];
export declare function projection(payload: CatalogPayload, entries: readonly SkillEntry[]): {
    schema_version: string;
    skills: SkillEntry[];
};
export declare function catalogPath(root: string, source: string): string;
