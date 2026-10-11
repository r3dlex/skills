export function pyRepr(value) {
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
    return typeof value === "object" ? JSON.stringify(value) : `${value}`;
}
//# sourceMappingURL=py-repr.mjs.map