local M = {}
M.slots = {}

local data_dir = vim.fn.stdpath("data") .. "/hooks"
vim.fn.mkdir(data_dir, "p")

local ns_id = vim.api.nvim_create_namespace("Hooks")

---Find path where arglst is saved depending on context.
---Context depends on which git repo user is in, otherwise fallback to global
---@return string
local function _get_path()
  local context

  local result = vim.system({ "git", "rev-parse", "--show-toplevel" }, { text = true }):wait()
  if result.code ~= 0 then
    context = "global"
  else
    context = result.stdout:gsub("\n", ""):gsub("/", "_")
  end

  return data_dir .. "/" .. context
end

---Save current state
local function _save_state()
  local path = _get_path()

  vim.fn.writefile({ vim.json.encode(M.slots) }, path)
  vim.api.nvim_exec_autocmds("User", { pattern = "HooksChanged" })
end

---Load slots depending on context.
---Context depends on which git repo user is in, otherwise fallback to global
---@return table<string|integer, string>
local function _load_state()
  local path = _get_path()

  -- If state file does not exist, write the file
  if vim.fn.filereadable(path) == 0 then
    _save_state()
  end

  local content = table.concat(vim.fn.readfile(path))
  return vim.json.decode(content)
end

---Return a sorted array of numeric keys
---@param tbl table<string, string>
---@return integer[]
local function _sorted_keys(tbl)
  local keys = {}
  for k, _ in pairs(tbl) do
    table.insert(keys, tonumber(k))
  end
  table.sort(keys)
  return keys
end

---Return an array of formatted lines for Menu's buffer
---@param slots table<string, string>
---@param sorted_keys integer[]
---@return string[]
local function _get_formatted_lines(slots, sorted_keys)
  local formatted_lines = {}
  for _, k in ipairs(sorted_keys) do
    table.insert(formatted_lines, string.format("[%d] = %s", k, slots[tostring(k)]))
  end

  return formatted_lines
end

---Validate the lines to ensure correct syntax
---Filepath needs to be valid
---Returns a boolean flag indicating if all lines are valid, and a table of the lines with errors
---@param lines string[]
---@return boolean, string[]
local function _validate_lines(lines)
  local is_all_valid = true
  local lines_with_errors = {}

  for i, line in ipairs(lines) do
    local is_valid_fp = true
    local is_valid_key = true
    local is_eq_exist = true

    local sep_start_index, _ = string.find(line, "=")

    if not sep_start_index then
      is_eq_exist = false
    end

    if is_eq_exist then
      local filepath = vim.fn.trim(string.sub(line, sep_start_index + 1))
      local key = string.match(line, "^%[(.-)%]")

      if vim.fn.filereadable(vim.fn.expand(filepath)) == 0 then
        is_valid_fp = false
      end

      if not (key and key:match("^[0-9]+$")) then
        is_valid_key = false
      end
    end

    if not (is_valid_fp and is_valid_key and is_eq_exist) then
      is_all_valid = false
      table.insert(lines_with_errors, i)
    end
  end

  return is_all_valid, lines_with_errors
end

-- ============================================
-- Action: Add
-- ============================================

---Check if file already exists in slots
---@param filepath string
---@return integer|nil
local function _find_key(filepath)
  for key, fp in pairs(M.slots) do
    if fp == filepath then
      return tonumber(key)
    end
  end
  return nil
end

---Insert current file at the start (position 1), pushing all others up
function M.add_at_start()
  M.slots = _load_state()
  local current_file = vim.fn.expand("%:p")

  if current_file == "" or vim.bo.buftype ~= "" then
    return
  end

  -- Check if already exists
  local existing_key = _find_key(current_file)
  if existing_key then
    vim.notify("Hooks: File already exists at [" .. existing_key .. "]", vim.log.levels.WARN)
    return
  end

  -- Shift all existing hooks up by 1
  local sorted_keys = _sorted_keys(M.slots)
  for i = #sorted_keys, 1, -1 do
    local old_key_num = sorted_keys[i]
    M.slots[tostring(old_key_num + 1)] = M.slots[tostring(old_key_num)]
  end
  
  -- Insert at position 1
  M.slots["1"] = current_file
  _save_state()

  vim.notify("Hooks: " .. current_file .. " inserted at [1]", vim.log.levels.INFO)
end

---Add current file at the end (highest number + 1)
function M.add_at_end()
  M.slots = _load_state()
  local current_file = vim.fn.expand("%:p")

  if current_file == "" or vim.bo.buftype ~= "" then
    return
  end

  -- Check if already exists
  local existing_key = _find_key(current_file)
  if existing_key then
    vim.notify("Hooks: File already exists at [" .. existing_key .. "]", vim.log.levels.WARN)
    return
  end
  
  local sorted_keys = _sorted_keys(M.slots)
  local new_key = #sorted_keys > 0 and sorted_keys[#sorted_keys] + 1 or 1

  M.slots[tostring(new_key)] = current_file
  _save_state()

  vim.notify("Hooks: " .. current_file .. " added at [" .. new_key .. "]", vim.log.levels.INFO)
