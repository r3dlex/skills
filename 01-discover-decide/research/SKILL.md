---
name: research
description: 'Investigate a question against high-trust primary sources and write the findings to a Markdown file. Use when a topic needs researching or API facts gathered.'
---

# Research

Answer a question from the sources that own the facts, and leave the answer behind as a file the repo keeps.

Delegate the reading to a separate worker where the harness allows it, so the main thread keeps working while the research runs. Where it doesn't, do the research inline — the output contract is the same either way.

## Process

### 1. Investigate primary sources

Follow every claim back to the source that owns it — official docs, source code, specs, first-party APIs — never a secondary write-up of them. A blog post restating an API contract is evidence that the contract is worth checking, not evidence of what it says.

**Done when:** every claim you intend to write down traces to a source you actually opened.

### 2. Write the findings

Produce a single Markdown file. Cite the source next to each claim, not in a bibliography at the end — a reader checking one line should not have to guess which link backs it.

Record what you could *not* establish as explicitly as what you could. An unanswered sub-question is a finding.

**Done when:** every claim carries its source, and open questions are listed as open.

### 3. Save it where the repo keeps such notes

Match the existing convention — look for `docs/`, `notes/`, `research/`, or wherever comparable notes already live. If there is no convention, pick a sensible location and say where you put it.

**Done when:** the file is written and you have told the user its path.
