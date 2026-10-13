export interface InstallArgs {
    includes: string[];
    rest: string[];
}
export declare function parseCatalogArgs(argv: readonly string[]): InstallArgs | number;
export declare function catalogRows(root: string, host: string, includes: readonly string[], skill?: string): {
    rows: string;
    projectionText: string;
};
export declare function writeProjection(dir: string, name: string, text: string): void;
export declare function failCatalog(error: unknown): number;
