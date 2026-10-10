interface Cursor {
  text: string;
  i: number;
}

function skip(cursor: Cursor): void {
  while (" \n\r\t".includes(cursor.text[cursor.i] ?? "")) {
    cursor.i += 1;
  }
}

function readString(cursor: Cursor): string {
  if (cursor.text[cursor.i] !== "\"") {
    throw new Error("mask site not located");
  }
  cursor.i += 1;
  let value = "";
  while (cursor.i < cursor.text.length && cursor.text[cursor.i] !== "\"") {
    const char = cursor.text[cursor.i] ?? "";
    cursor.i += 1;
    value += char === "\\" ? readEscape(cursor) : char;
  }
  cursor.i += 1;
  return value;
}

function readEscape(cursor: Cursor): string {
  const char = cursor.text[cursor.i] ?? "";
  cursor.i += 1;
  return char;
}

function skipValue(cursor: Cursor): void {
  skip(cursor);
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
  while (cursor.i < cursor.text.length && !",}]".includes(cursor.text[cursor.i] ?? "")) {
    cursor.i += 1;
  }
}

function skipArray(cursor: Cursor): void {
  cursor.i += 1;
  skip(cursor);
  while (cursor.text[cursor.i] !== "]") {
    skipValue(cursor);
    skip(cursor);
    if (cursor.text[cursor.i] === ",") {
      cursor.i += 1;
      skip(cursor);
    }
  }
  cursor.i += 1;
}

function skipObject(cursor: Cursor, pointer: string | undefined, found: { start: number; end: number } | undefined): void {
  cursor.i += 1;
  skip(cursor);
  while (cursor.text[cursor.i] !== "}") {
    const key = readString(cursor);
    skip(cursor);
    cursor.i += 1;
    skip(cursor);
    const path = `/${key}`;
    if (pointer === path && cursor.text[cursor.i] === "\"") {
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
  cursor.i += 1;
}

export function replaceJsonString(text: string, pointer: string, mask: string): string {
  const found = { start: -1, end: -1 };
  const cursor = { text, i: 0 };
  skip(cursor);
  if (text[cursor.i] !== "{") {
    throw new Error("mask site not located");
  }
  skipObject(cursor, pointer, found);
  if (found.start < 0) {
    throw new Error("mask site not located");
  }
  return text.slice(0, found.start) + mask + text.slice(found.end);
}
