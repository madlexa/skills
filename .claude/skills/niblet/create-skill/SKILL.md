---
name: create-skill
description: Use when creating or updating a skill, agent, command, script, or CLAUDE.md/AGENTS.md addition in the madlexa/skills marketplace repo.
user-invocable: false
---

# Authoring skills and agents for madlexa/skills

## Overview
This repo is a marketplace of Claude Code / Kimi Code CLI plugins. Reusable workflows live as skills; specialized sub-agents live as agent prompts. Follow these conventions so niblet can promote your artifact safely.

## When to use
- You are about to create a new reusable workflow the agent should invoke automatically.
- You are editing an existing skill, agent, command, script, or project-wide instruction file.
- You are unsure whether a finding should be a KB entry, memory file, or skill.

## When NOT to use
- One-off bug fixes or single-session discoveries → use `ADD_KB_ENTRY` instead.
- User feedback or corrections → use `UPDATE_MEMORY` instead.

## Decide the artifact type

| Finding | Artifact | Promotion path |
|---|---|---|
| One-off gotcha, convention, root cause | KB entry | `ADD_KB_ENTRY` → `.claude/kb/<topic>.md` (auto) |
| User correction, "wtf", interruption | Memory | `UPDATE_MEMORY` → `.claude/memory/feedback_<slug>.md` (auto) |
| Reusable agent workflow | Skill | `CREATE_SKILL` → `.claude/skills/niblet/<name>/SKILL.md` (proposal) |
| Specialized sub-agent prompt | Agent | `CREATE_AGENT` → `.claude/agents/niblet/<name>.md` (proposal) |
| Terminal shortcut | Command | `CREATE_COMMAND` → `.claude/commands/niblet/<name>` (proposal) |
| Reusable helper script | Script | `CREATE_SCRIPT` → `.claude/scripts/niblet/<name>` (proposal) |
| Project-wide agent instructions | CLAUDE.md / AGENTS.md | `UPDATE_CLAUDE` / `UPDATE_AGENTS` (proposal) |

## Skill structure

File: `.claude/skills/niblet/<name>/SKILL.md`

```markdown
---
name: <slug>
description: Use when <triggering conditions>
user-invocable: false
---

# Title

## Overview
What this is and why it matters (1–2 sentences).

## When to use
- Symptom / situation 1
- Symptom / situation 2

## Steps
1. Actionable step one.
2. Actionable step two.
3. Actionable step three.

## Why this works
(Optional) non-obvious rationale.

## Trust / safety
(Optional) boundaries or risks.
```

## Validation checklist
- [ ] Frontmatter is valid YAML and contains `name` and `description`.
- [ ] `name` matches the directory basename and uses only `[a-z0-9._-]`.
- [ ] `description` starts with "Use when" and describes triggering conditions, not the workflow.
- [ ] Body includes `## When to use` and `## Steps`.
- [ ] No secrets, no ephemeral project state, no large copy-pasted logs.
- [ ] Tool names match the current runtime (Claude Code vs Kimi Code CLI).

## Promotion
1. Stage through niblet as `CREATE_SKILL` (project scope, target as above).
2. Review the generated proposal in `.niblet/proposals/`.
3. Promote with `niblet-promote <proposal-file>` or run `NIBLET_AUTO_PROMOTE=1 niblet-skill-gardener` if the proposal is low-risk.

## Common mistakes
- Putting the skill directly in `.claude/skills/<name>/` instead of `.claude/skills/niblet/<name>/`. The `niblet/` namespace keeps plugin-owned skills isolated.
- Writing a description that summarizes the skill's workflow. Future agents may follow the description instead of reading the full skill.
- Forgetting `user-invocable`. Set to `true` only if the user can type the skill name as a command.
