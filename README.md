# COUPLED tags

A comment convention for code and values that must change together but can't share a single source of truth. Each place gets a greppable tag, so whoever changes one can run `grep --recursive --line-number 'COUPLED:<key>:'` and find the others.

It ships with a lint script and a Claude Code skill.

## Why

Configuration is spread across tools that can't read each other: proxies, app servers, CI, Dockerfiles and external consoles. A plain "keep in sync with X" comment is easy to miss and can't be searched for reliably. A tag can.

Prefer to use a single source of truth whenever possible: environment variables, templating, generated files or a shared module. Use a tag when that costs more than it saves, or until a refactor makes it possible.

## Examples

### A duplicated function

E.g. Legacy code awaiting a refactor.

```java
// src/main/java/com/example/billing/Invoice.java
/**
 * COUPLED:vat-calculation: same-as
 */
private int calculateVat(int netPence) { ... }
```
```java
// src/main/java/com/example/checkout/Cart.java
/**
 * COUPLED:vat-calculation: same-as
 */
private int calculateVat(int netPence) { ... }
```

---

### A runtime version pinned in several files

```toml
# pyproject.toml
requires-python = ">=3.12"     # COUPLED:python-version: = (also .python-version)
```
```yaml
# .github/workflows/ci.yml
python-version: "3.12"         # COUPLED:python-version: = (also .python-version)
```
```dockerfile
# Dockerfile
# COUPLED:python-version: = (also .python-version)
FROM python:3.12-slim
```

`.python-version` can't take a comment, so the other sites name it.

---

### An upload limit that must be larger at the proxy than in the app

```nginx
# nginx/default.conf
client_max_body_size 10m;      # COUPLED:upload-size-limit: >= MAX_UPLOAD_MB (m vs MB)
```
```python
# app/settings.py
MAX_UPLOAD_MB = 8              # COUPLED:upload-size-limit: <= client_max_body_size (MB vs m)
```

---

### A load-balancer idle timeout that must be shorter than the app's keep-alive timeout

```js
// server.js
server.keepAliveTimeout = 65_000;  // COUPLED:keepalive-timeout: > idle timeout (ms vs s)
```
```markdown
<!-- docs/external/aws-alb.md -->
Idle timeout: 60 s (EC2 console > Load balancers > prod-alb > Attributes). COUPLED:keepalive-timeout: < server.keepAliveTimeout (s vs ms)
```

---

### An OAuth redirect URI registered in a provider's console

