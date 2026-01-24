# Repository Guidelines

## Project Structure & Module Organization

- `skills/` holds individual skills; each skill lives in its own folder with a required `SKILL.md` and optional `LICENSE.txt`.
- `template/SKILL.md` is the starter template for new skills, including YAML frontmatter and section layout.
- `.claude-plugin/marketplace.json` defines the marketplace manifest and the list of published skills.
- `README.md` documents high-level usage and installation commands.

## Build, Test, and Development Commands

This repo is content-focused and does not include a build system or test runner.

- `/plugin marketplace add <github-user>/<repo-name>` adds this marketplace to Claude Code.
- `/plugin install my-skills@unilorn-skills` installs the skills defined in the manifest.

## Coding Style & Naming Conventions

- Skill files are Markdown with YAML frontmatter (`name`, `description`, `license`) at the top.
- Use clear, descriptive skill folder names: `skills/<skill-name>/SKILL.md`.
- Follow the section structure from `template/SKILL.md` (Overview → When to Use → Instructions → Examples).
- Use 2-space indentation for JSON in `.claude-plugin/marketplace.json` (current style).

## Testing Guidelines

- No automated tests are defined.
- Validate changes by ensuring the marketplace manifest references the new skill directory and that `SKILL.md` renders correctly.

## Commit & Pull Request Guidelines

- Commit messages are short and descriptive; observed patterns include `Initial commit: ...` and `config: ...` with optional emoji.
- PRs should include a brief description of the skill or manifest change and link any related issues if applicable.
- If adding a skill, include the new `SKILL.md` and update `.claude-plugin/marketplace.json`.

## Agent-Specific Notes

- Prefer creating skills via `template/SKILL.md` and keep instructions explicit and actionable.
- Keep skills narrow in scope and ensure trigger conditions are clear in the frontmatter and “When to Use” section.
