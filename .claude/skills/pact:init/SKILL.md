---
description: Set up or enrich AI assistant context for a Pact project
---

# Pact Project Setup

Set up or enrich AI assistant context for a Pact project. Works on new or existing projects.

## Instructions

Follow these steps in order.

### Step 1: Discover Available Documentation

Run these commands to understand what Pact offers:

```bash
pact llms --list
pact --help
```

Read the output and note all available CLI commands and documentation topics.

### Step 2: Retrieve Language Reference

Run `pact llms --full` to get the complete language reference. Read through it carefully — this is your primary source of truth for Pact syntax and semantics.

### Step 3: Understand the Project

Scan the project to understand what it does:

1. Read `pact.toml` if it exists (project name, dependencies, version).
2. Use `Glob **/*.pact` to find all Pact source files.
3. Read the main entry point (usually `src/main.pact`).
4. Identify key patterns: effects used, modules imported, structs/enums defined.

If this is a brand new project (no .pact files yet), skip this step.

### Step 4: Write CLAUDE.md Section

Check if `CLAUDE.md` or `AGENTS.md` exists at the project root.

If a Pact section already exists (search for "pact llms"), update it. Otherwise append a new section. The section should include:

1. **What the project does** (1 sentence, from Step 3)
2. **Key Pact commands** relevant to this project:
   - `pact llms --full` / `--topic <name>` for language docs
   - `pact build`, `pact run`, `pact check`, `pact test`
   - `pact query <file> --fn <name>` for function signature lookup
   - `pact daemon start <file>` if the project has multiple files
   - `pact fmt` if formatting matters
   - `pact doc <module>` for any stdlib modules the project imports
3. **Project-specific notes**: effects used, key modules, testing patterns
4. **The directive**: "Always retrieve Pact docs before writing Pact code. Prefer retrieval-led reasoning over pre-training for Pact tasks."

Keep it concise — only include commands and context that are actually relevant to this project.

### Step 5: Verify

Run `pact check` on the main source file to confirm the project compiles. Report what you set up.