end

---Insert current file at specific position, pushing others up
---@param position integer
function M.insert(position)
  M.slots = _load_state()
  local current_file = vim.fn.expand("%:p")

  if current_file == "" or vim.bo.buftype ~= "" then
    return
  end

  -- Check if already exists
  local existing_key = _find_key(current_file)
  if existing_key then
    vim.notify("Hooks: File already exists at [" .. existing_key .. "]", vim.log.levels.WARN)
    return
  end

  position = math.max(1, position)
  local sorted_keys = _sorted_keys(M.slots)
  
  -- If position is beyond end, just append
  if position > #sorted_keys + 1 then
    M.slots[tostring(position)] = current_file
  else
    -- Shift hooks at position and beyond up by 1
    for i = #sorted_keys, position, -1 do
      local old_key_num = sorted_keys[i]
      M.slots[tostring(old_key_num + 1)] = M.slots[tostring(old_key_num)]
    end
    M.slots[tostring(position)] = current_file
  end
  
  _save_state()
  vim.notify("Hooks: " .. current_file .. " inserted at [" .. position .. "]", vim.log.levels.INFO)
end

---Renumber keys to be contiguous after removal
---@param removed_key integer
local function _renumber_after_removal(removed_key)
  local new_slots = {}
  local sorted_keys = _sorted_keys(M.slots)
  
  local new_idx = 1
  for _, old_num in ipairs(sorted_keys) do
    new_slots[tostring(new_idx)] = M.slots[tostring(old_num)]
    new_idx = new_idx + 1
  end
  
  M.slots = new_slots
end

---Remove a hook by key and renumber to maintain contiguous indices
---@param key integer
function M.remove(key)
  M.slots = _load_state()
  local key_str = tostring(key)

  if not M.slots[key_str] then
    vim.notify("Hooks: No hook at [" .. key .. "]", vim.log.levels.WARN)
    return
  end

  local filepath = M.slots[key_str]
  M.slots[key_str] = nil
  _renumber_after_removal(key)
  _save_state()

  vim.notify("Hooks: Removed [" .. key .. "] " .. filepath, vim.log.levels.INFO)
end

---Remove current file from hooks and renumber
function M.remove_current()
  M.slots = _load_state()
  local current_file = vim.fn.expand("%:p")

  -- Find which key has current file
  local found_key = nil
  for key, filepath in pairs(M.slots) do
    if filepath == current_file then
      found_key = key
      break
    end
  end

  if not found_key then
    vim.notify("Hooks: Current file is not a hook", vim.log.levels.WARN)
    return
  end

  M.slots[found_key] = nil
  _renumber_after_removal(tonumber(found_key))
  _save_state()

  vim.notify("Hooks: Removed [" .. found_key .. "]", vim.log.levels.INFO)
end

-- ============================================
-- Action: Jump
-- ============================================

---Jump to the file registered to the specific key
---@param key integer
function M.jump(key)
  M.slots = _load_state()
  local filepath = M.slots[tostring(key)]

  if filepath then
    vim.cmd.edit(filepath)
  else
    vim.notify("Hooks: No hook at [" .. key .. "]", vim.log.levels.WARN)
  end
end

