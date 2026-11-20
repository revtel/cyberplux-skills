---
name: cyberplux-sbom-sync
description: Register a project on CyberPlux (cyberplux.com) and upload its SBOM / dependency list so the owner is alerted when an advisory or known vulnerability (OSV.dev) hits the exact installed versions. Use when the user asks to upload, sync or update an SBOM, dependency list, lockfile or package inventory to CyberPlux, to "register this project for security alerts", to set up automatic SBOM updates (hook, git hook, CI), or right after you added, removed or upgraded dependencies in a repository that has a .cyberplux file.
license: MIT
---

# CyberPlux SBOM sync

CyberPlux matches each registered project's packages against published advisories and OSV.dev, and emails / messages the owner when something affects the installed versions. This skill keeps that package list current.

Everything goes through one script, `scripts/cyberplux-sbom` (next to this file; call it by its full path). It never prints the API key.

| Command | What it does |
|---|---|
| `cyberplux-sbom status` | Config, where the key comes from, last sync, whether lockfiles changed |
| `cyberplux-sbom init [--project-key K] [--environment E] [--team-id T] [--branch B] [--path P]` | Writes `.cyberplux` (no secrets) at the repo root |
| `cyberplux-sbom register [--name N] [--repository-url U]` | Creates / updates the project on CyberPlux (once, before the first sync) |
| `cyberplux-sbom sync [--if-changed] [--any-branch] [--dry-run]` | Generates a CycloneDX SBOM and uploads it; replaces the project's package list |
| `cyberplux-sbom install-git-hooks` | Syncs in the background after commits / pulls on the tracked branch |

## Decide what to do

Run `status` first.

### Already set up (`.cyberplux` exists, key present)

Run `sync`. After you changed dependencies, sync only once the lockfile is final (after `npm install` / `uv lock` / `go mod tidy` and so on) and only on the tracked branch. The script refuses other branches: uploading from a feature branch would replace the production package list with unmerged dependencies. Do not pass `--any-branch` unless the user asks.

Report the summary line (packages, matching advisories). OSV.dev results arrive about a minute later. If the CyberPlux MCP tools (`security-alert-projects`) are connected, call `get_alerts` for the details. Otherwise point the user to https://cyberplux.com/account/projects.

### First time in this repository

1. **API key.** If `status` says the key is missing, ask the user to create one at https://cyberplux.com/account/projects and run `! <script> login` themselves. That command reads the key from the prompt. Never ask them to paste the key into the chat, and never put it in a file inside the repository. For CI, the key goes in a secret named `CYBERPLUX_API_KEY`.
2. **Project identity.** Run `init`. The project key defaults to the origin remote path (`github.com/owner/repo`). Ask the user for the environment if it is not production (`production`, `staging`, `development`, `test` or `other`). Ask for `--team-id` if the project belongs to a team (team ids come from MCP `get_account`). Ask for `--path` when the deployable app lives in a subdirectory of a monorepo.
3. **Register.** If the MCP tools are connected, prefer `register_project`. It also takes `system` components (OS, runtime, framework, database, with exact versions read from the machine, `node -v` or `/etc/os-release`, never guessed), and those catch advisories the lockfile cannot. Use the same `project_key` / `environment` / `team_id` as `.cyberplux`. Without MCP, run `register`.
4. **Sync.** Run `sync`.
5. **Keep it current.** Offer one or both:
   - **Claude Code:** the `cyberplux` plugin's Stop hook already syncs at the end of any turn that changed lockfiles in an opted-in repository. Nothing to install per repo.
   - **Any agent or human:** run `install-git-hooks`.
   - **Most accurate for production:** CI on the deployed branch. See `examples/github-actions.yml` in this skill's repository, or use the repository root as a GitHub Action.
6. Suggest committing `.cyberplux` so CI and teammates address the same project.

## SBOM generators

`generator = auto` picks the first one found: `syft`, then `trivy`, then `cdxgen`, then `npx @cyclonedx/cyclonedx-npm` (npm only, production dependencies, lockfile only). If none is installed, tell the user how to install syft (`brew install syft`, or https://github.com/anchore/syft#installation) instead of hand-writing a package list. For anything else, set `generator = command` and `command = <shell command writing CycloneDX or SPDX JSON to $SBOM_OUT>` in `.cyberplux`.

Prefer the SBOM of what is actually deployed. For a container image, use `command = syft <image> -o cyclonedx-json=$SBOM_OUT`.

## Errors

| Message | Meaning / fix |
|---|---|
| HTTP 401 | Key revoked or mistyped: create a new one, `login` again |
| HTTP 404 `project_not_found` | Not registered with this key / team: `register` (or MCP `register_project`) |
| HTTP 422 `too_many_components` | Over 5000 packages: scope `--path` to the deployed app, or use a production-only generator |
| HTTP 413 | SBOM over 40 MB decompressed: same as above |
| `skipped without purl` | Components the generator could not identify; usually vendored files, safe to ignore |
| HTTP 429 | 60 requests/min per key; wait a minute |

## Config file `.cyberplux`

Git-config syntax, committed to the repo, no secrets:

```ini
[project]
	key = github.com/acme/web
	environment = production
	branch = main          # only this branch syncs; "*" = any (default: origin's default branch)
	path = .               # subdirectory to scan
	generator = auto       # auto | syft | trivy | cdxgen | cyclonedx-npm | command
#	team-id = <uuid>
#	command = syft my-image:latest -o cyclonedx-json=$SBOM_OUT
```

Environment: `CYBERPLUX_API_KEY` (overrides `~/.config/cyberplux/api-key`), `CYBERPLUX_URL` (default `https://cyberplux.com`).
