# 安裝指南

## 前置需求

- **macOS 13+**（Ventura 或更新版本）
- **Swift 5.9+**（沒有 Xcode Command Line Tools 的話，跑 `xcode-select --install` 安裝）
- **jq**（授權 hook 腳本會用到，用 `brew install jq` 安裝）

## 快速安裝

```bash
bash scripts/setup.sh
```

腳本會分四步走，每步都會問你要不要做。不想一個一個確認的話，加 `--yes`（閒聊 LLM provider 偵測在 `--yes` 模式下會跳過）：

```bash
bash scripts/setup.sh --yes
```

腳本做的事：

1. 編譯 release binary（`swift build -c release`）
2. 把 Claude Code hook 設定寫進 `~/.claude/settings.json`
3. 設定閒聊腳本，偵測可用的 LLM provider（Anthropic API、AWS Bedrock 或 Ollama）
4. 在你的 RC 檔（`~/.zshrc` 或 `~/.bashrc`）加上 `claude()` wrapper

裝完之後照平常一樣跑 `claude`，ClaudePet 會在背景自動啟動。

## 手動安裝

想自己一步步來的話，照這四步做。

### 1. 編譯

```bash
cd /path/to/ClaudePet
swift build -c release
```

Binary 會在 `.build/release/ClaudePet`。不需要外部套件。

### 2. 設定 Claude Code Hooks

