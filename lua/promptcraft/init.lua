-- lua/promptcraft/init.lua
local M = {}

-- 選択されているファイルのパス一覧を保持
-- 実際には、:PromptCraftPickFiles などで埋める想定
M.selected_files = {}

-- NUI Layout の参照を格納
M.current_layout = nil

-- それぞれのバッファ番号
M.prompt_buf = nil
M.filelist_buf = nil

--------------------------------------------------------------------------------
-- finalize: プロンプトと選択ファイルの中身を合体してクリップボードへコピー
--------------------------------------------------------------------------------
function M.finalize()
  if not M.prompt_buf then
    print("No prompt buffer found. Did you run :PromptCraftStart ?")
    return
  end

  -- 1) プロンプトエリアのテキスト
  local prompt_lines = vim.api.nvim_buf_get_lines(M.prompt_buf, 0, -1, false)

  -- 2) 選択ファイルの実際の中身をまとめる
  local file_contents = {}
  for _, filepath in ipairs(M.selected_files) do
    local f = io.open(filepath, "r")
    if f then
      table.insert(file_contents, ("## File: %s"):format(filepath))
      for line in f:lines() do
        table.insert(file_contents, line)
      end
      f:close()
      table.insert(file_contents, "") -- 空行区切り
    else
      table.insert(file_contents, ("## [Error] Could not open file: %s"):format(filepath))
    end
  end

  -- 3) 合体
  local final_lines = {}
  vim.list_extend(final_lines, prompt_lines)
  table.insert(final_lines, "")
  table.insert(final_lines, "## Files included:")
  vim.list_extend(final_lines, file_contents)

  -- 4) クリップボードへコピー
  local text = table.concat(final_lines, "\n")
  vim.fn.setreg("+", text)
  print("Prompt + selected files have been copied to the system clipboard.")

  -- レイアウトを閉じる
  if M.current_layout then
    M.current_layout:unmount()
    M.current_layout = nil
  end
end

--------------------------------------------------------------------------------
-- PromptCraftStart: 右側に縦分割されたペインを表示
--   - 上半分: プロンプト入力
--   - 下半分: 選択ファイル一覧
-- ノーマルモードで <CR> を押すと finalize() を呼んでクリップボード書き込み
--------------------------------------------------------------------------------
function M.start()
  local Layout = require("nui.layout")
  local Split = require("nui.split")
  local event = require("nui.utils.autocmd").event

  -- ========== 右ペインを構成するための2つのSplitを用意 (上/下) ==========
  -- 上ペイン: プロンプト入力
  local prompt_split = Split({
    relative = "editor",
    position = "center",
    size = 1,  -- Layout側で最終的に大きさを決めるので仮設定
    buf_options = {
      modifiable = true,
      readonly = false,
    },
  })
  -- 下ペイン: 選択ファイル一覧
  local filelist_split = Split({
    relative = "editor",
    position = "center",
    size = 1,
    buf_options = {
      modifiable = false, -- ファイル一覧は参照のみと想定
      readonly = false,
    },
  })

  -- バッファ番号を記録
  M.prompt_buf = prompt_split.bufnr
  M.filelist_buf = filelist_split.bufnr

  -- 上ペインに初期メッセージをセット
  vim.api.nvim_buf_set_lines(M.prompt_buf, 0, -1, false, {
    "## Write your request (prompt) below.",
    "",
  })

  -- 下ペインに「選択ファイル一覧」を列挙
  local filelist_lines = { "## Selected Files", "" }
  for _, path in ipairs(M.selected_files) do
    table.insert(filelist_lines, path)
  end
  vim.api.nvim_buf_set_lines(M.filelist_buf, 0, -1, false, filelist_lines)

  -- ========== ENTERキーで finalize() を呼び出すマッピングを設定 ==========
  local function set_enter_mapping(bufnr)
    vim.api.nvim_buf_set_keymap(
      bufnr,
      "n",          -- ノーマルモード
      "<CR>",       -- Enterキー
      -- コマンド呼び出し: Lua関数 M.finalize() を呼ぶ
      -- <Cmd>lua require("promptcraft").finalize()<CR> の形がシンプル
      "<Cmd>lua require('promptcraft').finalize()<CR>",
      { noremap = true, silent = true }
    )
  end

  set_enter_mapping(M.prompt_buf)
  set_enter_mapping(M.filelist_buf)

  -- ========== 左右のレイアウト全体を組み立てる ==========
  -- 今回は画面全体を埋め尽くしつつ、左70%は何もしない（元のバッファ）扱いで空Boxに
  -- 右30%部分をさらに上下分割: prompt_split (50%), filelist_split (50%)
  local layout = Layout({
    relative = "editor",
    position = "center",
    size = {
      width = "100%",
      height = "100%",
    },
  }, {
    -- 1段目: 横方向に2つのBox
    Layout.Box({}, { size = "70%" }),  -- 左側を空Boxにする
    Layout.Box(
      Layout(
        {
          -- 右側レイアウトの設定
          -- relative/position/sizeは親Layoutで制御されるので省略可
        },
        {
          -- 上下分割
          Layout.Box(prompt_split,    { size = "50%" }),
          Layout.Box(filelist_split, { size = "50%" }),
        }
      ), 
      { size = "30%" }
    ),
  })

  -- レイアウトをマウント(描画)
  layout:mount()

  -- 後で閉じるために保存
  M.current_layout = layout

  -- もしペインを離れたら自動で閉じたいなどの挙動が必要なら、以下のように設定
  prompt_split:on({ event.BufLeave, event.WinLeave }, function()
    -- layout:unmount()
  end)
  filelist_split:on({ event.BufLeave, event.WinLeave }, function()
    -- layout:unmount()
  end)

  print("PromptCraft UI started. Write prompt in top split, see files in bottom split. Press <CR> to finalize.")
end

--------------------------------------------------------------------------------
-- プラグインセットアップ
--------------------------------------------------------------------------------
function M.setup()
  -- 適当なユーザコマンドを生やす
  vim.api.nvim_create_user_command("PromptCraftStart", function()
    M.start()
  end, {})
end

return M

