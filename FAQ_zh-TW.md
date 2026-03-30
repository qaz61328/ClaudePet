# 常見問題

## 授權

### 如何關閉權限通知？

刪除 `~/.claude/settings.json` 中的 `PreToolUse` hook 即可。ClaudePet 仍會顯示工作完成的通知，但不再攔截工具授權。

### 需要授權的時候，看不到詳細要授權什麼

在狀態列選單勾選「在終端機授權」。開啟後 ClaudePet 只會通知您需要授權，不再攔截授權內容。實際的核准操作會回到 Claude Code 終端機內建的對話框，可以看到完整的 diff 和指令細節。

### 需要授權的時候，按了「永遠允許」後，下次還是會跳出授權通知

「永遠允許」的選項目前是針對當前 session 的，並不會跨 session 記憶。這是因為 Claude Code 的工具授權機制本身就是基於 session 的，沒有提供跨 session 的持久化選項。

若想要跨 session 永久允許某些工具，請在 `.claude/settings.json` 中手動添加相應的授權設定。

## 閒聊

### 為什麼有時候會突然跑 Agent？

那是閒聊功能。ClaudePet 會消耗少量 token，透過 subagent 用 AI 產生符合當下情境的台詞。你可以從狀態列選單的「閒聊功能」關閉這個功能。注意 agent 的執行過程一定會顯示在終端機上，這部分無法隱藏。

### `.claude/scheduled_tasks.lock` 是什麼？

這個檔案不是 ClaudePet 產生的，而是 Claude Code 自己的排程機制。只要任何 session 使用 `CronCreate` 建立 cron job，Claude Code 就會在該專案的 `.claude/` 目錄下放這個 lock file。

因為 `~/.claude/CLAUDE.md` 中的閒聊指示會讓 Claude 在每個 session 開始時建立 cron job，所以這個檔案會出現在你工作的每個專案中。

你可以把它加入 `.gitignore_global` 來忽略，或者如果你完全不想要閒聊功能，把 `~/.claude/CLAUDE.md` 中所有閒聊相關的指示刪除即可。

### 為什麼有時候閒聊 cron job 沒有啟動？

閒聊 cron job 是透過 `~/.claude/CLAUDE.md` 中的指示來設定的。有時候 Claude 會跳過它，原因包括：

1. 指示埋在檔案中後段，被大量其他指示稀釋
2. 對話開始時 Claude 的注意力集中在使用者的第一則訊息上
3. 「At the start of each session」這種描述容易被當成背景資訊跳過

最有效的改法：把 cron 設定指示搬到 `~/.claude/CLAUDE.md` 的最頂部，用更強制的語氣，獨立成一個區塊。

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
