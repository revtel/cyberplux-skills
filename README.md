# CyberPlux agent skills

Open-source agent skills and hooks that keep your project's **dependency list (SBOM)** on [CyberPlux](https://cyberplux.com) current. CyberPlux matches the exact installed versions against new security advisories and OSV.dev, and alerts you by email or chat when something affects them.

- **Skill** (`skills/cyberplux-sbom-sync`): lets Claude Code, Codex, Cursor, Gemini CLI or any [Agent Skills](https://agentskills.io) compatible agent register a project, generate a CycloneDX SBOM and upload it.
- **Claude Code hook**: at the end of any turn where lockfiles changed, the SBOM is regenerated and uploaded. Opt-in per repository, silent otherwise.
- **Git hooks**: the same for any agent or human, after commits and pulls.
- **GitHub Action**: uploads on every lockfile change on the deployed branch. This is the most accurate source for production.

All of them run one dependency-free Bash script (`cyberplux-sbom`, needs `git`, `curl`, `gzip` and an SBOM generator).

[中文說明在下方](#中文說明)

## Install

### Claude Code (skill + hook)

```text
/plugin marketplace add alanfeng99/cyberplux-skills
/plugin install cyberplux@cyberplux
```

### Other agents (skill only)

Copy `skills/cyberplux-sbom-sync` into your agent's skills folder (`~/.codex/skills/`, `.cursor/skills/`, `~/.gemini/skills/`, …), or:

```bash
npx skills add alanfeng99/cyberplux-skills
```

Then use `install-git-hooks` for automatic updates.

### SBOM generator

Install one: [syft](https://github.com/anchore/syft#installation) (`brew install syft`, recommended, every ecosystem), trivy or cdxgen. Projects that only use npm can rely on `npx @cyclonedx/cyclonedx-npm`, which is fetched automatically.

## Quick start

1. Create a member API key at <https://cyberplux.com/account/projects>.
2. In your repository, ask your agent: *"Register this project on CyberPlux and upload its SBOM."*

Or by hand (`cyberplux-sbom` is `skills/cyberplux-sbom-sync/scripts/cyberplux-sbom`):

```bash
cyberplux-sbom login                 # paste the key; stored in ~/.config/cyberplux/api-key (0600)
cyberplux-sbom init                  # writes .cyberplux; project key = origin path, e.g. github.com/acme/web
cyberplux-sbom register              # once
cyberplux-sbom sync                  # generate + upload
cyberplux-sbom install-git-hooks     # optional: keep it current without Claude Code
git add .cyberplux && git commit -m "Track dependencies on CyberPlux"
```

`.cyberplux` contains no secrets: project key, environment, tracked branch, scan path and generator. See [SKILL.md](skills/cyberplux-sbom-sync/SKILL.md#config-file-cyberplux).

## CI (GitHub Actions)

Add the secret `CYBERPLUX_API_KEY`, then copy [examples/github-actions.yml](examples/github-actions.yml):

```yaml
- uses: actions/checkout@v4
- uses: alanfeng99/cyberplux-skills@v0   # pin a commit SHA
  with:
    api-key: ${{ secrets.CYBERPLUX_API_KEY }}
```

## Design notes

- **Only the tracked branch syncs.** An upload replaces the environment's whole package list, so syncing from a feature branch would report unmerged dependencies as production. Hooks skip other branches silently; manual `sync` refuses unless you pass `--any-branch`.
- **Only when lockfiles change.** The script keeps a fingerprint of every lockfile (plus `.cyberplux`) in `.git/cyberplux-sbom.state`. Hooks cost a few milliseconds when nothing changed.
- **Opt-in per repository.** The Claude Code hook and the git hooks do nothing without a `.cyberplux` file.
- **The key never touches the repository or the agent's output.** It comes from `CYBERPLUX_API_KEY` or `~/.config/cyberplux/api-key`. Agents are told to have the user run `login` themselves.
- **Hooks never block.** The Claude Code hook reports failures as a message. Git hooks run in the background and log to `.git/cyberplux-sbom.log`.
- **Husky / `core.hooksPath`:** `install-git-hooks` writes into the active hooks directory. If a tool regenerates that directory, add the line `"$(git rev-parse --git-path hooks)/cyberplux-sbom" sync --if-changed --quiet &` to your own hook instead.

## API

The script uses two public endpoints, both authenticated with a member key (`sam_…`):

- `POST /api/account/v1/sbom?project_key=&environment=&team_id=`: body is a CycloneDX or SPDX JSON SBOM (gzip allowed), replacing the package list. Max 5000 packages.
- `POST /api/account/mcp`: MCP server (`register_project`, `get_alerts`, …). Connect it to your agent for richer use: `claude mcp add --transport http security-alert-projects https://cyberplux.com/api/account/mcp --header "Authorization: Bearer sam_..."`

## License

MIT

---

## 中文說明

讓 AI agent 把專案的 SBOM／相依套件清單登錄到 [CyberPlux](https://cyberplux.com)，之後有新通報或 OSV.dev 已知漏洞影響到你實際安裝的版本，就會用 email 或通訊軟體通知你。

- **Skill**：Claude Code、Codex、Cursor 等支援 Agent Skills 的 agent 都能用。跟 agent 說「把這個專案登錄到 CyberPlux 並上傳 SBOM」即可。
- **Claude Code hook**：一輪對話結束時，如果 lockfile 有變動，自動重新產生 SBOM 並上傳。只在有 `.cyberplux` 的 repo 生效，沒變動時不做任何事。
- **Git hooks**（`install-git-hooks`）：commit 或 pull 後在背景同步，不限 agent。
- **GitHub Action**：部署分支的 lockfile 一變就上傳。正式環境最準的是這個。

注意：上傳會整份取代該環境的套件清單，所以只有追蹤的分支（預設是 origin 的預設分支）會同步，feature branch 一律跳過，避免把還沒合併的套件當成正式環境。

API key 在 <https://cyberplux.com/account/projects> 建立，用 `cyberplux-sbom login` 存到 `~/.config/cyberplux/api-key`（權限 600）。不要放進 repo，也不要貼給 agent；CI 請用 secret `CYBERPLUX_API_KEY`。
