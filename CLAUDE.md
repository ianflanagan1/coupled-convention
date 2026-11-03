# coupled-tags

`devbox run -- task check` runs ShellCheck, the shunit2 tests and the flake build; run it before finishing. `devbox run -- task lint-file -- <files>` checks the shell scripts given.

`skills/ianf-coupled-tags/scripts/coupled-tags-lint.sh` is POSIX `sh` and awk. `flake.nix` packages it as `coupled-tags-lint`, which other projects add to their devbox from GitHub, so a change reaches them only once it's pushed and they run `devbox update`. `scripts/coupled-tags-gate.py` runs under `python3 -I` with only the standard library. When the tag format changes, change SKILL.md, the README, the lint script and the hook together.
