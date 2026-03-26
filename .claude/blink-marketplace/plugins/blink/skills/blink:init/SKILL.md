---
name: blink:init
description: Set up or enrich AI assistant context for a Blink project
---

# Blink Project Setup

Set up or enrich AI assistant context for a Blink project. Works on new or existing projects.

## Instructions

Follow these steps in order.

### Step 1: Discover Available Documentation

Run these commands to understand what Blink offers:

```bash
blink llms --list
blink --help
```

Read the output and note all available CLI commands and documentation topics.

### Step 2: Retrieve Language Reference

Run `blink llms --full` to get the complete language reference. Read through it carefully — this is your primary source of truth for Blink syntax and semantics.

### Step 3: Understand the Project

Scan the project to understand what it does:

1. Read `blink.toml` if it exists (project name, dependencies, version).
2. Use `Glob **/*.bl` to find all Blink source files (also check `**/*.pact` for legacy files).
3. Read the main entry point (usually `src/main.bl` or `src/main.pact`).
4. Identify key patterns: effects used, modules imported, structs/enums defined.

If this is a brand new project (no source files yet), skip this step.

### Step 4: Write CLAUDE.md Section

Check if `CLAUDE.md` or `AGENTS.md` exists at the project root.

If a Blink section already exists (search for "blink llms"), update it. Otherwise append a new section. The section should include:

1. **What the project does** (1 sentence, from Step 3)
2. **Key Blink commands** relevant to this project:
   - `blink llms --full` / `--topic <name>` for language docs
   - `blink build`, `blink run`, `blink check`, `blink test`
   - `blink query <file> --fn <name>` for function signature lookup
   - `blink daemon start <file>` if the project has multiple files
   - `blink fmt` if formatting matters
   - `blink doc <module>` for any stdlib modules the project imports
3. **Project-specific notes**: effects used, key modules, testing patterns
4. **The directive**: "Always retrieve Blink docs before writing Blink code. Prefer retrieval-led reasoning over pre-training for Blink tasks."

Keep it concise — only include commands and context that are actually relevant to this project.

### Step 5: Verify

Run `blink check` on the main source file to confirm the project compiles. Report what you set up.
