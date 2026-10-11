export function pyJsonDumps(value: unknown, indent = 2): string {
  const body = JSON.stringify(value, null, indent) ?? "null";
  return body.replace(/[^\u0000-\u007e]/g, (ch) => `\\u${ch.charCodeAt(0).toString(16).padStart(4, "0")}`);
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
