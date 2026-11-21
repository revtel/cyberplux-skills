<p>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/cyberplux-logo-reverse.png">
    <img src="assets/cyberplux-logo.png" alt="CyberPlux" width="360">
  </picture>
</p>

# CyberPlux agent skills

**繁體中文** | [English](README.en.md)

讓 AI coding agent、git hook 或 CI 自動把專案的相依套件清單（SBOM）同步到 [CyberPlux](https://cyberplux.com)。

CyberPlux 是資安通報服務。它知道專案實際安裝的套件版本後，遇到下面兩種情況會用 email 或通訊軟體通知你：

- 新發布的通報影響到其中某個版本；
- [OSV.dev](https://osv.dev) 出現這些版本的已知漏洞。

通知準不準，取決於套件清單是不是最新的。這個 repo 負責讓清單跟著 lockfile 走。

## 目錄

- [內容](#內容)
- [運作方式](#運作方式)
- [需要什麼](#需要什麼)
- [設定步驟](#設定步驟)
- [自動更新](#自動更新)
- [指令](#指令)
- [設定檔](#設定檔)
- [疑難排解](#疑難排解)
- [安全性](#安全性)
- [移除](#移除)
- [使用的 API](#使用的-api)

## 內容

| 元件 | 位置 | 用途 |
|---|---|---|
| Agent skill | `skills/cyberplux-sbom-sync/SKILL.md` | Claude Code、Codex、Cursor、Gemini CLI 等支援 [Agent Skills](https://agentskills.io) 的 agent 讀了就知道怎麼登錄專案、上傳 SBOM |
| 指令稿 | `skills/cyberplux-sbom-sync/scripts/cyberplux-sbom` | 實際做事的 Bash 腳本，其他元件都呼叫它，也可以自己手動執行 |
| Claude Code hook | `hooks/` | Stop hook：agent 每輪結束時，lockfile 有變就重新上傳 |
| Git hooks | `cyberplux-sbom install-git-hooks` 安裝 | commit／pull／rebase 後重新上傳，不管 lockfile 是誰改的 |
| GitHub Action | `action.yml`、`examples/github-actions.yml` | 部署分支有變動時由 CI 上傳 |

## 運作方式

```
lockfile 變動 ──► cyberplux-sbom sync
                   1. 不在追蹤的分支 → 跳過
                   2. lockfile 指紋沒變 → 跳過
                   3. 產生 CycloneDX SBOM（syft／trivy／cdxgen／cyclonedx-npm）
                   4. gzip 後 POST 到 https://cyberplux.com/api/account/v1/sbom
                   5. CyberPlux 整份取代該專案的套件清單，比對通報並掃描 OSV.dev
                   6. 有東西影響到你的版本時收到通知
```

三條規則確保資料正確：

1. **上傳會整份取代**該專案、該環境的套件清單，所以內容必須是實際部署的版本。
2. **因此只有一個分支會同步**，預設是遠端的預設分支（`main`）。agent 在 feature branch 升級套件時不會上傳，要等變更合併進 `main`。否則還沒合併的套件會被當成正式環境。
3. **沒有 `.cyberplux` 檔的 repo 一律不動作**。全域安裝 Claude Code plugin 不會影響其他 repo。

## 需要什麼

- `bash`、`git`（2.31 以上）、`curl`、`gzip`。macOS、Linux 內建；Windows 請用 WSL 或 Git Bash。
- CyberPlux 帳號和**會員 API key**（`sam_` 開頭），在 <https://cyberplux.com/account/projects> 建立。
- 一個 SBOM 產生工具：

  | 工具 | 安裝 | 支援範圍 |
  |---|---|---|
  | **[syft](https://github.com/anchore/syft#installation)**（建議） | `brew install syft` | 所有常見語言，也支援 container image |
  | [trivy](https://trivy.dev) | `brew install trivy` | 所有常見語言 |
  | [cdxgen](https://github.com/CycloneDX/cdxgen) | `npm i -g @cyclonedx/cdxgen` | 所有常見語言 |
  | cyclonedx-npm | 不用裝（透過 `npx`） | 只有 npm 專案，只含正式相依 |

  腳本依上表順序使用第一個找到的工具。

- 選用：`jq`，輸出比較好讀。

## 設定步驟

### 1. 安裝 skill

**Claude Code**（skill 和自動 hook 是同一個 plugin）：

```text
/plugin marketplace add revtel/cyberplux-skills
/plugin install cyberplux@cyberplux
```

**其他 agent**：

```bash
npx skills add revtel/cyberplux-skills
```

或把 `skills/cyberplux-sbom-sync` 資料夾複製到 agent 的 skills 目錄（例如 `~/.codex/skills/`、`.cursor/skills/`）。

**不用 agent**：

```bash
git clone https://github.com/revtel/cyberplux-skills.git ~/.cyberplux-skills
ln -s ~/.cyberplux-skills/skills/cyberplux-sbom-sync/scripts/cyberplux-sbom /usr/local/bin/cyberplux-sbom
```

### 2. 存 API key

在 <https://cyberplux.com/account/projects> 建立 key，然後在自己的終端機執行（Claude Code 裡在指令前面加 `!`）：

```bash
cyberplux-sbom login
```

輸入時不會顯示，key 會存到 `~/.config/cyberplux/api-key`，權限 600。不要把 key 貼到 agent 對話裡，也不要 commit。

### 3. 登錄 repo

在 repo 裡打開 agent，說：

> 把這個專案登錄到 CyberPlux 並上傳 SBOM。

agent 會執行下面這些指令，你也可以自己跑：

```bash
cyberplux-sbom init       # 寫 .cyberplux；project key 預設是 origin 路徑，例如 github.com/acme/web
cyberplux-sbom register   # 在 CyberPlux 建立專案（只需一次）
cyberplux-sbom sync       # 產生 SBOM 並上傳
```

常用的 `init` 選項：

```bash
cyberplux-sbom init --environment staging --branch develop      # staging 環境，由 develop 分支更新
cyberplux-sbom init --path apps/web                             # monorepo：只掃一個 app
cyberplux-sbom init --team-id <uuid>                            # 團隊專案：所有成員都會收到通知
```

### 4. Commit `.cyberplux`

```bash
git add .cyberplux && git commit -m "Track dependencies on CyberPlux"
```

這個檔案不含任何機密。commit 之後，CI 和同事都會對應到同一個專案。

### 5. 開啟自動更新

從下一節挑一種或多種方式。

## 自動更新

| 方式 | 何時觸發 | 適合 | 設定 |
|---|---|---|---|
| **Claude Code hook** | agent 每輪結束、lockfile 有變時 | agent 在 `main` 上升級套件 | 裝好 plugin 就生效 |
| **Git hooks** | `commit`、`merge`／`pull`、`rebase` 後 | 任何 agent 或人在本機改動 | 每個 clone 執行一次 `cyberplux-sbom install-git-hooks` |
| **GitHub Action** | 部署分支有 lockfile 變動的 push，加上每週一次 | **正式環境最準**，CI 看到的就是合併後的內容 | 見下方 |

建議：**正式環境用 GitHub Action**，本機再加一種 hook 讓回饋更快。

### GitHub Action

1. 在 repo 的 **Settings → Secrets and variables → Actions** 新增 `CYBERPLUX_API_KEY`。
2. 把 [`examples/github-actions.yml`](examples/github-actions.yml) 複製到 `.github/workflows/cyberplux-sbom.yml`。重點是：

```yaml
steps:
  - uses: actions/checkout@v4
  - uses: revtel/cyberplux-skills@v0     # 正式使用請改釘 commit SHA
    with:
      api-key: ${{ secrets.CYBERPLUX_API_KEY }}
      # register: true                   # 專案還沒登錄時，第一次執行加這行
```

輸入參數：`api-key`（必填）、`project-key`、`environment`、`team-id`、`path`、`generator`、`register`、`url`。沒給 `project-key` 時，用 repo 裡的 `.cyberplux`，再沒有就用 `github.com/<owner>/<repo>`。Action 會自己安裝 syft。

### Container image

部署 container 的話，image 比原始碼更接近實際情況，因為它還包含作業系統套件和 base image。在 `.cyberplux` 設定：

```ini
[project]
	generator = command
	command = syft ghcr.io/acme/web:latest -o cyclonedx-json=$SBOM_OUT
```

## 指令

| 指令 | 說明 |
|---|---|
| `cyberplux-sbom login` | 從終端機讀取會員 key，存到 `~/.config/cyberplux/api-key`（600） |
| `cyberplux-sbom init [選項]` | 寫 `.cyberplux`。選項：`--project-key`、`--environment`、`--team-id`、`--branch`、`--path`、`--generator` |
| `cyberplux-sbom register [--name N] [--repository-url U]` | 在 CyberPlux 建立或更新專案 |
| `cyberplux-sbom sync` | 立即產生並上傳 |
| `cyberplux-sbom sync --if-changed` | lockfile 自上次上傳後有變才上傳；不在追蹤分支或沒有 `.cyberplux` 時安靜跳過（hook 用的就是這個） |
| `cyberplux-sbom sync --dry-run` | 只產生 SBOM、顯示會送出什麼，不上傳 |
| `cyberplux-sbom sync --any-branch` | 不在追蹤分支也上傳 |
| `cyberplux-sbom status` | 顯示專案、key 來源、上次同步時間、lockfile 是否變動 |
| `cyberplux-sbom install-git-hooks` | 在這個 clone 安裝 `post-commit`、`post-merge`、`post-rewrite` hook |

## 設定檔

`.cyberplux`（git config 格式，要 commit，不含機密）：

```ini
[project]
	key = github.com/acme/web   # 必填；1-120 字元：英數字與 . _ / @ : + -
	environment = production    # production | staging | development | test | other
	branch = main               # 只有這個分支會同步；"*" 表示任何分支。預設是遠端的預設分支
	path = .                    # 要掃描的子目錄
	generator = auto            # auto | syft | trivy | cdxgen | cyclonedx-npm | command
	team-id = <uuid>            # 選填：團隊專案
	command = ...               # generator = command 時：把 CycloneDX／SPDX JSON 寫到 $SBOM_OUT
```

同一個 `key` 加 `environment` 永遠對應同一個專案，所以正式和 staging 可以分開登錄。

環境變數：`CYBERPLUX_API_KEY`（會員 key，優先於檔案，CI 用這個）、`CYBERPLUX_URL`（預設 `https://cyberplux.com`）、`XDG_CONFIG_HOME`（key 存放位置，預設 `~/.config`）。

腳本只在 `.git/` 裡寫兩個檔案，不會被 commit：`cyberplux-sbom.state`（上次上傳的指紋與時間）和 `cyberplux-sbom.log`（git hook 的輸出）。

## 疑難排解

| 狀況 | 原因與處理 |
|---|---|
| `no API key` | 執行 `cyberplux-sbom login`，或設定 `CYBERPLUX_API_KEY` |
| `HTTP 401` | key 被撤銷或打錯，建立新 key 後重新 `login` |
| `HTTP 404 project_not_found` | 這把 key（或團隊）沒有這個專案，執行 `cyberplux-sbom register` |
| `HTTP 422 too_many_components` | 超過 5000 個套件，用 `--path` 縮小到實際部署的 app |
| `HTTP 413` | SBOM 解壓縮後超過 40 MB，處理方式同上 |
| `HTTP 429` | 超過每把 key 每分鐘 60 次，等一分鐘 |
| `on branch 'x', but production tracks 'main'` | 這是預期行為（見[運作方式](#運作方式)）。切回追蹤分支；真的要上傳就加 `--any-branch` |
| `no SBOM generator found` | 安裝 syft（見[需要什麼](#需要什麼)） |
| `components skipped without purl` | 工具辨識不出的檔案（通常是 vendored 程式碼），可忽略 |
| git hook 沒動作 | 看 `.git/cyberplux-sbom.log`。Husky 等工具會管理 `core.hooksPath`，可能覆寫 hook，請把 `"$(git rev-parse --git-path hooks)/cyberplux-sbom" sync --if-changed --quiet &` 加到你自己的 hook |
| Claude Code hook 沒動作 | 只在有 `.cyberplux`、位於追蹤分支、lockfile 有變動時才執行。用 `cyberplux-sbom status` 檢查 |

## 安全性

- API key 只存在 `CYBERPLUX_API_KEY` 或 `~/.config/cyberplux/api-key`（權限 600）。腳本不會印出 key，skill 也要求 agent 讓使用者自己執行 `login`。
- 會員 key 只能讀寫該會員（與其團隊）的專案資料，碰不到 CyberPlux 的其他東西，隨時可以在 <https://cyberplux.com/account/projects> 撤銷。
- 會送出的資料：SBOM 裡的套件名稱、版本、package URL，以及 project key 和環境。不會送出原始碼。
- CI 請把 key 放在 secret，並把 action 釘在 commit SHA。
- 資安問題請透過本 repo 的 GitHub security advisory 回報。

## 移除

- Claude Code：`/plugin uninstall cyberplux@cyberplux`
- Git hooks：刪掉 `.git/hooks/post-commit`、`post-merge`、`post-rewrite` 裡標記 `# cyberplux-sbom` 的那幾行，再刪除 `.git/hooks/cyberplux-sbom`
- Key：`rm ~/.config/cyberplux/api-key`，並在網站上撤銷
- 專案：在 <https://cyberplux.com/account/projects> 刪除

## 使用的 API

兩個端點都用 `Authorization: Bearer sam_…` 驗證。

- `POST /api/account/v1/sbom?project_key=…&environment=…[&team_id=…]`：body 是 CycloneDX JSON（1.2 以上）或 SPDX JSON（2.2 以上）的 SBOM，可加 `Content-Encoding: gzip`（請求上限 4.5 MB）。上傳會整份取代專案的套件清單，最多 5000 個套件。
- `POST /api/account/mcp`：MCP 伺服器，提供 `register_project`、`get_alerts`、`get_project` 等工具。把 agent 接上它，就能一併登錄 runtime、作業系統等系統元件，也能直接查詢通知：

  ```bash
  claude mcp add --transport http security-alert-projects https://cyberplux.com/api/account/mcp \
    --header "Authorization: Bearer sam_..."
  ```

## 授權

[MIT](LICENSE)
