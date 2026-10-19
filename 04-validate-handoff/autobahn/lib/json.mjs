import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
export class Invalid extends Error {
    runtimeKind;
    constructor(message, runtimeKind = "") {
        super(message);
        this.name = "Invalid";
        this.runtimeKind = runtimeKind;
    }
}
export const VERSION = "readiness-contract/1";
export const ID = /^[A-Za-z0-9][A-Za-z0-9._-]*$(?![\s\S])/;
export const SHA = /^[a-f0-9]{64}$(?![\s\S])/;
export const REVISION = /^[a-f0-9]{40}$(?![\s\S])/;
// JSON's numeric token type is part of Python's canonical bytes (80 != 80.0).
// Keep floats and unbounded integers losslessly at the decoding boundary.
export class Float {
    value;
    constructor(value) {
        this.value = value;
    }
    valueOf() { return this.value; }
}
export function numeric(value) {
    return typeof value === "number" || typeof value === "bigint" || value instanceof Float;
}
export function compare(left, right) {
    const a = Array.from(left, (ch) => ch.codePointAt(0) ?? 0);
    const b = Array.from(right, (ch) => ch.codePointAt(0) ?? 0);
    for (let index = 0; index < Math.min(a.length, b.length); index += 1) {
        if (a[index] !== b[index])
            return (a[index] ?? 0) - (b[index] ?? 0);
    }
    return a.length - b.length;
}
export function equal(left, right) {
    if (left === right)
        return true;
    if (numeric(left) || typeof left === "boolean") {
        return numericEqual(left, right);
    }
    if (Array.isArray(left))
        return Array.isArray(right) && left.length === right.length && left.every((value, index) => equal(value, right[index]));
    if (isDict(left))
        return isDict(right) && Object.keys(left).length === Object.keys(right).length && Object.keys(left).every((key) => Object.hasOwn(right, key) && equal(left[key], right[key]));
    return left === right;
}
function numericEqual(left, right) {
    if (!numeric(right) && typeof right !== "boolean")
        return false;
    const a = left instanceof Float ? left.value : left;
    const b = right instanceof Float ? right.value : right;
    if (typeof a === "bigint")
        return integerEqual(a, b);
    if (typeof b === "bigint")
        return integerEqual(b, a);
    return Number(a) === Number(b);
}
function integerEqual(integer, value) {
    if (typeof value === "bigint")
        return integer === value;
    return Number.isInteger(Number(value)) && integer === BigInt(Number(value));
}
function truthy(value) {
    if (value == null || value === false || value === 0 || value === "") {
        return false;
    }
    if (Array.isArray(value)) {
        return value.length > 0;
    }
    return typeof value === "object" ? Object.keys(value).length > 0 : true;
}
export function require(value, message) {
    if (!truthy(value)) {
        throw new Invalid(message);
    }
}
export function string(value) {
    return typeof value === "string" && strip(value) !== "";
}
export function whitespace(ch) {
    return /\p{White_Space}/u.test(ch) || [28, 29, 30, 31].includes(ch.charCodeAt(0));
}
export function strip(value) {
    let start = 0, end = value.length;
    while (start < end && whitespace(value[start] ?? ""))
        start += 1;
    while (end > start && whitespace(value[end - 1] ?? ""))
        end -= 1;
    return value.slice(start, end);
}
export function redactText(value) {
    const pattern = /https?:\/\//g;
    let output = "", previous = 0;
    for (let match = pattern.exec(value); match !== null; match = pattern.exec(value)) {
        let end = pattern.lastIndex;
        while (end < value.length && !whitespace(value[end] ?? ""))
            end += 1;
        if (end === pattern.lastIndex)
            continue;
        output += value.slice(previous, match.index) + "[redacted-url]";
        previous = end;
        pattern.lastIndex = end;
    }
    return output + value.slice(previous);
}
export function typeName(value) {
    if (value == null)
        return "NoneType";
    if (Array.isArray(value))
        return "list";
    if (value instanceof Float)
        return "float";
    const names = { object: "dict", boolean: "bool", number: "int", bigint: "int", string: "str" };
    return names[typeof value] ?? typeof value;
}
export function match(pattern, value) {
    if (typeof value !== "string")
        throw new TypeError("expected string or bytes-like object, got '" + typeName(value) + "'");
    return pattern.test(value);
}
export function hashable(value) {
    if (isDict(value) || Array.isArray(value))
        throw new TypeError("unhashable type: '" + typeName(value) + "'");
}
export function pyKey(value) {
    hashable(value);
    if (value == null)
        return "none";
    if (typeof value === "string")
        return "str:" + value;
    if (typeof value === "boolean")
        return value ? "int:1" : "int:0";
    if (typeof value === "bigint")
        return "int:" + String(value);
    const number = Number(value);
    return Number.isInteger(number) ? "int:" + String(BigInt(number)) : "float:" + String(number);
}
export function pyStr(value) {
    if (value == null)
        return "None";
    if (typeof value === "boolean")
        return value ? "True" : "False";
    if (typeof value === "string")
        return value;
    if (value instanceof Float && !Number.isFinite(value.value))
        return String(value.value).toLowerCase().replace("infinity", "inf");
    if (Array.isArray(value))
        return "[" + value.map(pyLiteral).join(", ") + "]";
    if (isDict(value))
        return "{" + Object.entries(value).map(([key, child]) => pyLiteral(key) + ": " + pyLiteral(child)).join(", ") + "}";
    return dumps(value);
}
function pyLiteral(value) {
    if (typeof value === "string")
        return pyRepr(value);
    return pyStr(value);
}
export function pyRepr(value) {
    const quote = value.includes("'") && !value.includes('"') ? '"' : "'";
    return quote + Array.from(value, (ch) => reprCharacter(ch, quote)).join("") + quote;
}
function reprCharacter(ch, quote) {
    if (ch === quote || ch === "\\")
        return "\\" + ch;
    const special = { "\n": "\\n", "\r": "\\r", "\t": "\\t" };
    if (Object.hasOwn(special, ch))
        return special[ch] ?? "";
    if (ch !== " " && /[\p{C}\p{Z}]/u.test(ch))
        return reprCode(ch.codePointAt(0) ?? 0);
    return ch;
}
function reprCode(code) {
    if (code <= 255)
        return "\\x" + code.toString(16).padStart(2, "0");
    return (code <= 65535 ? "\\u" : "\\U") + code.toString(16).padStart(code <= 65535 ? 4 : 8, "0");
}
function isDict(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value) && !(value instanceof Float);
}
function quote(value) {
    let out = "\"";
    for (const ch of value) {
        out += escaped(ch);
    }
    return out + "\"";
}
function escaped(ch) {
    const special = { '"': '\\"', "\\": "\\\\", "\n": "\\n", "\r": "\\r", "\t": "\\t", "\b": "\\b", "\f": "\\f" };
    if (Object.hasOwn(special, ch))
        return special[ch] ?? "";
    let out = "";
    for (let index = 0; index < ch.length; index += 1) {
        const code = ch.charCodeAt(index);
        const unit = ch[index] ?? "";
        out += code < 0x20 || code > 0x7e ? `\\u${code.toString(16).padStart(4, "0")}` : unit;
    }
    return out;
}
function numberText(value) {
    if (Number.isNaN(value))
        return "NaN";
    if (!Number.isFinite(value))
        return value < 0 ? "-Infinity" : "Infinity";
    return String(value);
}
function floatText(value) {
    if (!Number.isFinite(value))
        return numberText(value);
    if (Object.is(value, -0))
        return "-0.0";
    const [mantissa = "0", exponent = "0"] = value.toExponential().split("e");
    const power = Number(exponent);
    if (power < -4 || power >= 16)
        return mantissa + "e" + (power < 0 ? "-" : "+") + String(Math.abs(power)).padStart(2, "0");
    const plain = String(value);
    return plain.includes(".") ? plain : plain + ".0";
}
function pad(level) {
    return "  ".repeat(level);
}
function scalar(value) {
    if (value === null) {
        return "null";
    }
    if (value instanceof Float)
        return floatText(value.value);
    if (typeof value === "bigint")
        return String(value);
    if (typeof value === "boolean" || typeof value === "number") {
        return typeof value === "boolean" ? String(value) : numberText(value);
    }
    if (typeof value === "string") {
        return quote(value);
    }
    if (Array.isArray(value) || isDict(value))
        return null;
    throw new TypeError(`Object of type ${typeof value} is not JSON serializable`);
}
function collection(value, level, indent, sort, tight) {
    const list = Array.isArray(value);
    const keys = Object.keys(value);
    if (!list && sort)
        keys.sort(compare);
    const open = list ? "[" : "{", close = list ? "]" : "}";
    if (keys.length === 0)
        return [open + close];
    const parts = [open, ...elements(value, keys, level, indent, tight)];
    if (indent !== null)
        parts.push("\n" + pad(level));
    parts.push(close);
    return parts;
}
function elements(value, keys, level, indent, tight) {
    const parts = [];
    const separator = tight ? "," : ", ";
    const colon = tight && indent === null ? ":" : ": ";
    for (const [index, key] of keys.entries()) {
        if (index > 0)
            parts.push(indent === null ? separator : ",");
        if (indent !== null)
            parts.push("\n" + pad(level + 1));
        if (!Array.isArray(value))
            parts.push(quote(key) + colon);
        parts.push({ value: value[key], level: level + 1 });
    }
    return parts;
}
export function dumps(value, indent = null, sort = false, tight = false) {
    const pending = [{ value, level: 0 }];
    const output = [];
    while (pending.length > 0) {
        const next = pending.pop();
        if (typeof next === "string") {
            output.push(next);
            continue;
        }
        const atom = scalar(next.value);
        if (atom !== null) {
            output.push(atom);
            continue;
        }
        const parts = collection(next.value, next.level, indent, sort, tight);
        for (let index = parts.length - 1; index >= 0; index -= 1)
            pending.push(parts[index]);
    }
    return output.join("");
}
export function canonical(value) {
    return createHash("sha256").update(dumps(value, null, true, true)).digest("hex");
}
export function digest(path) {
    return createHash("sha256").update(readFileSync(path)).digest("hex");
}
export function read(path) {
    return parse(new TextDecoder("utf-8", { fatal: true, ignoreBOM: true }).decode(readFileSync(path)));
}
const NAN = new Float(NaN);
class Decoder {
    raw;
    index = 0;
    pending = [];
    constructor(raw) {
        this.raw = raw;
    }
    whitespace() {
        while (/[ \t\r\n]/.test(this.raw[this.index] ?? "") && this.index < this.raw.length)
            this.index += 1;
    }
    invalid() { throw new SyntaxError("Expecting value: line 1 column " + (this.index + 1)); }
    quoted() {
        const start = this.index++;
        while (this.index < this.raw.length) {
            const next = this.raw[this.index++];
            if (next === "\\")
                this.index += 1;
            else if (next === '"')
                return JSON.parse(this.raw.slice(start, this.index));
        }
        return this.invalid();
    }
    member(frame) {
        this.whitespace();
        if (this.raw[this.index] !== '"')
            this.invalid();
        const key = this.quoted();
        this.whitespace();
        if (this.raw[this.index++] !== ":")
            this.invalid();
        frame.pairs.push([key, this.token()]);
    }
    collection(object) {
        this.index += 1;
        if (object) {
            const result = Object.create(null);
            this.pending.push({ object: result, pairs: [], next: false });
            return result;
        }
        const list = [];
        this.pending.push({ list, next: false });
        return list;
    }
    finish(frame) {
        this.pending.pop();
        if ("object" in frame) {
            for (const [key, value] of frame.pairs) {
                require(!Object.hasOwn(frame.object, key), "duplicate_key:" + key);
                frame.object[key] = value;
            }
        }
    }
    item(frame) {
        this.whitespace();
        const close = "object" in frame ? "}" : "]";
        if (this.raw[this.index] === close) {
            this.index += 1;
            this.finish(frame);
            return;
        }
        if (frame.next) {
            if (this.raw[this.index++] !== ",")
                this.invalid();
            this.whitespace();
        }
        frame.next = true;
        if ("object" in frame)
            this.member(frame);
        else
            frame.list.push(this.token());
    }
    literal() {
        const match = /^(?:true|false|null|-?Infinity|NaN|-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?)/.exec(this.raw.slice(this.index));
        if (!match)
            return this.invalid();
        const literal = match[0];
        this.index += literal.length;
        if (["true", "false", "null"].includes(literal))
            return JSON.parse(literal);
        if (literal === "NaN")
            return NAN;
        if (/[.eE]|Infinity/.test(literal))
            return new Float(Number(literal));
        const integer = BigInt(literal);
        return integer <= BigInt(Number.MAX_SAFE_INTEGER) && integer >= BigInt(Number.MIN_SAFE_INTEGER) ? Number(integer) : integer;
    }
    token() {
        this.whitespace();
        switch (this.raw[this.index]) {
            case '"': return this.quoted();
            case "{": return this.collection(true);
            case "[": return this.collection(false);
            default: return this.literal();
        }
    }
    decode() {
        const result = this.token();
        while (this.pending.length > 0)
            this.item(this.pending[this.pending.length - 1]);
        this.whitespace();
        if (this.index !== this.raw.length)
            this.invalid();
        return result;
    }
}
export function parse(raw) { return new Decoder(raw).decode(); }