---Jump to the next slot (circular)
---If current file is not in slots, jumps to the first slot
function M.next()
  M.slots = _load_state()
  local sorted_keys = _sorted_keys(M.slots)

  if #sorted_keys == 0 then
    vim.notify("Hooks: No slots defined", vim.log.levels.WARN)
    return
  end

  local current_file = vim.fn.expand("%:p")
  local current_index = nil

  for i, key_num in ipairs(sorted_keys) do
    if M.slots[tostring(key_num)] == current_file then
      current_index = i
      break
    end
  end

  local next_index
  if current_index then
    next_index = (current_index % #sorted_keys) + 1
  else
    next_index = 1
  end

  M.jump(sorted_keys[next_index])
end

---Jump to the previous slot (circular)
---If current file is not in slots, jumps to the first slot
function M.prev()
  M.slots = _load_state()
  local sorted_keys = _sorted_keys(M.slots)

  if #sorted_keys == 0 then
    vim.notify("Hooks: No slots defined", vim.log.levels.WARN)
    return
  end

  local current_file = vim.fn.expand("%:p")
  local current_index = nil

  for i, key_num in ipairs(sorted_keys) do
    if M.slots[tostring(key_num)] == current_file then
      current_index = i
      break
    end
  end

  local prev_index
  if current_index then
    prev_index = ((current_index - 2 + #sorted_keys) % #sorted_keys) + 1
  else
    prev_index = 1
  end

  M.jump(sorted_keys[prev_index])
end

-- ============================================
-- Action: Move
-- ============================================

---Move current file's hook one position to the left (swap with previous)
function M.move_left()
  local current_file = vim.fn.expand("%:p")
  M.slots = _load_state()
  local sorted_keys = _sorted_keys(M.slots)

  -- Find current file's key
  local current_key = nil
  local current_idx = nil
  for i, key_num in ipairs(sorted_keys) do
    if M.slots[tostring(key_num)] == current_file then
      current_key = key_num
      current_idx = i
      break
    end
  end

  if not current_key then
    vim.notify("Hooks: Current file is not a hook", vim.log.levels.WARN)
    return
  end

  if current_idx == 1 then
    vim.notify("Hooks: Already at first position", vim.log.levels.WARN)
    return
  end

  -- Swap with previous
  local prev_key = sorted_keys[current_idx - 1]
  local from_val = M.slots[tostring(current_key)]
  local to_val = M.slots[tostring(prev_key)]
  M.slots[tostring(current_key)] = to_val
  M.slots[tostring(prev_key)] = from_val
  _save_state()

  vim.notify(string.format("Hooks: Moved [%d] <-> [%d]", current_key, prev_key), vim.log.levels.INFO)
end

---Move current file's hook one position to the right (swap with next)
function M.move_right()
  local current_file = vim.fn.expand("%:p")
  M.slots = _load_state()
  local sorted_keys = _sorted_keys(M.slots)

  -- Find current file's key
  local current_key = nil
  local current_idx = nil
  for i, key_num in ipairs(sorted_keys) do
    if M.slots[tostring(key_num)] == current_file then
      current_key = key_num
      current_idx = i
      break
    end
  end

  if not current_key then
    vim.notify("Hooks: Current file is not a hook", vim.log.levels.WARN)
    return
  end

  if current_idx == #sorted_keys then
    vim.notify("Hooks: Already at last position", vim.log.levels.WARN)
    return
  end

  -- Swap with next
  local next_key = sorted_keys[current_idx + 1]
  local from_val = M.slots[tostring(current_key)]
  local to_val = M.slots[tostring(next_key)]
  M.slots[tostring(current_key)] = to_val
  M.slots[tostring(next_key)] = from_val
  _save_state()

  vim.notify(string.format("Hooks: Moved [%d] <-> [%d]", current_key, next_key), vim.log.levels.INFO)
end

-- ============================================
-- Action: menu
-- ============================================

---Display Hooks's menu for editing
function M.menu()
  M.slots = _load_state()
  local sorted_keys = _sorted_keys(M.slots)
  local formatted_lines = _get_formatted_lines(M.slots, sorted_keys)

  -- Menu's buffers settings
  local menu_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("buftype", "acwrite", { buf = menu_buf })
  vim.api.nvim_set_option_value("bufhidden", "delete", { buf = menu_buf })
  vim.api.nvim_buf_set_name(menu_buf, "Hooks-Menu")

  vim.api.nvim_buf_set_lines(menu_buf, 0, -1, false, formatted_lines)

  -- Allow user to :q or <ESC> without prompting to save if there are no changes to the file
  vim.api.nvim_set_option_value("modified", false, { buf = menu_buf })

  vim.keymap.set("n", "<ESC>", "<CMD>q<CR>", { buffer = menu_buf, silent = true })

  -- Menu's floating window settings
  local width = math.floor(vim.o.columns * 0.6)
  local height = math.floor(vim.o.lines * 0.6)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local menu_win = vim.api.nvim_open_win(menu_buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = "Hooks Menu",
    title_pos = "center",
    footer = ":w to save | :q or ESC to quit",
    footer_pos = "center",
  })

  -- Save logic
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = menu_buf,
    desc = "Save Hooks state on write",
    callback = function(_)
      vim.api.nvim_buf_clear_namespace(menu_buf, ns_id, 0, -1)

      local new_lines = vim.api.nvim_buf_get_lines(menu_buf, 0, -1, false)

      local is_all_valid, lines_with_errors = _validate_lines(new_lines)

      if is_all_valid then
        M.slots = {}

        -- Extract filepaths and renumber contiguously
        local filepaths = {}
        for _, line in ipairs(new_lines) do
          local sep_start_index, _ = string.find(line, "=")
          local filepath = vim.fn.trim(string.sub(line, sep_start_index + 1))
          table.insert(filepaths, filepath)
        end

        -- Assign contiguous keys starting from 1
        for i, filepath in ipairs(filepaths) do
          M.slots[tostring(i)] = filepath
        end

        _save_state()

        vim.api.nvim_set_option_value("modified", false, { buf = menu_buf })
        vim.notify("Hooks: State saved!", vim.log.levels.INFO)
        vim.api.nvim_win_close(menu_win, true)
      else
        for _, line_num in ipairs(lines_with_errors) do
          vim.api.nvim_buf_set_extmark(menu_buf, ns_id, line_num - 1, 0, {
            virt_text = { { "X", "ErrorMsg" } },
            virt_text_pos = "eol",
          })
        end
        vim.notify(
          "Hooks: Please ensure syntax is correct ([<key>] = <valid fp>), and that the file exists!",
          vim.log.levels.ERROR
        )
      end
    end,
  })
end

return M
