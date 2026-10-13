export function pySplitlines(text: string): string[] {
  if (text === "") {
    return [];
  }
  const lines = text.split(/\r\n|\n|\r/);
  if ((text.endsWith("\n") || text.endsWith("\r")) && lines.at(-1) === "") {
    lines.pop();
  }
  return lines;
}
