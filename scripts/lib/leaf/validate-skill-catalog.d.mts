interface SkillAudit {
    name: string;
    path: string;
    description_chars: number;
    description_status: string;
    body_lines: number;
    body_status: string;
    cross_skill_links: string;
    ai_sdlc_compatible: boolean;
    status: string;
}
interface AuditPayload {
    schema_version: string;
    policy: Record<string, string | number>;
    skill_count: number;
    warnings: string[];
    failures: string[];
    skills: SkillAudit[];
    status: string;
}
export declare function audit(root: string): AuditPayload;
export declare function main(argv: readonly string[]): number;
export {};
