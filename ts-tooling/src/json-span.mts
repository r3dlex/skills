interface Cursor {
  text: string;
  i: number;
}

function atEnd(cursor: Cursor): boolean {
  return cursor.i >= cursor.text.length;
}

function isSpace(char: string | undefined): boolean {
  return char === " " || char === "\n" || char === "\r" || char === "\t";
}

function skip(cursor: Cursor): void {
  while (!atEnd(cursor) && isSpace(cursor.text[cursor.i])) {
    cursor.i += 1;
  }
}

function malformed(): never {
  throw new Error("mask site not located");
}

function readString(cursor: Cursor): string {
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

function readEscape(cursor: Cursor): string {
  if (atEnd(cursor)) {
    malformed();
  }
  const char = cursor.text[cursor.i] ?? "";
  cursor.i += 1;
  return char;
}

function skipValue(cursor: Cursor): void {
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

function skipArray(cursor: Cursor): void {
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

function skipObject(cursor: Cursor, pointer: string | undefined, found: { start: number; end: number } | undefined): void {
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
    if (pointer === `/${key}` && cursor.text[cursor.i] === "\"") {
      const start = cursor.i + 1;
      readString(cursor);
      if (found) {
        found.start = start;
        found.end = cursor.i - 1;
      }
    } else {
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

export function jsonStringSpan(text: string, pointer: string): { start: number; end: number } {
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

export function replaceJsonString(text: string, pointer: string, mask: string): string {
  const span = jsonStringSpan(text, pointer);
  return text.slice(0, span.start) + mask + text.slice(span.end);
}
