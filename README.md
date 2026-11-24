# COUPLED tags

A convention for code and values that must change together but can't share a single source of truth. Each place carries a greppable marker, `COUPLED:<key>: <label>`, and the repository's registry, `.coupled-tags.toml`, describes each group: how its places relate. Whoever changes one runs `grep --recursive --line-number 'COUPLED:<key>:'` and finds the others, and the group's table beside them.

It comes with a lint, [coupled-tags-lint](https://github.com/ianflanagan1/coupled-tags-lint), which checks that markers and registry agree, that the values they relate hold, and that no group has changed since it was last reviewed, and which gives Claude Code two hooks. This repository holds the Claude Code skill.

## Why

Configuration is spread across tools that can't read each other: proxies, app servers, CI, Dockerfiles and external consoles. A plain "keep in sync with X" comment is easy to miss and can't be searched for reliably. A marker can.

Prefer to use a single source of truth whenever possible: environment variables, templating, generated files or a shared module. Use a marker when that costs more than it saves, or until a refactor makes it possible.

## Why a marker and a registry

The marker on each line says, in the code, that the line is coupled and what to search for; the registry says, in one place, how the group relates. So a reader of any site is one search from the whole group, a relation is written once rather than at every site, and a group can hold files that can't take a comment, even only such files.

## Examples

### A duplicated function

E.g. Legacy code awaiting a refactor.

```java
// src/main/java/com/example/billing/Invoice.java
/**
 * COUPLED:vat-calculation: invoice
 */
private int calculateVat(int netPence) {
    ...
}
// COUPLED:vat-calculation:END
```
```java
// src/main/java/com/example/checkout/Cart.java
/**
 * COUPLED:vat-calculation: cart
 */
private int calculateVat(int netPence) {
    ...
}
// COUPLED:vat-calculation:END
```
```toml
["COUPLED:vat-calculation:"]
relations = ["same-as"]
```

`COUPLED:vat-calculation:END` closes each block, so the marker covers the whole function. Without it, a marker covers only the line after it.

---

### A runtime version pinned in several files

```yaml
# .github/workflows/ci.yml
python-version: "3.12"         # COUPLED:python-version: ci
```
```dockerfile
# Dockerfile
# COUPLED:python-version: docker
FROM python:3.12-slim
```
```toml
["COUPLED:python-version:"]
relations = ["="]
files = ["./.python-version"]
```

`.python-version` can't take a comment, so the registry names it, and the lint checks its one line against the others, and reports it if it's missing. Versions match on the parts both give, so `3.12` and `3.12.4` agree.

---

### An upload limit that must be larger at the proxy than in the app

```nginx
# nginx/default.conf
client_max_body_size 10m;      # COUPLED:upload-size-limit: nginx
```
```python
# app/settings.py
MAX_UPLOAD_MB = 8              # COUPLED:upload-size-limit: app
```
```toml
["COUPLED:upload-size-limit:"]
relations = ["nginx >= app"]
```

---

### A load-balancer idle timeout that must be shorter than the app's keep-alive timeout

```js
// server.js
server.keepAliveTimeout = 65_000;  // COUPLED:keepalive-timeout: server
```
```markdown
<!-- docs/external/aws-alb.md -->
Idle timeout: `60` s (EC2 console > Load balancers > prod-alb > Attributes). COUPLED:keepalive-timeout: alb
```
```toml
["COUPLED:keepalive-timeout:"]
relations = ["server > alb * 1000"]
```

The formula converts units: the app's value is in ms, the load balancer's in s.

---

### More forms

A margin, with `+` and `-`: the proxy waits at least 5 s longer than the app.

```toml
["COUPLED:request-timeout-chain:"]
relations = ["proxy >= app + 5"]
```

A selector, for a line holding more than the value:

```sh
APP_URL=http://localhost:8080  # COUPLED:dev-port: url
HTTP_PORT=8080                 # COUPLED:dev-port: port
```
```toml
["COUPLED:dev-port:"]
relations = ["url = port"]
select = { url = ':(\d+)$' }
```

Two files that can't take a comment, and no marker at all:

```toml
["COUPLED:node-version:"]
relations = ["./.nvmrc = ./package.json#/engines/node"]
```

A file in another repository, which the lint names as not checked:

```toml
["COUPLED:coverage-listing-shape:"]
relations = ["go same-shape //github.com/ianflanagan1/code-rulebook/schema/coverage.schema.json"]
```

Lists that must contain each other:

```toml
["COUPLED:disabled-functions:"]
relations = ["php-ini subset-of phpstan"]
```

## Format

The skill, [SKILL.md](skills/ianf-coupled-tags/SKILL.md), and [coupled-tags-lint's README](https://github.com/ianflanagan1/coupled-tags-lint#markers-and-the-registry) give the format in full: markers and blocks, the registry's tables and relations, how values are read and compared, the reviewed section, and the settings, including `tag-message`, which follows each label with a message for readers who don't know the convention.

### Choosing a key

Name the invariant the group protects, not where it lives: `request-timeout-chain`, not `nginx-timeouts`. If an unrelated setting could plausibly carry the key, it's too vague. Name each label for its site's place in the group: `nginx`, `app`, `ci`.

### Other repositories

Each end of a coupling across repositories carries a marker, and each repository's registry describes its own side, naming the other's files with `//<git-host>/<owner>/<name>/<path>`. The lint doesn't read other repositories, since which revision to compare against, and how to reach it, depend on how they're released; it names them in its status line as not checked.

### External systems

When the other end lives in no repository at all (a cloud console, DNS, a provider's dashboard), describe its **current** configuration in `docs/external/<service>.md`, and mark each value there. The search then finds the doc, and the doc says what to change and where.

Another repository is never an external system, even when it isn't checked out: its end can carry a marker, so mark both ends and link them with `//` refs rather than writing a doc that copies the other repository's values.

## Claude Code

The `ianf-coupled-tags` skill teaches Claude the convention:

- **Adding:** `/ianf-coupled-tags <this> with <that> [as <key>]`. Claude finds every site, marks each one, writes the group's table, checks the relations hold and runs `coupled-tags-lint --fix --update`, which needs to be on your PATH. If you don't give a key, it proposes one and waits for your choice.
- **Honouring:** before editing anything marked `COUPLED:`, Claude searches for the key, reads the group, and updates every site.

Clone to `~/projects/claude/coupled-tags`, then link the skill into your skills folder:

```sh
ln -s ~/projects/claude/coupled-tags/skills/ianf-coupled-tags ~/.claude/skills/ianf-coupled-tags
```

It's invoked as `/ianf-coupled-tags`. The `ianf-` prefix keeps it from colliding with other skills of the same name.

To share it with a repository's contributors, copy the skill into its `.claude/skills/ianf-coupled-tags/` instead. `SKILL.md` starts with `<!-- COUPLED:IGNORE-FILE -->`, so coupled-tags-lint and its hooks skip the copy's example markers there, or wherever else it's put, with no `exclude` in the repository's settings.

### Hooks

A skill's description doesn't guarantee Claude loads it just because it's editing a marked line. coupled-tags-lint's `coupled-tags-hook` does: as a `PostToolUse` hook on Read it shows Claude the groups in each file it reads, and as a `PreToolUse` hook on Edit, MultiEdit and Write it stops the first edit to a marked line in a session until Claude has seen the group. [Its README](https://github.com/ianflanagan1/coupled-tags-lint#the-claude-code-hooks) says how to add them to `~/.claude/settings.json`.
