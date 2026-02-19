local M = {}
M.slots = {}

local data_dir = vim.fn.stdpath("data") .. "/hooks"
vim.fn.mkdir(data_dir, "p")

local ns_id = vim.api.nvim_create_namespace("Hooks")

---Find path where hooks are saved depending on context.
---@return string
local function _get_path()
  local result = vim.system({ "git", "rev-parse", "--show-toplevel" }, { text = true }):wait()
  local context = result.code ~= 0 and "global" or result.stdout:gsub("\n", ""):gsub("/", "_")
  return data_dir .. "/" .. context
end

---Save current state
local function _save_state()
  vim.fn.writefile({ vim.json.encode(M.slots) }, _get_path())
  vim.api.nvim_exec_autocmds("User", { pattern = "HooksChanged" })
end

---Load slots from disk
---@return string[]
local function _load_state()
  local path = _get_path()
  if vim.fn.filereadable(path) == 0 then
    _save_state()
  end
  return vim.json.decode(table.concat(vim.fn.readfile(path)))
end

---Return formatted lines for menu buffer
---@return string[]
local function _get_formatted_lines()
  local lines = {}
  for i, filepath in ipairs(M.slots) do
    table.insert(lines, string.format("[%d] = %s", i, filepath))
  end
  return lines
end

---Validate lines from menu
---@param lines string[]
---@return boolean, integer[]
local function _validate_lines(lines)
  local errors = {}
  for i, line in ipairs(lines) do
    local sep = string.find(line, "=")
    if not sep then
      table.insert(errors, i)
    else
      local filepath = vim.fn.trim(string.sub(line, sep + 1))
      if vim.fn.filereadable(vim.fn.expand(filepath)) == 0 then
        table.insert(errors, i)
      end
    end
  end
  return #errors == 0, errors
end

---Find index of filepath in slots
---@param filepath string
---@return integer|nil
local function _find_index(filepath)
  for i, fp in ipairs(M.slots) do
    if fp == filepath then
      return i
    end
  end
  return nil
end

-- ============================================
-- Action: Add
-- ============================================

function M.add_at_start()
  M.slots = _load_state()
  local current_file = vim.fn.expand("%:p")
  if current_file == "" or vim.bo.buftype ~= "" then
    return
  end
  if _find_index(current_file) then
    vim.notify("Hooks: File already in list", vim.log.levels.WARN)
    return
  end
  table.insert(M.slots, 1, current_file)
  _save_state()
  vim.notify("Hooks: Added at [1]", vim.log.levels.INFO)
end

