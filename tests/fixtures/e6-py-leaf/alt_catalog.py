import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
root.joinpath("catalog.json").write_text(
    json.dumps(
        {
            "schema_version": "1.0",
            "phases": ["03-configure-generate"],
            "skills": [
                {
                    "name": "ai-catapult-init",
                    "source_path": "03-configure-generate/ai-catapult-init",
                    "owner_phase": "03-configure-generate",
                    "applies_to_phases": ["03-configure-generate"],
                    "lifecycle": "stable",
                    "supported_hosts": ["codex"],
                }
            ],
        },
        indent=2,
    )
    + "\n"
)