```python
# app/auth.py
REDIRECT_URI = "https://example.com/auth/callback"  # COUPLED:oauth-redirect-uri: =
```
```markdown
<!-- docs/external/google-oauth.md -->
Authorised redirect URIs: `https://example.com/auth/callback`. COUPLED:oauth-redirect-uri: =
```


## Format

```
<comment> COUPLED:<key>: <op> [<target>] [(<note>)]
```

- **Key:** lowercase letters, digits and `-`, ended by `:`. A key names a *group*, so one search for `COUPLED:<key>:` finds every site in it. Every character is literal in plain and regex search alike, so it finds exactly the group however it's run, and a shortened search only finds more, never less.
- **Op:** `=`, `!=`, `<`, `<=`, `>`, `>=`, or `same-as` for duplicated code, from this site's point of view.
- **Target:** the other value, by its own name at its site. Not its file: the search already shows where every site is, and a path goes stale when files move. Leave the target out when every site in the group is `=`, or every site is `same-as`.
- **Note:** optional free text in parentheses for what the op and target can't say: units, a formula, a reason. Keeping it in parentheses separates it from the op and target, which the lint can check.
- **Placement:** use the file's own comment syntax, with the tag last in its comment. Put it in a trailing comment on the line it describes; where that isn't possible or would change the value (Dockerfiles, Makefile variables), or for a multi-line block, on the line above; for a whole function, in its docblock.
- **Sites the search can't reach:** a file without comments (JSON, `.nvmrc`) gets no tag, and a search of one repository misses a site in another. Every tagged site lists them in a note starting `also`: `(also .nvmrc)`, `(also repo-tools: src/repo_list/agents.py)`.

### Choosing a key

Name the invariant the group protects, not where it lives: `request-timeout-chain`, not `nginx-timeouts`. If an unrelated setting could plausibly carry the key, it's too vague.

### External systems

When the other end lives outside the repo (a cloud console, DNS, a provider's dashboard), describe its **current** configuration in `docs/external/<service>.md`, and tag each value there. The search then finds the doc, and the doc says what to change and where.

## Lint

`skills/ianf-coupled-tags/scripts/coupled-tags-lint.sh` is POSIX `sh` and runs anywhere. It reports:

- **malformed tags:** the key has uppercase letters or underscores, or is missing the `:` or the space after it
- **relations:** a relation that doesn't start with an op, an op that needs a target and lacks one, or a note that isn't one parenthesised piece at the end
- **orphan keys:** the key appears only once, which usually means the other end was deleted, unless its note starts `also`

```sh
coupled-tags-lint            # check the current directory
coupled-tags-lint -l         # also list every key and its sites
coupled-tags-lint -x docs/   # exclude a path prefix (repeatable)
```

In a git work tree it scans tracked files plus untracked files that aren't ignored. Elsewhere it uses `grep --recursive`, skipping `.git`, `node_modules` and `vendor`. It exits with 0 when clean, 1 when it finds problems, and 2 on a usage error.

### Adding it to a project

This repository is a Nix flake that packages the script as the `coupled-tags-lint` command, with the `git`, `awk`, `grep` and `sed` it calls pinned, so it behaves the same on macOS, Linux and CI. Add it to a project's devbox, which pins the commit in `devbox.lock`:

```sh
devbox add github:ianflanagan1/coupled-tags#coupled-tags-lint
```

Then run `coupled-tags-lint` in the project's check, for example as a step of a Taskfile `check` task, so CI runs it too. `devbox update` moves the project to the latest version. Without devbox, `nix run github:ianflanagan1/coupled-tags` runs it once, and `sh skills/ianf-coupled-tags/scripts/coupled-tags-lint.sh` runs it from a clone.

It does **not** check that changes to a key touch every site. Diff-aware enforcement in the style of Google's `LINT.IfChange` is out of scope.

## Claude Code

The `ianf-coupled-tags` skill teaches Claude the convention:

- **Adding:** `/ianf-coupled-tags <this> with <that> [as <key>]`. Claude finds every site, tags each one, checks the relations hold and runs the lint script. If you don't give a key, it proposes one and waits for your choice.
- **Honouring:** before editing anything tagged `COUPLED:`, Claude searches for the key and updates every site. The hook below makes sure of it.

Clone to `~/projects/claude/coupled-tags`, then link the skill into your skills folder:

```sh
ln -s ~/projects/claude/coupled-tags/skills/ianf-coupled-tags ~/.claude/skills/ianf-coupled-tags
```

It's invoked as `/ianf-coupled-tags`. The `ianf-` prefix keeps it from colliding with other skills of the same name.

### Hook

A skill's description doesn't guarantee Claude loads it just because it's editing a tagged line. `scripts/coupled-tags-gate.py` does: a `PreToolUse` hook on Edit, MultiEdit and Write. The first time in a session that an edit touches a tagged line, a line under a tag's comment block, or a line inside a tagged block, it refuses the edit and gives Claude every site of the key in that repository, so Claude reads the group, changes it together, and retries. Later edits to that key in the session pass. It runs on the standard library, and lets any input it can't handle through.

It doesn't see edits made through Bash, or blocks that aren't indented. Run `devbox install` in this repository, then add it to the `hooks` section of `~/.claude/settings.json`:

```json
"PreToolUse": [
  {
    "matcher": "Write|Edit|MultiEdit",
    "hooks": [
      {
        "type": "command",
        "command": "\"$HOME/projects/claude/coupled-tags/.devbox/nix/profile/default/bin/python3\" -I \"$HOME/projects/claude/coupled-tags/scripts/coupled-tags-gate.py\""
      }
    ]
  }
]
```

Without the hook, add this line to your project's `CLAUDE.md` instead:

```
Before changing anything tagged `COUPLED:<key>:`, search for `COUPLED:<key>:` and update every site (see the ianf-coupled-tags skill).
```

## Development

`devbox run -- task check` runs ShellCheck, the tests of the lint script and the hook, then builds the flake and lints this repository's tags with the command it packages.

## Other agents

The convention and the lint script don't depend on any agent. `skills/ianf-coupled-tags/SKILL.md` uses the [Agent Skills](https://agentskills.io) format, so other agents that support skills can load it.

- **Agents that support skills:** copy `skills/ianf-coupled-tags/` into your agent's skills directory (see its docs for the location). Keep the folder intact, so `scripts/coupled-tags-lint.sh` stays alongside `SKILL.md`. Slash-command arguments may behave differently, so just ask the agent in plain language, for example "couple the nginx upload limit with the app's `MAX_UPLOAD_MB`".
- **Any agent:** add this to your project's `AGENTS.md` (or the agent's equivalent instructions file):

  ```
  Code and values that must change together are tagged `COUPLED:<key>: <relation>` in comments.
  Before changing anything tagged `COUPLED:<key>:`, run `grep --recursive --line-number 'COUPLED:<key>:'`, read every site
  and every site listed in an `also` note, and update them together so every relation still holds. Never silently change a value to satisfy a relation; report violations.
  ```

- **CI:** run `coupled-tags-lint` as a step (see [Adding it to a project](#adding-it-to-a-project)) to catch malformed tags and orphan keys whoever made the edit.

## Prior art

- Google's `LINT.IfChange` / `LINT.ThenChange`, enforced at code review
- "Keep in sync with ..." comments
