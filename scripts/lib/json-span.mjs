function atEnd(cursor) {
    return cursor.i >= cursor.text.length;
}
function isSpace(char) {
    return char === " " || char === "\n" || char === "\r" || char === "\t";
}
function skip(cursor) {
    while (!atEnd(cursor) && isSpace(cursor.text[cursor.i])) {
        cursor.i += 1;
    }
}
function malformed() {
    throw new Error("mask site not located");
}
function readString(cursor) {
    if (cursor.text[cursor.i] !== "\"") {
        malformed();
    }
    cursor.i += 1;
    let value = "";
    while (!atEnd(cursor) && cursor.text[cursor.i] !== "\"") {
        const char = cursor.text[cursor.i] ?? "";
        cursor.i += 1;
        value += char === "\\" ? readEscape(cursor) : char;
    }
    if (cursor.text[cursor.i] !== "\"") {
        malformed();
    }
    cursor.i += 1;
    return value;
}
const SIMPLE_ESCAPES = {
    "\"": "\"",
    "\\": "\\",
    "/": "/",
    b: "\b",
    f: "\f",
    n: "\n",
    r: "\r",
    t: "\t",
};
function isHex(char) {
    return char !== undefined && "0123456789abcdefABCDEF".includes(char);
}
function readHex4(cursor) {
    let hex = "";
    for (let i = 0; i < 4; i += 1) {
        const char = cursor.text[cursor.i];
        if (!isHex(char)) {
            malformed();
        }
        hex += char;
        cursor.i += 1;
    }
    return Number.parseInt(hex, 16);
}
function readUnicode(cursor) {
    const code = readHex4(cursor);
    if (code < 0xd800 || code > 0xdfff) {
        return String.fromCharCode(code);
    }
    if (code > 0xdbff || cursor.text[cursor.i] !== "\\" || cursor.text[cursor.i + 1] !== "u") {
        malformed();
    }
    cursor.i += 2;
    const low = readHex4(cursor);
    if (low < 0xdc00 || low > 0xdfff) {
        malformed();
    }
    return String.fromCodePoint(((code - 0xd800) << 10) + (low - 0xdc00) + 0x10000);
}
function readEscape(cursor) {
    if (atEnd(cursor)) {
        malformed();
    }
    const char = cursor.text[cursor.i] ?? "";
    cursor.i += 1;
    const simple = SIMPLE_ESCAPES[char];
    if (simple !== undefined) {
        return simple;
    }
    if (char === "u") {
        return readUnicode(cursor);
    }
    malformed();
}
function pointerFor(key) {
    return `/${key.replaceAll("~", "~0").replaceAll("/", "~1")}`;
}
function skipValue(cursor) {
    skip(cursor);
    if (atEnd(cursor)) {
        malformed();
    }
    const char = cursor.text[cursor.i];
    if (char === "{") {
        skipObject(cursor, undefined, undefined);
        return;
    }
    if (char === "[") {
        skipArray(cursor);
        return;
    }
    if (char === "\"") {
        readString(cursor);
        return;
    }
    while (!atEnd(cursor) && !",}]".includes(cursor.text[cursor.i] ?? " ")) {
        cursor.i += 1;
    }
}
function skipArray(cursor) {
    cursor.i += 1;
    skip(cursor);
    while (!atEnd(cursor) && cursor.text[cursor.i] !== "]") {
        const before = cursor.i;
        skipValue(cursor);
        skip(cursor);
        if (cursor.text[cursor.i] === ",") {
            cursor.i += 1;
            skip(cursor);
        }
        if (cursor.i === before) {
            malformed();
        }
    }
    if (cursor.text[cursor.i] !== "]") {
        malformed();
    }
    cursor.i += 1;
}
function skipObject(cursor, pointer, found) {
    cursor.i += 1;
    skip(cursor);
    while (!atEnd(cursor) && cursor.text[cursor.i] !== "}") {
        const key = readString(cursor);
        skip(cursor);
        if (atEnd(cursor)) {
            malformed();
        }
        cursor.i += 1;
        skip(cursor);
        if (pointer === pointerFor(key) && cursor.text[cursor.i] === "\"") {
            const start = cursor.i + 1;
            readString(cursor);
            if (found) {
                found.start = start;
                found.end = cursor.i - 1;
            }
        }
        else {
            skipValue(cursor);
        }
        skip(cursor);
        if (cursor.text[cursor.i] === ",") {
            cursor.i += 1;
            skip(cursor);
        }
    }
    if (cursor.text[cursor.i] !== "}") {
        malformed();
    }
    cursor.i += 1;
}
export function jsonStringSpan(text, pointer) {
    const found = { start: -1, end: -1 };
    const cursor = { text, i: 0 };
    skip(cursor);
    if (cursor.text[cursor.i] !== "{") {
        malformed();
    }
    skipObject(cursor, pointer, found);
    if (found.start < 0 || found.end < found.start) {
        malformed();
    }
    return { start: found.start, end: found.end };
}
export function replaceJsonString(text, pointer, mask) {
    const span = jsonStringSpan(text, pointer);
    return text.slice(0, span.start) + mask + text.slice(span.end);
}
//# sourceMappingURL=json-span.mjs.map