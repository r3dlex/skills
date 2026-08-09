# Ticket Types

Every ticket is either **HITL** — human in the loop, worked *with* a human who speaks for
themselves — or **AFK**, driven by the agent alone.

A HITL ticket only resolves through that live exchange. The agent never stands in for the
human's side of it: a grilling session that answers its own questions has broken this rule,
and its "decision" is worthless because nothing was actually decided.

## Research (AFK)

Reading documentation, third-party APIs, or local resources such as knowledge bases, to
surface a fact a decision waits on. Resolved by delegating to the `research` skill.

Use when knowledge outside the current working directory is required.

## Prototype (HITL)

Raise the fidelity of the discussion by making a cheap, rough, concrete artifact to react
to — an outline, a rough take, a stub, or UI/logic code via the `prototype` skill. Link the
prototype as an asset rather than pasting it in.

Use when "how should it look" or "how should it behave" is the key question.

## Grilling (HITL)

Conversation. The default case. Always invoke `grill-me` and `domain-modeling`.

## Task (HITL or AFK)

Manual work that must happen before a *decision* can be made — nothing to decide, prototype,
or research, but the discussion is blocked until it is done. Signing up for a service so its
API can be judged, provisioning access, moving data so its shape can be seen.

This is the one type that *does* rather than decides, and it earns its place by unblocking a
decision, not by delivering the destination. The agent drives it alone where it can (AFK);
otherwise it hands the human a precise checklist (HITL).

Resolved when the work is done. The answer records what was done and any resulting facts —
credential locations, new URLs, row counts — that later tickets depend on.
