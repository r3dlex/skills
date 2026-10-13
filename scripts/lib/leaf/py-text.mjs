export function pySplitlines(text) {
    if (text === "") {
        return [];
    }
    const lines = text.split(/\r\n|\n|\r/);
    if ((text.endsWith("\n") || text.endsWith("\r")) && lines.at(-1) === "") {
        lines.pop();
    }
    return lines;
}
//# sourceMappingURL=py-text.mjs.map