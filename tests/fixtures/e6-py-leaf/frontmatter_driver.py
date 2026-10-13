import sys
from pathlib import Path

from validate_skill_frontmatter import frontmatter_name

print(frontmatter_name(Path(sys.argv[1])))
