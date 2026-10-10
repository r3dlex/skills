export interface SampleDeps {
    read: (path: string) => string;
    writeOut: (text: string) => void;
    writeErr: (text: string) => void;
}
export declare function productionDeps(): SampleDeps;
export declare function main(argv: readonly string[], deps?: SampleDeps): number;
