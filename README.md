# unilorn-skills

Personal skill marketplace for Claude Code.

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

## Installation

```bash
# Add this marketplace
/plugin marketplace add <github-user>/<repo-name>

# Install skills from this marketplace
/plugin install my-skills@unilorn-skills
```

## Skills

| Skill | Description |
|-------|-------------|
| [effective-go](skills/effective-go/SKILL.md) | Apply Go best practices from Effective Go guide |
