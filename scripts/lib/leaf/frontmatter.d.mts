export declare function frontmatterName(path: string): string;
export declare function frontmatter(path: string): {
    meta: Record<string, string>;
    body: string[];
};
