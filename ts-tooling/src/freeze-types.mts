export const CLASSES = [
  "eligible",
  "compat-shim",
  "scaffold-template",
  "test-wrapper",
  "kept-language",
] as const;

export type LedgerClass = (typeof CLASSES)[number];

export const OWNERS = [
  "e6-sk-01-py-leaf",
  "e6-sk-02-v1-port",
  "e6-sk-03-py-lib",
  "e6-sk-04-sh-drivers",
  "e6-sk-05-test-harness",
] as const;

export interface LedgerEntry {
  path: string;
  class: LedgerClass;
  owner?: string;
  in_flight?: number;
  consumers?: string[];
  entrypoint?: string;
  allow?: string[];
}

export interface FileStat {
  path: string;
  violations: number;
  max?: number;
  worst?: string;
  errors?: number;
  blocks?: number;
}

export interface Measured {
  c901: FileStat[];
  xenon: FileStat[];
  mypy: FileStat[];
  shellcheck: FileStat[];
  shfmt: string[];
  bash_n: string[];
  xenon_average_ok: boolean;
}

export interface Baseline {
  schema: "legacy-freeze-baseline/1";
  base: string;
  classes: LedgerClass[];
  excludes: string[];
  infrastructure_shells: string[];
  entries: LedgerEntry[];
  measured: Measured;
}

export const RANK: Record<string, number> = { A: 0, B: 1, C: 2, D: 3, E: 4, F: 5 };
