# unilorn-skills

Personal skill marketplace for Claude Code, with local sync support for Codex.

## Structure

```
.
├── .claude-plugin/
│   └── marketplace.json    # Marketplace manifest
├── skills/                 # Individual skills
│   └── <skill-name>/
│       ├── SKILL.md        # Skill definition (required)
│       └── LICENSE.txt     # License (optional)
├── template/
│   └── SKILL.md            # Template for new skills
└── README.md
```

## Creating a New Skill

1. Copy `template/SKILL.md` to `skills/<your-skill-name>/SKILL.md`
2. Edit the YAML frontmatter and content
3. Add the skill path to `.claude-plugin/marketplace.json` in the `skills` array

## Installation (Claude Code)

```bash
# Add this marketplace
/plugin marketplace add <github-user>/<repo-name>

# Install skills from this marketplace
/plugin install my-skills@unilorn-skills
```

## Installation (Codex)

If you want to use these skills with Codex, sync them into your Codex skills directory.

```bash
scripts/sync_skills.sh

# Optional: remove skills in ~/.codex/skills that are not in this repo
scripts/sync_skills.sh --delete
```

The script syncs `skills/*` to `~/.codex/skills` by default. Set `CODEX_HOME` to target a different Codex home directory.

## Skills

| Skill | Description |
|-------|-------------|
| [effective-go](skills/effective-go/SKILL.md) | Apply Go best practices from Effective Go guide |
| [github-pr-description](skills/github-pr-description/SKILL.md) | Generate or overwrite a GitHub PR description from the current branch diff |
