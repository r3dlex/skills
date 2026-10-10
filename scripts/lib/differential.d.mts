export interface Anchor {
    commit: string;
    path: string;
    blob: string;
    sha256: string;
}
export interface Site {
    stream: "stdout" | "stderr";
    prefix?: string;
    jsonPointer?: string;
}
export interface NormalizationClass {
    name: string;
    mask: string;
    sites: Site[];
}
export interface MaskSpan {
    name: string;
    stream: "stdout" | "stderr";
    start: number;
    end: number;
}
export interface CorpusCase {
    id: string;
    args: string[];
    stdin?: string;
    files?: Record<string, string>;
}
export interface Corpus {
    anchor: Anchor;
    candidate: string[];
    cases: CorpusCase[];
    normalizations?: NormalizationClass[];
    applyMasks?: MaskSpan[];
}
export declare class DifferentialError extends Error {
    constructor(message: string);
}
export declare function materialize(root: string, anchor: Anchor): Buffer;
export declare function normalize(text: string, classes: readonly NormalizationClass[], stream: "stdout" | "stderr"): string;
export declare function outputsEqual(left: ProcResult, right: ProcResult): boolean;
export interface ProcResult {
    status: number;
    stdout: string;
    stderr: string;
    files: Record<string, string>;
}
export declare function compareCase(reference: ProcResult, candidate: ProcResult, corpus: Corpus): void;
export declare function runAnchored(root: string, corpus: Corpus): void;
export declare function main(argv: readonly string[]): number;
