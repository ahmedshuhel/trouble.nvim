local providers = require("trouble.providers")
local util = require("trouble.util")
local config = require("trouble.config")
local Text = require("trouble.text")
local folds = require("trouble.folds")

---@class Renderer
local renderer = {}

local signs = {}

local function get_icon(file)
  local ok, icons = pcall(require, "nvim-web-devicons")
  if not ok then
    util.warn(
      "'nvim-web-devicons' is not installed. Install it, or set icons=false in your configuration to disable this message"
    )
    return ""
  end
  local fname = vim.fn.fnamemodify(file, ":t")
  local ext = vim.fn.fnamemodify(file, ":e")
  return icons.get_icon(fname, ext, { default = true })
end

local function update_signs()
  signs = config.options.signs
  if config.options.use_lsp_diagnostic_signs then
    local lsp_signs = require("trouble.providers.lsp").get_signs()
    signs = vim.tbl_deep_extend("force", {}, signs, lsp_signs)
  end
end


---@param view TroubleView
function renderer.render(view, opts)
  opts = opts or {diagnostic_items = {}}
  local items = opts.diagnostic_items

  if #items == 0 then
    util.warn("no results")
  end

  local grouped = providers.group(items)
  local count = util.count(grouped)

  -- check for auto close
  if opts.auto and config.options.auto_close then
    if count == 0 then
      view:close()
      return
    end
  end

  -- Update lsp signs
  update_signs()

  local text = Text:new()
  view.items = {}

  text:nl()

  -- render file groups
  for filename, group_items in pairs(grouped) do
    if opts.open_folds then
      folds.open(filename)
    end
    if opts.close_folds then
      folds.close(filename)
    end
    renderer.render_file(view, text, filename, group_items)
  end

  view:render(text)
  if opts.focus then
    view:focus()
  end
end

---@param view View
---@param text Text
---@param items Item[]
---@param filename string
function renderer.render_file(view, text, filename, items)
  view.items[text.lineNr + 1] = { filename = filename, is_file = true }

  local count = util.count(items)

  text:render(" ")

  if folds.is_folded(filename) then
    text:render(config.options.fold_closed, "FoldIcon", " ")
  else
    text:render(config.options.fold_open, "FoldIcon", " ")
  end

  if config.options.icons then
    local icon, icon_hl = get_icon(filename)
    text:render(icon, icon_hl, { exact = true, append = " " })
  end

  text:render(vim.fn.fnamemodify(filename, ":p:."), "File", " ")
  text:render(" " .. count .. " ", "Count")
  text:nl()

  if not folds.is_folded(filename) then
    renderer.render_diagnostics(view, text, items)
  end
end

---@param view View
---@param text Text
---@param items Item[]
function renderer.render_diagnostics(view, text, items)
  for _, diag in ipairs(items) do
    view.items[text.lineNr + 1] = diag

    local sign = diag.sign or signs[string.lower(diag.type)]
    if not sign then
      sign = diag.type
    end

    local indent = "     "
    if config.options.indent_lines then
      indent = " │   "
    end

    local sign_hl = diag.sign_hl or ("TroubleSign" .. diag.type)

    text:render(indent, "Indent")
    text:render(sign .. "  ", sign_hl, { exact = true })
    text:render(diag.text, "Text" .. diag.type, " ")
    -- text:render(diag.type, diag.type, " ")

    if diag.source then
      text:render(diag.source, "Source")
    end
    if diag.code and diag.code ~= vim.NIL then
      text:render("(" .. diag.code .. ")", "Code")
    end

    text:render(" ")

    text:render("[" .. diag.lnum .. ", " .. diag.col .. "]", "Location")
    text:nl()
  end
end

return renderer
