# coupled-tags

`devbox run -- task check` checks this repository, which holds only the skill's Markdown, so there's nothing for it to run; run it before finishing.

The lint and the Claude Code hooks are in coupled-tags-lint (`~/projects/cli/coupled-tags-lint`), which defines the marker and registry format in code. When the format changes, change SKILL.md, this README, and the lint's `core/markers.py`, `core/relations.py`, `core/registry.py` and README together.
