export declare const SUPPORTED_MAJOR = 26;
export declare const NODE_UNAVAILABLE = "node_unavailable";
export declare const NODE_VERSION_UNSUPPORTED = "node_version_unsupported";
export declare const EXIT_NODE_UNAVAILABLE = 127;
export declare const EXIT_NODE_VERSION_UNSUPPORTED = 126;
export declare function nodeMajor(version: string): number;
export declare function nodeVersionStatus(version: string): "ok" | typeof NODE_VERSION_UNSUPPORTED;
export declare function assertNodeVersion(version?: string): void;
