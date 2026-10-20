type Json = null | boolean | number | string | Json[] | {
    [key: string]: Json;
};
interface ContractConstants {
    allowed_classes: string[];
    argv_template: string[];
    consumers: string[];
    excluded_fields: string[];
    goal_id: string;
    permitted_sites: {
        [key: string]: string[];
    };
    plan_id: string;
    policy_path: string;
    projected_schemas: string[];
    refusal_schema: string;
    registry_path: string;
    required_targets: string[];
    schema: string;
    spec_path: string;
    spec_sha256_lineage: string;
    superseded_tool_sha256: string[];
}
export declare const CONTRACT: ContractConstants;
export declare function canonical(value: Json): string;
export declare function sha256Hex(bytes: Buffer): string;
export declare function main(argv: ReadonlyArray<string>): number;
export {};
