export interface ParityHit {
    file: string;
    line: number;
    construct: string;
}
export declare function scanBody(file: string, text: string, denylist: RegExp, marker: string): {
    missing: boolean;
    hits: ParityHit[];
    pass: boolean;
};
export declare function checkFiles(files: readonly string[], denylist: RegExp, marker: string, usage: string, label: string): number;
export declare function codexMain(argv: readonly string[]): number;
export declare function opencodeMain(argv: readonly string[]): number;
