# Umbrella Fixture B

Reference v3 layout for an umbrella repository. The matrix declares two managed repos (`services/auth`, `services/billing`) at depth 2 with `max_allowed_depth: 3`. The drift report shows the expected shape after a physical-copy sync run.


Workflow fixture surfaces are generated under `.ai/workflows/`, `.ai/phases/`, and `.ai/handoff/`; generated `AGENTS.md` and `README.md` link to both workflow files (`CLAUDE.md`/`GEMINI.md` are thin pointers to `AGENTS.md`).