function M.add_at_end()
  M.slots = _load_state()
  local current_file = vim.fn.expand("%:p")
  if current_file == "" or vim.bo.buftype ~= "" then
    return
  end
  if _find_index(current_file) then
    vim.notify("Hooks: File already in list", vim.log.levels.WARN)
    return
  end
  table.insert(M.slots, current_file)
  _save_state()
  vim.notify("Hooks: Added at [" .. #M.slots .. "]", vim.log.levels.INFO)
end

---@param position integer
function M.insert(position)
  M.slots = _load_state()
  local current_file = vim.fn.expand("%:p")
  if current_file == "" or vim.bo.buftype ~= "" then
    return
  end
  if _find_index(current_file) then
    vim.notify("Hooks: File already in list", vim.log.levels.WARN)
    return
  end
  position = math.max(1, math.min(position, #M.slots + 1))
  table.insert(M.slots, position, current_file)
  _save_state()
  vim.notify("Hooks: Inserted at [" .. position .. "]", vim.log.levels.INFO)
end

-- ============================================
-- Action: Remove
-- ============================================

---@param index integer
function M.remove(index)
  M.slots = _load_state()
  if index < 1 or index > #M.slots then
    vim.notify("Hooks: Invalid index [" .. index .. "]", vim.log.levels.WARN)
    return
  end
  local filepath = M.slots[index]
  table.remove(M.slots, index)
  _save_state()
  vim.notify("Hooks: Removed [" .. index .. "] " .. filepath, vim.log.levels.INFO)
end

function M.remove_current()
  M.slots = _load_state()
  local current_file = vim.fn.expand("%:p")
  local idx = _find_index(current_file)
  if not idx then
    vim.notify("Hooks: Current file is not a hook", vim.log.levels.WARN)
    return
  end
  table.remove(M.slots, idx)
  _save_state()
  vim.notify("Hooks: Removed [" .. idx .. "]", vim.log.levels.INFO)
end

-- ============================================
-- Action: Jump
-- ============================================

---@param index integer
function M.jump(index)
  M.slots = _load_state()
  local filepath = M.slots[index]
  if filepath then
    vim.cmd.edit(filepath)
  else
    vim.notify("Hooks: No hook at [" .. index .. "]", vim.log.levels.WARN)
  end
end

function M.next()
  M.slots = _load_state()
  if #M.slots == 0 then
    vim.notify("Hooks: No hooks defined", vim.log.levels.WARN)
    return
  end
  local current_file = vim.fn.expand("%:p")
  local idx = _find_index(current_file) or 0
  local next_idx = (idx % #M.slots) + 1
  M.jump(next_idx)
end

function M.prev()
  M.slots = _load_state()
  if #M.slots == 0 then
    vim.notify("Hooks: No hooks defined", vim.log.levels.WARN)
    return
  end
  local current_file = vim.fn.expand("%:p")
  local idx = _find_index(current_file) or 2
  local prev_idx = ((idx - 2 + #M.slots) % #M.slots) + 1
  M.jump(prev_idx)
end

-- ============================================
-- Action: Move
-- ============================================

function M.move_left()
  M.slots = _load_state()
  local current_file = vim.fn.expand("%:p")
  local idx = _find_index(current_file)
  if not idx then
    vim.notify("Hooks: Current file is not a hook", vim.log.levels.WARN)
    return
  end
  if idx == 1 then
    vim.notify("Hooks: Already at first position", vim.log.levels.WARN)
    return
  end
  -- Swap with previous
  M.slots[idx], M.slots[idx - 1] = M.slots[idx - 1], M.slots[idx]
  _save_state()
  vim.notify("Hooks: Moved to [" .. (idx - 1) .. "]", vim.log.levels.INFO)
end

function M.move_right()
  M.slots = _load_state()
  local current_file = vim.fn.expand("%:p")
  local idx = _find_index(current_file)
  if not idx then
    vim.notify("Hooks: Current file is not a hook", vim.log.levels.WARN)
    return
  end
  if idx == #M.slots then
    vim.notify("Hooks: Already at last position", vim.log.levels.WARN)
    return
  end
  -- Swap with next
  M.slots[idx], M.slots[idx + 1] = M.slots[idx + 1], M.slots[idx]
  _save_state()
  vim.notify("Hooks: Moved to [" .. (idx + 1) .. "]", vim.log.levels.INFO)
end

-- ============================================
-- Action: Menu
-- ============================================

function M.menu()
  M.slots = _load_state()

  local menu_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("buftype", "acwrite", { buf = menu_buf })
  vim.api.nvim_set_option_value("bufhidden", "delete", { buf = menu_buf })
  vim.api.nvim_buf_set_name(menu_buf, "Hooks-Menu")
  vim.api.nvim_buf_set_lines(menu_buf, 0, -1, false, _get_formatted_lines())
  vim.api.nvim_set_option_value("modified", false, { buf = menu_buf })

  vim.keymap.set("n", "<ESC>", "<CMD>q<CR>", { buffer = menu_buf, silent = true })

  local width = math.floor(vim.o.columns * 0.6)
  local height = math.floor(vim.o.lines * 0.6)
  local menu_win = vim.api.nvim_open_win(menu_buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = "Hooks Menu",
    title_pos = "center",
    footer = ":w to save | :q or ESC to quit",
    footer_pos = "center",
  })

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = menu_buf,
    desc = "Save Hooks state",
    callback = function()
      vim.api.nvim_buf_clear_namespace(menu_buf, ns_id, 0, -1)
      local lines = vim.api.nvim_buf_get_lines(menu_buf, 0, -1, false)
      local valid, errors = _validate_lines(lines)

      if not valid then
        for _, line_num in ipairs(errors) do
          vim.api.nvim_buf_set_extmark(menu_buf, ns_id, line_num - 1, 0, {
            virt_text = { { "X", "ErrorMsg" } },
            virt_text_pos = "eol",
          })
        end
        vim.notify("Hooks: Invalid filepaths", vim.log.levels.ERROR)
        return
      end

      -- Extract filepaths (ignore whatever indices were in brackets)
      M.slots = {}
      for _, line in ipairs(lines) do
        local sep = string.find(line, "=")
        local filepath = vim.fn.trim(string.sub(line, sep + 1))
        table.insert(M.slots, filepath)
      end

      _save_state()
      vim.api.nvim_set_option_value("modified", false, { buf = menu_buf })
      vim.notify("Hooks: Saved!", vim.log.levels.INFO)
      vim.api.nvim_win_close(menu_win, true)
    end,
  })
end

return M
