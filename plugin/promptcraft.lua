-- plugin/promptcraft.lua
-- Neovim起動時に自動ロードされ、setup() を呼ぶ
if vim.fn.has("nvim-0.7") == 1 then
  -- Luaファイルを読み込み
  require("promptcraft").setup()
end

