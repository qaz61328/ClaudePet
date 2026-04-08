# 常見問題

## 授權

### 如何關閉權限通知？

請到 偏好設定 視窗勾選「在終端機授權」即可。開啟後 ClaudePet 不再攔截工具授權，實際的核准操作會回到 Claude Code 終端機內建的對話框，可以看到完整的 diff 和指令細節。

### 需要授權的時候，按了「永遠允許」後，下次還是會跳出授權通知

「永遠允許」的選項目前是針對當前 session 的，並不會跨 session 記憶。這是因為 Claude Code 的工具授權機制本身就是基於 session 的，沒有提供跨 session 的持久化選項。

若想要跨 session 永久允許某些工具，請在 `.claude/settings.json` 中手動添加相應的授權設定。

### Plan Mode 第一次使用會跳出寫入權限確認

每次新對話第一次進入 Plan Mode 時，Claude 需要把計畫寫入 `.claude/plans/` 目錄下的 MD 檔。Claude Code 的權限機制會在第一次寫入時跳出確認。

在 `~/.claude/settings.json` 的 `permissions.allow` 陣列中加入以下規則即可解決：

```json
"Write(*/.claude/plans/*)"
```

加入後 Plan Mode 寫入計畫檔不再需要手動確認。

## 閒聊

### 閒聊功能怎麼運作的？

ClaudePet 偵測到所有 Claude Code session 結束後，等一段時間（約 5 分鐘加隨機偏移），跑外部 shell script 呼叫 LLM 產生一句符合角色的閒聊。腳本會自動偵測可用 provider：Anthropic API、AWS Bedrock、Claude Code CLI（`claude -p --bare`）。

整個過程在 ClaudePet 程序內完成，不會跑 Claude Code subagent、終端機不會有任何輸出。每次閒聊會消耗少量 token（一次 LLM 呼叫），請留意 API 用量。

### 閒聊功能沒反應

1. 到 偏好設定 視窗（一般 頁籤）勾選「啟用閒聊功能」（預設關閉）
2. 確認有可用的 LLM provider（`ANTHROPIC_API_KEY` 有設、AWS CLI 有設好、或 `claude` CLI 有裝）
3. 閒聊只在所有 Claude Code session 結束後等約 5 分鐘才觸發
4. 確認 `scripts/generate-chatter.sh` 有執行權限（`chmod +x scripts/generate-chatter.sh`）

## 角色與自訂

### 建立的角色不符合想要的樣子

執行 `/create-persona` 時，試著提供更具體的外觀描述。像是顏色、服裝風格、配件、髮型等細節都能幫助產生更好的結果。例如：「藍色身體、圓框眼鏡、橘色貓耳」會比「一個可愛角色」好得多。

### 可以自己放喜歡的角色圖嗎？

可以。把 sprite PNG 放到對應角色的 `Personas/<id>/` 目錄下，檔名遵循 `<state>_<number>.png` 的格式即可（例如 `idle_1.png`、`idle_2.png`、`bow_1.png` 等）。每個動畫狀態至少需要 2 張圖，但可以放超過 4 張。

### 可以放自訂音效嗎？

可以。每個角色都能有自己的音效。把音效檔放到對應角色的 `Personas/<id>/` 目錄下即可。啟動音效支援 `startup.mp3`；通知音效支援 `notify.mp3`；授權音效支援 `authorize.mp3`，支援三種格式：AIF、WAV、MP3。如果找不到自訂音效，會自動使用內建預設音效。

### 可以讓角色自由走動嗎？

不覺得一個會自己在畫面上動來動去的小幫手**有點干擾**工作嗎？目前沒有規劃這個功能。

## 已知問題（我知道問題，期待大神來幫我修）

### Claude Code 的 Dream 功能會跳出授權通知

Dream 模式在背景執行工具呼叫時，會跟一般操作一樣觸發 PreToolUse hook，目前尚無解決方法。

### Auto Edit Mode 仍然會跳出授權或通知氣泡

Claude Code 在 Auto Edit Mode 下雖然會跳過自己的授權提示，但 PreToolUse hook 照樣觸發。Hook 無法區分一般模式和 Auto Edit Mode，所以 ClaudePet 會照常顯示授權氣泡（或「在終端機授權」模式下的通知氣泡）。目前尚無解決方法。

### Grep 和 Glob 工具不會走 ClaudePet 授權

PreToolUse hook 只攔截具破壞性或互動性的工具（Bash、Edit、Write 等）。Grep 和 Glob 是唯讀搜尋工具，授權會回退到 Claude Code 終端機內建 UI，不經過 ClaudePet 的授權泡泡。

### 編輯 `.claude/` 目錄下的檔案不會走 ClaudePet 授權

Claude Code 編輯 `.claude/` 目錄下的檔案（skills、settings 等）時，會使用內建的設定保護機制，不走一般的 PreToolUse hook 流程。終端機會顯示特殊對話框，帶有「allow Claude to edit its own settings for this session」的選項。這類編輯不會觸發 ClaudePet 的授權泡泡。目前無法修復，這是 Claude Code 的內部行為。
