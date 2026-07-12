"""Small frontmatter helper kept separate to avoid validator import cycles."""
from pathlib import Path

def frontmatter_name(path: Path) -> str:
    lines = path.read_text(encoding="utf-8").splitlines()
    if not lines or lines[0] != "---":
        return ""
    for line in lines[1:]:
        if line == "---": break
        if line.startswith("name:"):
            return line.split(":", 1)[1].strip().strip("'\"")
    return ""
