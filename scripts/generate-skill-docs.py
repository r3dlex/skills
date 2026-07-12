#!/usr/bin/env python3
"""Regenerate bounded catalog navigation in root and phase documentation."""
import argparse, re, sys
from pathlib import Path
from catalog import load_catalog
START='<!-- GENERATED:SKILL-CATALOG:START -->'; END='<!-- GENERATED:SKILL-CATALOG:END -->'
def description(path):
 text=path.read_text(); m=re.search(r'^description:\s*[\'\"]?(.*?)[\'\"]?\s*$',text,re.M); return m.group(1).rstrip("'\"") if m else ''
def replace(path, body, check):
 region=f'{START}\n{body.rstrip()}\n{END}'
 old=path.read_text() if path.exists() else ''
 if START in old and END in old: new=old[:old.index(START)]+region+old[old.index(END)+len(END):]
 else: new=old.rstrip()+('\n\n' if old.strip() else '')+region+'\n'
 if check:
  if new != old: print(f'generated catalog drift: {path}',file=sys.stderr); return False
 else: path.parent.mkdir(parents=True,exist_ok=True); path.write_text(new)
 return True
def main():
 p=argparse.ArgumentParser(); p.add_argument('--check',action='store_true'); a=p.parse_args(); root=Path(__file__).resolve().parent.parent; c=load_catalog(root)
 rows=['| Skill | Lifecycle | Owner phase |','|---|---|---|']
 for e in sorted(c['skills'],key=lambda x:x['name']): rows.append(f"| [`{e['name']}`]({e['source_path']}/SKILL.md) | `{e['lifecycle']}` | `{e['owner_phase']}` |")
 ok=replace(root/'README.md','\n'.join(rows),a.check) & replace(root/'AGENTS.md','\n'.join(rows),a.check)
 for phase in c['phases']:
  lines=[f'# {phase}','', '| Skill | Applies to phases |','|---|---|']
  for e in sorted((x for x in c['skills'] if x['owner_phase']==phase),key=lambda x:x['name']): lines.append(f"| [`{e['name']}`](../{e['source_path']}/SKILL.md) | {', '.join(e['applies_to_phases'])} |")
  ok=replace(root/phase/'README.md','\n'.join(lines),a.check) & ok
 return 0 if ok else 1
if __name__=='__main__': raise SystemExit(main())
