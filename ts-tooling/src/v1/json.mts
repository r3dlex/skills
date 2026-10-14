import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";

export class Invalid extends Error {
  readonly runtimeKind: string;

  constructor(message: string, runtimeKind = "") {
    super(message);
    this.name = "Invalid";
    this.runtimeKind = runtimeKind;
  }
}

export const VERSION = "readiness-contract/1";
export const ID = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;
export const SHA = /^[a-f0-9]{64}$/;
export const REVISION = /^[a-f0-9]{40}$/;
export interface Args {
  root?: string;
  handoff?: string | null;
  goal_id?: string[] | null;
  goal?: string | null;
  context?: string | null;
  execution_record?: string | null;
  execution_root?: string | null;
  worktree_root?: string | null;
  base_commit?: string | null;
  bundle?: string | null;
  legacy?: string | null;
  stage?: string;
  operation?: string;
}

type Dict = Record<string, unknown>;

function truthy(value: unknown): boolean {
  if (value == null || value === false || value === 0 || value === "") {
    return false;
  }
  if (Array.isArray(value)) {
    return value.length > 0;
  }
  return typeof value === "object" ? Object.keys(value).length > 0 : true;
}

export function require(value: unknown, message: string): void {
  if (!truthy(value)) {
    throw new Invalid(message);
  }
}

export function string(value: unknown): boolean {
  return typeof value === "string" && value.trim() !== "";
}

function isDict(value: unknown): value is Dict {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function quote(value: string): string {
  let out = "\"";
  for (const ch of value) {
    out += escaped(ch);
  }
  return out + "\"";
}

function escaped(ch: string): string {
  if (ch === "\"") {
    return "\\\"";
  }
  if (ch === "\\") {
    return "\\\\";
  }
  if (ch === "\n") {
    return "\\n";
  }
  if (ch === "\r") {
    return "\\r";
  }
  if (ch === "\t") {
    return "\\t";
  }
  let out = "";
  for (let index = 0; index < ch.length; index += 1) {
    const code = ch.charCodeAt(index);
    const unit = ch[index] ?? "";
    out += code < 0x20 || code > 0x7e ? `\\u${code.toString(16).padStart(4, "0")}` : unit;
  }
  return out;
}

function numberText(value: number): string {
  if (!Number.isFinite(value)) {
    throw new TypeError("Out of range float values are not JSON compliant");
  }
  return Number.isInteger(value) ? String(value) : JSON.stringify(value);
}

function pad(level: number): string {
  return "  ".repeat(level);
}

function encode(value: unknown, sort: boolean, indent: number | null, level: number, tight: boolean): string {
  if (value === null) {
    return "null";
  }
  if (typeof value === "boolean" || typeof value === "number") {
    return typeof value === "boolean" ? String(value) : numberText(value);
  }
  if (typeof value === "string") {
    return quote(value);
  }
  if (Array.isArray(value)) {
    return encodeList(value, sort, indent, level, tight);
  }
  if (isDict(value)) {
    return encodeObject(value, sort, indent, level, tight);
  }
  throw new TypeError(`Object of type ${typeof value} is not JSON serializable`);
}

function encodeList(value: unknown[], sort: boolean, indent: number | null, level: number, tight: boolean): string {
  if (value.length === 0) {
    return "[]";
  }
  if (indent === null) {
    const sep = tight ? "," : ", ";
    return `[${value.map((item) => encode(item, sort, indent, level, tight)).join(sep)}]`;
  }
  const body = value.map((item) => `${pad(level + 1)}${encode(item, sort, indent, level + 1, tight)}`).join(",\n");
  return `[\n${body}\n${pad(level)}]`;
}

function encodeObject(value: Dict, sort: boolean, indent: number | null, level: number, tight: boolean): string {
  const keys = sort ? Object.keys(value).sort() : Object.keys(value);
  if (keys.length === 0) {
    return "{}";
  }
  const colon = tight && indent === null ? ":" : ": ";
  const parts = keys.map((key) => `${quote(key)}${colon}${encode(value[key], sort, indent, level + 1, tight)}`);
  if (indent === null) {
    return `{${parts.join(tight ? "," : ", ")}}`;
  }
  return `{\n${parts.map((part) => `${pad(level + 1)}${part}`).join(",\n")}\n${pad(level)}}`;
}

export function dumps(value: unknown, indent: number | null = null, sort = false, tight = false): string {
  return encode(value, sort, indent, 0, tight);
}

export function canonical(value: unknown): string {
  return createHash("sha256").update(dumps(value, null, true, true)).digest("hex");
}

export function digest(path: string): string {
  return createHash("sha256").update(readFileSync(path)).digest("hex");
}

export function read(path: string): unknown {
  return JSON.parse(readFileSync(path, "utf8"));
}
