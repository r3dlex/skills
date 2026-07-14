#!/bin/bash
# Shared argument parsing and selection for host installers.
CATALOG_INCLUDES=()
CATALOG_REST=()
parse_catalog_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --include-lifecycle)
        [[ $# -ge 2 ]] || { echo "--include-lifecycle requires a value" >&2; return 2; }
        case "$2" in stable|compatibility|experimental|deprecated) CATALOG_INCLUDES+=("$2");; *) echo "unknown lifecycle: $2" >&2; return 2;; esac
        shift 2;;
      *) CATALOG_REST+=("$1"); shift;;
    esac
  done
}
catalog_rows() {
  local host="$1"; shift
  local args=(--root "$SKILLS_DIR" --host "$host") value
  if [[ ${#CATALOG_INCLUDES[@]} -gt 0 ]]; then
    for value in "${CATALOG_INCLUDES[@]}"; do args+=(--include-lifecycle "$value"); done
  fi
  python3 "$SCRIPT_DIR/catalog-query.py" "${args[@]}" "$@"
}

skill_description() {
  python3 - "$1" <<'PY'
import sys
from pathlib import Path

for line in Path(sys.argv[1]).read_text().splitlines()[1:]:
    if line == '---':
        break
    if line.startswith('description:'):
        print(line.split(':', 1)[1].strip().strip('"\''))
        break
PY
}

flattened_skill_body() {
  python3 - "$1" <<'PY'
import re
import sys
from pathlib import Path

skill_file = Path(sys.argv[1])
skill_dir = skill_file.parent
repo = skill_dir
while repo.parent != repo and not (repo / 'catalog.json').is_file():
    repo = repo.parent
lines = skill_file.read_text().splitlines()

if lines and lines[0] == '---':
    try:
        lines = lines[lines.index('---', 1) + 1:]
    except ValueError:
        pass

sidecar_paths = set()
catalog_path = repo / 'catalog.json'
if catalog_path.is_file():
    import json
    for entry in json.loads(catalog_path.read_text())['skills']:
        source_dir = repo / entry['source_path']
        for sidecar in source_dir.rglob('*'):
            if not sidecar.is_file() or sidecar.name == 'SKILL.md':
                continue
            relative = sidecar.relative_to(source_dir).as_posix()
            sidecar_paths.add(f"{entry['name']}/{relative}")
            if source_dir == skill_dir:
                sidecar_paths.add(relative)
for prefix in ('reference', 'tests'):
    root = repo / prefix
    if root.is_dir():
        sidecar_paths.update(path.relative_to(repo).as_posix() for path in root.rglob('*') if path.is_file())

def has_unavailable_path(text):
    return any(path in text for path in sidecar_paths)

def remove_orphan_lead_in(output):
    while output and output[-1] == '':
        output.pop()
    start = len(output)
    while start and output[start - 1] != '' and not output[start - 1].startswith('#'):
        start -= 1
    if start < len(output) and output[-1].rstrip().endswith(':'):
        del output[start:]

def flush_block(block, output):
    if not block:
        return
    list_item = re.compile(r'^(\s*)([-+*]|\d+\.)\s+')
    if not any(list_item.match(line) for line in block):
        if has_unavailable_path('\n'.join(block)):
            if block[0].startswith('```'):
                remove_orphan_lead_in(output)
        else:
            output.extend(block)
        return

    items = []
    current = []
    for line in block:
        if list_item.match(line):
            if current:
                items.append(current)
            current = [line]
        elif current:
            current.append(line)
        else:
            items.append([line])
    if current:
        items.append(current)

    ordered = 0
    for item in items:
        text = '\n'.join(item)
        if has_unavailable_path(text):
            continue
        match = list_item.match(item[0])
        if match and match.group(2).endswith('.'):
            ordered += 1
            item[0] = re.sub(r'^(\s*)\d+\.', rf'\g<1>{ordered}.', item[0], count=1)
        output.extend(item)

output = []
block = []
skip_level = None
for line in lines:
    heading = re.match(r'^(#{1,6})\s+(.+?)\s*$', line)
    if heading:
        flush_block(block, output)
        block = []
        level = len(heading.group(1))
        if skip_level is not None and level <= skip_level:
            skip_level = None
        if heading.group(2).casefold() == 'references':
            skip_level = level
            continue
        if skip_level is None:
            output.append(line)
        continue
    if skip_level is not None:
        continue
    if line.strip():
        block.append(line)
    else:
        flush_block(block, output)
        block = []
        if output and output[-1] != '':
            output.append('')
flush_block(block, output)

cleaned = []
for index, line in enumerate(output):
    heading = re.match(r'^(#{2,6})\s+', line)
    if heading:
        level = len(heading.group(1))
        has_content = False
        for later in output[index + 1:]:
            next_heading = re.match(r'^(#{1,6})\s+', later)
            if next_heading and len(next_heading.group(1)) <= level:
                break
            if later.strip() and not next_heading:
                has_content = True
                break
        if not has_content:
            continue
    cleaned.append(line)
output = cleaned

while output and output[-1] == '':
    output.pop()
print('\n'.join(output))
PY
}
