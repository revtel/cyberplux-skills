# CyberPlux agent skills

**English** | [繁體中文](README.zh-TW.md)

Keep your project's dependency list (SBOM) on [CyberPlux](https://cyberplux.com) up to date, automatically, from your AI coding agent, your git hooks or your CI.

CyberPlux is a security advisory service. Once it knows the exact package versions a project uses, it alerts you by email or chat in two cases:

- a newly published advisory affects one of those versions, or
- a known vulnerability in one of those versions appears on [OSV.dev](https://osv.dev).

The alerts are only as good as the package list. This repository makes sure the list follows your lockfiles.

## Contents

- [What is in this repository](#what-is-in-this-repository)
- [How it works](#how-it-works)
- [Requirements](#requirements)
- [Setup](#setup)
- [Keeping the list current](#keeping-the-list-current)
- [Command reference](#command-reference)
- [Configuration reference](#configuration-reference)
- [Troubleshooting](#troubleshooting)
- [Security](#security)
- [Uninstall](#uninstall)
- [API used](#api-used)

## What is in this repository

| Part | Path | For |
|---|---|---|
| Agent skill | `skills/cyberplux-sbom-sync/SKILL.md` | Claude Code, Codex, Cursor, Gemini CLI and any other agent that reads [Agent Skills](https://agentskills.io). Tells the agent how to register a project and upload its SBOM. |
| CLI script | `skills/cyberplux-sbom-sync/scripts/cyberplux-sbom` | Does the actual work. Plain Bash; every other part calls it. You can also run it yourself. |
| Claude Code hook | `hooks/` | A Stop hook: after each agent turn, re-uploads if lockfiles changed. |
| Git hooks | installed by `cyberplux-sbom install-git-hooks` | Re-uploads after commit / pull / rebase, whoever changed the lockfile. |
| GitHub Action | `action.yml`, `examples/github-actions.yml` | Re-uploads from CI when the deployed branch changes. |

## How it works

```
lockfiles changed ──► cyberplux-sbom sync
                        1. skip if not on the tracked branch
                        2. skip if lockfile fingerprint is unchanged
                        3. generate a CycloneDX SBOM (syft / trivy / cdxgen / cyclonedx-npm)
                        4. gzip + POST to https://cyberplux.com/api/account/v1/sbom
                        5. CyberPlux replaces the project's package list,
                           matches advisories and scans OSV.dev
                        6. you get an alert when something affects your versions
```

Three rules keep the data correct:

1. **An upload replaces the whole package list** of that project and environment, so it must describe what is really deployed.
2. **That is why only one branch syncs**: by default the remote's default branch (`main`). If an agent upgrades a package on a feature branch, nothing is uploaded until that change reaches `main`. Otherwise unmerged dependencies would be reported as production.
3. **Nothing happens unless the repository opts in** with a `.cyberplux` file. Installing the Claude Code plugin globally does not touch other repositories.

## Requirements

- `bash`, `git` (2.31+), `curl`, `gzip`. Already present on macOS and Linux. On Windows use WSL or Git Bash.
- A CyberPlux account and a **member API key** (`sam_…`), created at <https://cyberplux.com/account/projects>.
- One SBOM generator:

  | Generator | Install | Covers |
  |---|---|---|
  | **[syft](https://github.com/anchore/syft#installation)** (recommended) | `brew install syft` or `curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh \| sh -s -- -b /usr/local/bin` | Every common ecosystem, plus container images |
  | [trivy](https://trivy.dev) | `brew install trivy` | Every common ecosystem |
  | [cdxgen](https://github.com/CycloneDX/cdxgen) | `npm i -g @cyclonedx/cdxgen` | Every common ecosystem |
  | cyclonedx-npm | nothing (run through `npx`) | npm projects only, production dependencies |

  The script uses the first one it finds, in that order.

- Optional: `jq`, for nicer output.

## Setup

### Step 1: Install the skill

**Claude Code** (skill and automatic hook in one plugin):

```text
/plugin marketplace add revtel/cyberplux-skills
/plugin install cyberplux@cyberplux
```

**Other agents:** use the [skills CLI](https://github.com/vercel-labs/skills):

```bash
npx skills add revtel/cyberplux-skills
```

Or copy the `skills/cyberplux-sbom-sync` folder into your agent's skills directory (for example `~/.codex/skills/` or `.cursor/skills/`).

**Without an agent:** clone the repository and put the script on your `PATH`:

```bash
git clone https://github.com/revtel/cyberplux-skills.git ~/.cyberplux-skills
ln -s ~/.cyberplux-skills/skills/cyberplux-sbom-sync/scripts/cyberplux-sbom /usr/local/bin/cyberplux-sbom
```

### Step 2: Save your API key

Create a key at <https://cyberplux.com/account/projects>, then run the following in your own terminal. In Claude Code, type `!` before the command.

```bash
cyberplux-sbom login
```

The key is read without echo and stored in `~/.config/cyberplux/api-key` with mode `600`. Do not paste the key into the agent chat, and do not commit it.

### Step 3: Register the repository

Open your agent in the repository and say:

> Register this project on CyberPlux and upload its SBOM.

The agent runs the commands below. You can also run them yourself:

```bash
cyberplux-sbom init       # writes .cyberplux; project key defaults to the origin path, e.g. github.com/acme/web
cyberplux-sbom register   # creates the project on CyberPlux (only needed once)
cyberplux-sbom sync       # generates the SBOM and uploads it
```

Common `init` options:

```bash
cyberplux-sbom init --environment staging --branch develop      # a staging profile fed from the develop branch
cyberplux-sbom init --path apps/web                             # monorepo: scan one app only
cyberplux-sbom init --team-id <uuid>                            # team project: every team member is alerted
```

### Step 4: Commit `.cyberplux`

```bash
git add .cyberplux && git commit -m "Track dependencies on CyberPlux"
```

The file contains no secrets. Committing it lets CI and teammates address the same project.

### Step 5: Turn on automatic updates

Choose one or more of the options in the next section.

## Keeping the list current

| Option | Triggers | Best for | Setup |
|---|---|---|---|
| **Claude Code hook** | End of each agent turn, if lockfiles changed | Agents upgrading dependencies on `main` | Already active after installing the plugin |
| **Git hooks** | After `commit`, `merge`/`pull`, `rebase` | Any agent or human, local work | `cyberplux-sbom install-git-hooks` (once per clone) |
| **GitHub Action** | Push to the deployed branch that touches a lockfile, plus a weekly run | **Production accuracy.** CI sees exactly what is merged. | See below |

We recommend the **GitHub Action for production**, plus one of the local hooks for fast feedback.

### GitHub Action

1. In the repository go to **Settings → Secrets and variables → Actions** and add `CYBERPLUX_API_KEY`.
2. Copy [`examples/github-actions.yml`](examples/github-actions.yml) to `.github/workflows/cyberplux-sbom.yml`. The core of it:

```yaml
on:
  push:
    branches: [main]
    paths: ["**/package-lock.json", "**/pnpm-lock.yaml", "**/poetry.lock", "**/go.sum", ".cyberplux"]  # …
jobs:
  sbom:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: revtel/cyberplux-skills@v0     # for production, pin a commit SHA instead of @v0
        with:
          api-key: ${{ secrets.CYBERPLUX_API_KEY }}
          # register: true                   # first run, if the project is not registered yet
```

Action inputs: `api-key` (required), `project-key`, `environment`, `team-id`, `path`, `generator`, `register`, `url`. Without `project-key` the action uses the committed `.cyberplux`, or `github.com/<owner>/<repo>`. The action installs syft by itself.

### Container images

If you deploy a container, the image is closer to the truth than the source tree, because it also contains OS packages and the base image. Set a custom generator in `.cyberplux`:

```ini
[project]
	generator = command
	command = syft ghcr.io/acme/web:latest -o cyclonedx-json=$SBOM_OUT
```

`$SBOM_OUT` is the file the script uploads.

## Command reference

| Command | Description |
|---|---|
| `cyberplux-sbom login` | Read a member key from the terminal and store it in `~/.config/cyberplux/api-key` (0600) |
| `cyberplux-sbom init [options]` | Write `.cyberplux`. Options: `--project-key`, `--environment`, `--team-id`, `--branch`, `--path`, `--generator` |
| `cyberplux-sbom register [--name N] [--repository-url U]` | Create or update the project on CyberPlux |
| `cyberplux-sbom sync` | Generate and upload now |
| `cyberplux-sbom sync --if-changed` | Upload only if lockfiles changed since the last upload. Silent no-op on other branches or in repositories without `.cyberplux` (what the hooks use) |
| `cyberplux-sbom sync --dry-run` | Generate the SBOM and show what would be sent, without uploading |
| `cyberplux-sbom sync --any-branch` | Upload from the current branch even if it is not the tracked one |
| `cyberplux-sbom status` | Show project, key source, last sync and whether lockfiles changed |
| `cyberplux-sbom install-git-hooks` | Install `post-commit`, `post-merge` and `post-rewrite` hooks in this clone |

## Configuration reference

`.cyberplux` (git-config syntax, committed, no secrets):

```ini
[project]
	key = github.com/acme/web   # required; 1-120 chars: letters, digits . _ / @ : + -
	environment = production    # production | staging | development | test | other
	branch = main               # only this branch syncs; "*" = any. Default: the remote's default branch
	path = .                    # subdirectory to scan
	generator = auto            # auto | syft | trivy | cdxgen | cyclonedx-npm | command
	team-id = <uuid>            # optional: team project
	command = ...               # with generator = command: writes CycloneDX/SPDX JSON to $SBOM_OUT
```

The same `key` plus `environment` always addresses the same project, so you can keep separate production and staging profiles.

Environment variables:

| Variable | Default | Purpose |
|---|---|---|
| `CYBERPLUX_API_KEY` | (none) | Member key; takes precedence over the stored file. Use it in CI |
| `CYBERPLUX_URL` | `https://cyberplux.com` | API base URL |
| `XDG_CONFIG_HOME` | `~/.config` | Where `cyberplux/api-key` is stored |

Files the script writes inside `.git/` (never committed): `cyberplux-sbom.state` (last uploaded fingerprint and time) and `cyberplux-sbom.log` (git hook output).

Lockfiles watched: `package-lock.json`, `npm-shrinkwrap.json`, `yarn.lock`, `pnpm-lock.yaml`, `bun.lock(b)`, `poetry.lock`, `Pipfile.lock`, `uv.lock`, `pdm.lock`, `requirements*.txt`, `go.sum`, `Cargo.lock`, `Gemfile.lock`, `composer.lock`, `packages.lock.json`, `gradle.lockfile`, `pubspec.lock`, `mix.lock`, `Package.resolved`, `Podfile.lock`.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `no API key` | Run `cyberplux-sbom login`, or set `CYBERPLUX_API_KEY` |
| `HTTP 401` | Key revoked or mistyped. Create a new key and `login` again |
| `HTTP 404 project_not_found` | The project is not registered for this key or team. Run `cyberplux-sbom register` |
| `HTTP 422 too_many_components` | More than 5000 packages. Narrow it with `--path` to the deployed app |
| `HTTP 413` | SBOM over 40 MB uncompressed. Same fix as above |
| `HTTP 429` | Rate limit (60 requests per minute per key). Wait a minute |
| `on branch 'x', but production tracks 'main'` | Intended, see [How it works](#how-it-works). Switch branches, or use `--any-branch` if you really mean it |
| `no SBOM generator found` | Install syft ([Requirements](#requirements)) |
| `components skipped without purl` | The generator could not identify some files (usually vendored code). Safe to ignore |
| Git hook did nothing | Check `.git/cyberplux-sbom.log`. Tools such as Husky manage `core.hooksPath` and may overwrite the hooks. Add `"$(git rev-parse --git-path hooks)/cyberplux-sbom" sync --if-changed --quiet &` to your own hook instead |
| Claude Code hook did nothing | It only acts in repositories with `.cyberplux`, on the tracked branch, when lockfiles changed. Run `cyberplux-sbom status` |

## Security

- The API key only lives in `CYBERPLUX_API_KEY` or `~/.config/cyberplux/api-key` (mode 600). The script never prints it, and the skill tells agents to let the user run `login` themselves.
- A member key can only read and write that member's (and their teams') project profiles. It has no other access to CyberPlux. You can revoke it at <https://cyberplux.com/account/projects> at any time.
- What is sent: package names, versions and package URLs from your SBOM, plus the project key and environment. No source code.
- In CI, store the key as a secret and pin the action to a commit SHA.
- Report security issues to the maintainers through GitHub security advisories on this repository.

## Uninstall

- Claude Code: `/plugin uninstall cyberplux@cyberplux`
- Git hooks: delete the lines marked `# cyberplux-sbom` in `.git/hooks/post-commit`, `post-merge` and `post-rewrite`, then delete `.git/hooks/cyberplux-sbom`
- Key: `rm ~/.config/cyberplux/api-key`, and revoke the key on the website
- Project: delete it at <https://cyberplux.com/account/projects>

## API used

Both endpoints authenticate with `Authorization: Bearer sam_…`.

- `POST /api/account/v1/sbom?project_key=…&environment=…[&team_id=…]`: the body is a CycloneDX JSON (1.2+) or SPDX JSON (2.2+) SBOM, optionally with `Content-Encoding: gzip` (request limit 4.5 MB). Replaces the project's package list. At most 5000 packages.
- `POST /api/account/mcp`: an MCP server with `register_project`, `get_alerts`, `get_project` and more. Connect your agent to it to also register runtimes and operating systems, and to read alerts directly:

  ```bash
  claude mcp add --transport http security-alert-projects https://cyberplux.com/api/account/mcp \
    --header "Authorization: Bearer sam_..."
  ```

## License

[MIT](LICENSE)
