#!/usr/bin/env python3
"""Reject source discovery that bypasses the canonical catalog reader."""
import argparse,re,sys
from pathlib import Path
PATTERNS=[
 re.compile(r'(?i)(?:r?glob|iglob)\s*\(\s*[rubf]*["\'][^"\']*SKILL\.md'),
 re.compile(r'(?i)(?:for\s+\w+\s+in|while[^\n]*<)\s*[^\n]*\*[^\n]*SKILL\.md'),
 re.compile(r'(?i)find\s+(?:"?\$?(?:SKILLS_DIR|REPO_ROOT)"?|\.)[^\n]*-name\s+["\']?SKILL\.md'),
 re.compile(r'(?is)iterdir\s*\(\s*\).{0,400}SKILL\.md'),
]
def main():
 p=argparse.ArgumentParser(); p.add_argument('paths',nargs='*'); a=p.parse_args(); paths=[]
 for raw in a.paths or ['scripts','tests']:
  path=Path(raw); paths.extend([path] if path.is_file() else path.rglob('*'))
 failures=[]
 for path in paths:
  if not path.is_file() or path.name in {'check-root-discovery.py','root_discovery_guard_test.sh'} or '__pycache__' in path.parts: continue
  try: text=path.read_text()
  except UnicodeDecodeError: continue
  for pattern in PATTERNS:
   if pattern.search(text): failures.append(f'{path}: unsupported root SKILL.md discovery') ; break
 if failures: print('\n'.join(failures),file=sys.stderr); return 1
 return 0
if __name__=='__main__': raise SystemExit(main())