在 `~/.claude/settings.json` 加入 hook 設定。把 `/path/to/ClaudePet` 換成你的實際路徑：

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/ClaudePet/hooks/notify-stop.sh",
            "async": true
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Read|Bash|Edit|Write|NotebookEdit|AskUserQuestion|ExitPlanMode|mcp__.*",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/ClaudePet/hooks/notify-permission.sh"
          }
        ]
      }
    ]
  },
  "permissions": {
    "allow": []
  }
}
```

已經有 `settings.json` 的話，把 `hooks` 合併進去就好。

### 3. 閒聊功能（Opt-in）

閒聊功能預設關閉，從狀態列選單開啟。

開啟後，ClaudePet 偵測到閒置狀態（所有 Claude Code session 結束）會啟動計時器（5 分鐘 ± 隨機偏移）。計時器到了就跑外部 shell script，透過 LLM API 產生一句符合角色的閒聊。

腳本解析順序：`Personas/<id>/generate-chatter.sh` → `scripts/generate-chatter.sh`。自動偵測可用 provider：Anthropic API（`ANTHROPIC_API_KEY`）、AWS Bedrock（`aws` CLI）、Ollama（localhost:11434）。

不需要修改 `~/.claude/CLAUDE.md`，閒聊完全在 ClaudePet 程序內運作。

### 4. Shell Wrapper（自動啟動）

在 `~/.zshrc`（或 `~/.bashrc`）加這段：

```bash
claude() {
  bash /path/to/ClaudePet/scripts/launch-pet.sh
  command claude "$@"
}
```

`launch-pet.sh` 會先打 `/health` 確認狀態。已經在跑就不會重複啟動。Binary 不存在的話會自動幫你 build。

改完 RC 檔後跑 `source ~/.zshrc`，或開新終端機。

## 升級

點狀態列選單的 **Check for Updates**，ClaudePet 會檢查最新的 [GitHub Release](https://github.com/qaz61328/ClaudePet/releases)，有新版的話自動拉取程式碼、重新編譯、更新設定、重啟。

手動升級：

```bash
git pull origin main
bash scripts/upgrade.sh
```

升級腳本做的事：
1. 重新編譯 release binary
2. 更新 `~/.claude/settings.json` 裡的 hooks（只更新還存在的 hook，不會把手動移除的加回去）
3. 移除 `~/.claude/CLAUDE.md` 裡的舊版閒聊設定（如果有的話）
4. 如果專案路徑有變，更新 shell wrapper
5. 重啟 ClaudePet

## 移除

```bash
bash scripts/uninstall.sh
```

腳本會先確認你要不要繼續，確認後：
1. 停止 ClaudePet 程序
2. 從 `~/.claude/settings.json` 移除 ClaudePet 的 hooks 和 permissions
3. 移除 `~/.claude/CLAUDE.md` 裡的舊版閒聊設定（如果有的話）
4. 從 RC 檔移除 `claude()` shell wrapper
5. 清除暫存檔（`$TMPDIR/claudepet-*`）

其他的 `settings.json` 和 `CLAUDE.md` 設定不受影響。腳本不會刪除 repo，要刪的話自己來：

```bash
rm -rf /path/to/ClaudePet
```

## 自訂角色

最快的方法：在 Claude Code 裡跑 `/create-persona`。它會問你角色設定，然後自動產生台詞、像素圖和音效。

要手動做的話，在 `Personas/<your-id>/` 建一個資料夾，裡面放：

- `persona.json`（台詞定義，格式參考 `.claude/commands/references/persona-schema.md`）
- 20 張 sprite PNG：`idle_1.png` 到 `idle_4.png`、`bow_1.png` 到 `bow_4.png`、`alert_1.png` 到 `alert_4.png`、`happy_1.png` 到 `happy_4.png`、`working_1.png` 到 `working_4.png`（64x64 像素，透明背景）
- 音效檔（可選，支援 .aif/.wav/.mp3）：`startup.aif`（啟動音效）、`notify.aif`（通知音效）、`authorize.aif`（授權音效）
- `chatter-prompt.md`（定義這個角色的閒聊行為，可選）

除了 `persona.json` 以外都是可選的。沒有 sprite 就用內建的，沒有音效就靜音。

切換角色在狀態列選單操作，選了什麼會記住，重啟也不會跑掉。選單最下面的「重新載入角色」可以抓到新加的角色，不需要重開 app。

## 全域快捷鍵

ClaudePet 會註冊系統級快捷鍵，不管當前焦點在哪個 app 都能觸發。不需要「輔助使用」權限。

### 預設鍵位

| 功能 | 快捷鍵 | 說明 |
|------|--------|------|
| 切換小幫手 | `⌃⌥P` | 顯示／隱藏小幫手 |
| 允許（授權） | `⌃⌥Y` | 批准目前的授權請求 |
| 永遠允許（授權） | `⌃⌥A` | 本次 session 內永遠允許 |
| 拒絕（授權） | `⌃⌥N` | 拒絕目前的授權請求 |

三個授權快捷鍵只有在授權泡泡顯示時才會生效，其他時候按了不會有反應。

### 自訂鍵位

點狀態列選單的「**快捷鍵設定⋯**」，會開啟設定視窗，每個功能一列。點擊錄製區，然後按下你要的修飾鍵＋按鍵組合就好。

- 至少要有一個修飾鍵（⌃、⌥、⇧ 或 ⌘）
- 按 **Esc** 取消錄製
- 按 **Delete** 清除設定
- 跟其他快捷鍵衝突的話會警告並拒絕

按「**還原預設值**」可以把所有快捷鍵重設回上面的預設。

自訂的鍵位會存在 UserDefaults，重啟也不會跑掉。

## Token 用量提醒

閒聊功能直接呼叫外部 LLM API（不經過 Claude Code）。每次產生閒聊時，會把角色 prompt 加上近期情境送去 API，產出一句短台詞。費用取決於你用的 provider：Anthropic API 用 Claude Haiku、AWS Bedrock 用最便宜的 Claude 模型、Ollama 在本機跑零成本。

想關掉的話，從狀態列選單切換「閒聊模式」就好。馬上生效，不用重啟。

## 常見問題

**ClaudePet 啟動不了**

確認 binary 存在：
```bash
ls .build/release/ClaudePet
```
沒有的話重新 build：`swift build -c release`

確認 port 23987 沒被占用：
```bash
lsof -i :23987
```

**授權泡泡不出現**

確認 hook 有設好：
```bash
cat ~/.claude/settings.json | jq '.hooks'
```

確認 `jq` 有裝：
```bash
which jq
```

Hook 腳本需要 `jq` 來解析 Claude Code 的 JSON 輸入。沒裝的話，PreToolUse hook 會靜默退出，Claude Code 會退回預設的終端機權限流程。

**ClaudePet 在跑但 Claude Code 沒反應**

直接測 server：
```bash
curl http://127.0.0.1:23987/health
```

應該拿到 `{"status":"ok","persona":"default",...}`。如果請求失敗，表示 ClaudePet 沒在跑，或其他東西佔了 port 23987。

**閒聊不會觸發**

1. 確認狀態列選單裡「閒聊模式」有開
2. 確認有可用的 LLM provider（`ANTHROPIC_API_KEY` 有設、`aws` CLI 有設好、或 Ollama 在跑）
3. 確認 `scripts/generate-chatter.sh` 有執行權限
4. 閒聊只在所有 session 結束後等 5 分鐘才觸發，Claude Code 還在跑的時候不會觸發
5. 手動測 endpoint：`curl -X POST http://127.0.0.1:23987/chatter -H "Content-Type: application/json" -H "X-ClaudePet-Token: $(cat $TMPDIR/claudepet-token)" -d '{"message":"test"}'`

**角色卡在 working 動畫**

Working 狀態會追蹤進行中的 Claude Code session。如果 session 當掉了沒送 `/working active=false`，狀態會卡住。Session 3 分鐘後會自動過期，等一下就好，或者從狀態列選單重啟 ClaudePet。
