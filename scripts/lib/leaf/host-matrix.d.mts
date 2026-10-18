export declare const HOST_MATRIX_FILE = "host-matrix.json";
export declare const HOST_MATRIX_SCHEMA = "host-matrix/1";
export declare const QUARANTINED: Set<string>;
export declare class HostMatrixError extends Error {
    constructor(reason: string);
}
export interface HostConsumer {
    installer: string | null;
    also?: string[];
    delivery?: string;
}
export interface HostMatrix {
    schema: string;
    payload_hosts: string[];
    aliases: Record<string, string>;
    consumers: Record<string, HostConsumer>;
    excluded: Record<string, string>;
}
export declare function validateHostMatrix(raw: unknown, skillNames: ReadonlySet<string>): HostMatrix;
export declare function hostMatrixPath(root: string): string;
export declare function loadHostMatrix(root: string, skillNames: ReadonlySet<string>): HostMatrix | undefined;
export declare function resolveHost(matrix: HostMatrix | undefined, host: string): string;
