export function pyJsonDumps(value: unknown, indent = 2): string {
  const body = JSON.stringify(value, null, indent) ?? "null";
  let out = "";
  for (let index = 0; index < body.length; index += 1) {
    const code = body.charCodeAt(index);
    const ch = body[index] ?? "";
    out += code > 0x7e ? `\\u${code.toString(16).padStart(4, "0")}` : ch;
  }
  return out;
}

export function pyRepr(value: unknown): string {
  if (typeof value === "string") {
    return `'${value.replaceAll("\\", "\\\\").replaceAll("'", "\\'")}'`;
  }
  if (Array.isArray(value)) {
    return `[${value.map((item) => pyRepr(item)).join(", ")}]`;
  }
  if (value === null || value === undefined) {
    return "None";
  }
  if (typeof value === "number" || typeof value === "boolean") {
    return JSON.stringify(value).replace("true", "True").replace("false", "False");
  }
  return typeof value === "object" ? JSON.stringify(value) : `${value as string}`;
}
