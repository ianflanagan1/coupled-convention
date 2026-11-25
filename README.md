# COUPLED markers

A convention for code and values that must change together but can't share a single source of truth. Each place carries a greppable marker, `COUPLED:<key>: <label>`, and the repository's registry, `coupled-registry.toml`, describes each group: how its places relate. Whoever changes one runs `grep --recursive --line-number 'COUPLED:<key>:'` and finds the others, and the group's table beside them.

It comes with a lint, [coupled](https://github.com/ianflanagan1/coupled), which checks that markers and registry agree, that the relations it can compare hold, between values, sets of names and blocks of text, and that no group has changed since it was last reviewed, and which gives Claude Code two hooks. This repository holds the Claude Code skill.

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
relations = ["invoice same-text cart"]
```

`COUPLED:vat-calculation:END` closes each block, so the marker covers the whole function. Without it, a marker covers only the line after it. The two copies are in one language, so `same-text` has the lint compare them line by line. Copies in two languages would be `same-as`, which the lint can't compare: it records each block, and reports a change to one until the group is reviewed.

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
relations = ["ci = docker", "pinned = docker"]
has-no-marker = { pinned = "./.python-version" }
```

`.python-version` can't take a comment, so the registry gives it a label, and the lint checks its one line against the others, and reports it if it's missing. Versions match on the parts both give, so `3.12` and `3.12.4` agree.

---

### An upload limit that must be larger at the proxy than in the app

```nginx
# nginx/default.conf
client_max_body_size 10m;      # COUPLED:upload-size-limit: proxy
```
```python
# app/settings.py
MAX_UPLOAD_MB = 8              # COUPLED:upload-size-limit: app
```
```toml
["COUPLED:upload-size-limit:"]
relations = ["proxy >= app"]
why = "the proxy rejects a larger body before the app sees it"
```

---

### A load-balancer idle timeout that must be shorter than the app's keep-alive timeout

```js
// server.js
server.keepAliveTimeout = 65_000;  // COUPLED:keepalive-timeout: server
```
```markdown
<!-- docs/external/aws-alb.md -->
Idle timeout: `60` s (EC2 console > Load balancers > prod-alb > Attributes). COUPLED:keepalive-timeout: load-balancer
```
```toml
["COUPLED:keepalive-timeout:"]
relations = ["app > load-balancer * 1000"]
```

The formula converts units: the app's value is in ms, the load balancer's in s.

---

### More forms

A margin, with `+` and `-`: the proxy waits at least 5 s longer than the app.

```toml
["COUPLED:request-timeout-chain:"]
relations = ["proxy >= app + 5"]
```

A regex after the label, between slashes, for a line holding more than the value:

```sh
APP_URL=http://localhost:8080  # COUPLED:dev-port: url /:(\d+)$/
HTTP_PORT=8080                 # COUPLED:dev-port: port
```
```toml
["COUPLED:dev-port:"]
relations = ["url = port"]
```

A file that can't hold a marker takes its regex in a table:

```toml
["COUPLED:dev-port:"]
relations = ["dev = port"]
has-no-marker = { dev = { file = "./web/package.json", regex = 'localhost:(\d+)' } }
```

Two files that can't take a comment, and no marker at all:

```toml
["COUPLED:node-version:"]
relations = ["nvmrc = engines"]
has-no-marker = { nvmrc = "./.nvmrc", engines = "./package.json#/engines/node" }
```

A site in another repository that keeps the group too, which the lint names as not checked:

```toml
["COUPLED:coverage-listing-shape:"]
relations = ["writer same-shape schema"]
in-another-registry = { schema = "//github.com/ianflanagan1/code-rulebook" }
why = "the rulebook's schema validates the listing this writes"
```

A group whose op the lint can't compare, such as `same-shape`, must say why its sites are coupled, since that's all that tells a reviewer what must hold.

Lists that must contain each other, which the lint compares by their members: the quoted values in each site's block, or what a regex picks out.

```ini
disable_functions = exec,passthru,shell_exec  ; COUPLED:disabled-functions: php-ini /[=,]\s*(\w+)/
```
```toml
["COUPLED:disabled-functions:"]
relations = ["php-ini subset-of phpstan"]
```

Prose that must stay true of the code it describes:

```toml
["COUPLED:password-rules:"]
relations = ["client same-as server", "help-page description-of server"]
why = "the form must refuse what the server would, and the help page says what both accept"
```

## Format

The skill, [SKILL.md](skills/ianf-coupled/SKILL.md), and [coupled's README](https://github.com/ianflanagan1/coupled#markers-and-the-registry) give the format in full: markers and blocks, the registry's tables and relations, the four kinds of op, how values, sets and text are read and compared, the reviewed section, and the settings, including `markers-show-relations` and `markers-point-to-registry`, which follow each label with its site's relations, and with a pointer for readers who don't know the convention.

### Choosing a key and labels

Name the invariant the group protects, not where it lives: `request-timeout-chain`, not `nginx-timeouts`. If an unrelated setting could plausibly carry the key, it's too vague.

Name each group's labels on their own, along one axis, the one way its sites differ that explains the relations, so each relation reads as the invariant: components (`proxy >= app`), the sides of a contract (`client`, `server`), the tools a pin is read by (`docker`, `ci`), or environments (`dev`, `prod`). Components take the project's own names first, from the Compose service that holds each site's file, as the project writes them; where none does, their role in whole words (`database`, not `db`). When one component holds several sites, add what each holds: `app-body`, `app-file`.

### Other repositories

A group across repositories has the same key in each, and each repository's registry describes only its own side, by a marker or a `has-no-marker` entry, and names the other's sites by their labels in `in-another-registry`, by the repository alone: `//<git-host>/<owner>/<name>`. So a file moves in one repository with no change to the other. A file in a repository that keeps no such group, such as a third party's published schema, goes in `has-no-marker` instead, as `//<git-host>/<owner>/<name>/<path>[#<pointer>]`. The lint doesn't read other repositories, since which revision to compare against, and how to reach it, depend on how they're released; it names them in its status line as not checked.

### External systems

When the other end lives in no repository at all (a cloud console, DNS, a provider's dashboard), prefer to describe its **current** configuration in `docs/external/<service>.md`, and mark each value there. The search then finds the doc, the doc says what to change and where, and the lint compares its values with the rest of the group.

When a doc isn't worth writing, name the site in the group's `has-no-file` instead, by a label, with where it's set, and relate it like any other:

```toml
["COUPLED:oauth-redirect:"]
relations = ["app = google"]
has-no-file = { google = "Google Cloud console > APIs & Services > Credentials > the web client > Authorised redirect URIs" }
```

The lint can't read its value and lists it as not checked, but the search for the key still finds the table, which says what to change and where.

Another repository is never an external system, even when it isn't checked out: its own registry can describe its end, so give the group to both and link them with `in-another-registry` entries rather than writing a doc that copies the other repository's values.

## Claude Code

The `ianf-coupled` skill teaches Claude the convention:

- **Adding:** `/ianf-coupled <this> with <that> [as <key>]`. Claude finds every site, marks each one, writes the group's table, checks the relations hold and runs `coupled --fix --update <key>`, which needs to be on your PATH. If you don't give a key, it proposes one and waits for your choice.
- **Honouring:** before editing anything marked `COUPLED:`, Claude searches for the key, reads the group, and updates every site.

Clone to `~/projects/claude/coupled-convention`, then link the skill into your skills folder:

```sh
ln -s ~/projects/claude/coupled-convention/skills/ianf-coupled ~/.claude/skills/ianf-coupled
```

It's invoked as `/ianf-coupled`. The `ianf-` prefix keeps it from colliding with other skills of the same name.

To share it with a repository's contributors, copy the skill into its `.claude/skills/ianf-coupled/` instead. `SKILL.md` starts with `<!-- COUPLED:IGNORE-FILE -->`, so coupled and its hooks skip the copy's example markers there, or wherever else it's put, with no `exclude` in the repository's settings.

### Hooks

A skill's description doesn't guarantee Claude loads it just because it's editing a marked line. coupled's `coupled-hook` does: as a `PostToolUse` hook on Read it shows Claude the groups in each file it reads, and as a `PreToolUse` hook on Edit, MultiEdit and Write it stops the first edit to a marked line in a session until Claude has seen the group. [Its README](https://github.com/ianflanagan1/coupled#the-claude-code-hooks) says how to add them to `~/.claude/settings.json`.
