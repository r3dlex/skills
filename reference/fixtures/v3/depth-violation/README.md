# Depth Violation Fixture C

The matrix declares `current_depth: 4` with `max_allowed_depth: 3`. The validator must:

1. Detect the violation (`current_depth > max_allowed_depth`).
2. Refuse to start the sync or apply path.
3. Emit a blocking error that names the offending repo path (`platform/team-a/region-eu/service-x`) and the offending depth (`4`).

Expected validator exit code: non-zero.
