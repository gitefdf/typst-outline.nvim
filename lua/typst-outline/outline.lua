local outline = {}

local highlights_set = false
local config = nil
local parser = nil

local function get_config()
  if not config then
    config = require("typst-outline").config
  end
  return config
end

local function get_parser()
  if not parser then
    parser = require("typst-outline.parser")
  end
  return parser
end

local function setup_highlights()
  if highlights_set then
    return
  end
  highlights_set = true
  local hl = get_config().highlights
  for i = 1, 9 do
    local name = "TypstOutlineH" .. i
    vim.api.nvim_set_hl(0, name, vim.tbl_extend("force", { default = true }, hl["H" .. i] or {}))
  end
  vim.api.nvim_set_hl(0, "TypstOutlineFile", vim.tbl_extend("force", { default = true }, hl.File or {}))
end

local states = {}

local function get_state()
  local tab = vim.api.nvim_get_current_tabpage()
  if not states[tab] then
    states[tab] = {
      winid = nil,
      bufnr = nil,
      main_file = nil,
      view_level = nil,
      display_map = {},
      hl_map = {},
      prev_win = nil,
      sync_file = nil,
      sync_lnum = 0,
      alt_buf = nil,
    }
  end
  return states[tab]
end

local ns = nil

local function get_main_file()
  local ok, main = pcall(vim.api.nvim_buf_get_var, 0, "typst_main")
  if ok and type(main) == "string" and vim.uv.fs_stat(vim.fn.resolve(main)) then
    return main
  end
  local fname = vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())
  if fname == "" then
    return nil
  end
  return get_parser().find_main(fname)
end

local function compute_numbering(headings)
  local counters = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }
  local numbers = {}
  for _, h in ipairs(headings) do
    if h.level == 0 then
      numbers[#numbers + 1] = ""
      goto continue
    end
    local L = h.level
    counters[L] = counters[L] + 1
    for i = L + 1, #counters do
      counters[i] = 0
    end
    local parts = {}
    for i = 1, L do
      parts[#parts + 1] = tostring(counters[i])
    end
    numbers[#numbers + 1] = table.concat(parts, ".")
    ::continue::
  end
  return numbers
end

local function heading_highlight(h)
  return "TypstOutlineH" .. math.min(h.level, 9)
end

local function update_winbar()
  local st = get_state()
  if not st.winid or not vim.api.nvim_win_is_valid(st.winid) then
    return
  end
  local level_str = st.view_level and (" [Lv%d]"):format(st.view_level) or " [All]"
  local main_str = st.main_file and vim.fn.fnamemodify(st.main_file, ":t") or ""
  vim.api.nvim_set_option_value("winbar", string.format("%%=" .. "%s%s", main_str, level_str), {
    scope = "local",
    win = st.winid,
  })
end

local function render()
  local st = get_state()
  if not st.bufnr or not vim.api.nvim_buf_is_valid(st.bufnr) then
    return
  end

  if not st.main_file or vim.uv.fs_stat(st.main_file) == nil then
    vim.api.nvim_set_option_value("modifiable", true, { buf = st.bufnr })
    vim.api.nvim_buf_set_lines(st.bufnr, 0, -1, false, { "(main file not found)" })
    vim.api.nvim_set_option_value("modifiable", false, { buf = st.bufnr })
    return
  end

  setup_highlights()

  local saved_lnum = 0
  if st.winid and vim.api.nvim_win_is_valid(st.winid) then
    saved_lnum = vim.api.nvim_win_get_cursor(st.winid)[1]
  end

  local ok, all = pcall(get_parser().parse, st.main_file, { max_depth = get_config().max_depth })
  if not ok then
    vim.notify("[TypstOutline] Parse error: " .. tostring(all), vim.log.levels.ERROR)
    return
  end

  local numbers = compute_numbering(all)

  local max_level = st.view_level or get_config().max_level
  local filtered = {}
  local filtered_numbers = {}
  for i, h in ipairs(all) do
    if not max_level or h.level <= max_level then
      filtered[#filtered + 1] = h
      filtered_numbers[#filtered_numbers + 1] = numbers[i]
    end
  end

  local display_lines = {}
  st.display_map = {}
  st.hl_map = {}
  st.sync_file = nil
  local prev_file = st.main_file
  local display_idx = 1

  local main_fname = vim.fn.fnamemodify(st.main_file, ":t")
  display_lines[1] = string.format("── %s ──", main_fname)
  st.display_map[1] = { file = st.main_file, lnum = 1, level = 0, text = "" }
  st.hl_map[1] = "TypstOutlineFile"

  for i, h in ipairs(filtered) do
    if h.file ~= prev_file then
      display_idx = display_idx + 1
      local fname = vim.fn.fnamemodify(h.file, ":t")
      display_lines[display_idx] = string.format("── %s ──", fname)
      st.display_map[display_idx] = { file = h.file, lnum = 1, level = 0, text = "" }
      st.hl_map[display_idx] = "TypstOutlineFile"
      prev_file = h.file
    end

    if h.level == 0 then
      goto continue_heading
    end

    display_idx = display_idx + 1
    if h.text == "" then
      display_lines[display_idx] = filtered_numbers[i]
    else
      display_lines[display_idx] = string.format("%s %s", filtered_numbers[i], h.text)
    end
    st.display_map[display_idx] = h
    st.hl_map[display_idx] = heading_highlight(h)

    ::continue_heading::
  end

  local old_lines = vim.api.nvim_buf_get_lines(st.bufnr, 0, -1, false)
  local changed = #old_lines ~= #display_lines
  if not changed then
    for i = 1, #old_lines do
      if old_lines[i] ~= display_lines[i] then
        changed = true
        break
      end
    end
  end

  if changed then
    vim.api.nvim_set_option_value("modifiable", true, { buf = st.bufnr })
    vim.api.nvim_buf_set_lines(st.bufnr, 0, -1, false, display_lines)
    vim.api.nvim_set_option_value("modifiable", false, { buf = st.bufnr })

    if not ns then
      ns = vim.api.nvim_create_namespace("typst_outline")
    end
    vim.api.nvim_buf_clear_namespace(st.bufnr, ns, 0, -1)

    for i, hl in ipairs(st.hl_map) do
      vim.api.nvim_buf_add_highlight(st.bufnr, ns, hl, i - 1, 0, -1)
    end

    if saved_lnum > 0 and st.winid and vim.api.nvim_win_is_valid(st.winid) then
      local max = vim.api.nvim_buf_line_count(st.bufnr)
      local target = math.min(saved_lnum, max)
      vim.api.nvim_win_set_cursor(st.winid, { target, 0 })
    end
  end

  update_winbar()
end

local function find_target_window(create)
  local st = get_state()
  if st.prev_win and vim.api.nvim_win_is_valid(st.prev_win) then
    local buf = vim.api.nvim_win_get_buf(st.prev_win)
    if vim.api.nvim_get_option_value("buftype", { buf = buf }) == "" then
      return st.prev_win
    end
  end
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if win ~= st.winid then
      local buf = vim.api.nvim_win_get_buf(win)
      local bt = vim.api.nvim_get_option_value("buftype", { buf = buf })
      if bt == "" then
        return win
      end
    end
  end
  if not create then
    return nil
  end
  vim.cmd("topleft vsplit")
  return vim.api.nvim_get_current_win()
end

local function jump()
  local st = get_state()
  local lnum = vim.api.nvim_win_get_cursor(st.winid)[1]
  local h = st.display_map[lnum]
  if not h then
    return
  end

  local swb = vim.o.switchbuf
  if swb:find("useopen") or swb:find("usetab") then
    local wid = vim.fn.bufwinid(h.file)
    if wid ~= -1 and wid ~= st.winid then
      vim.api.nvim_set_current_win(wid)
      vim.api.nvim_win_set_cursor(0, { h.lnum, 0 })
      vim.cmd("normal! zz")
      return
    end
  end

  local target = find_target_window(true)
  if target then
    vim.api.nvim_set_current_win(target)
  end

  local target_file = vim.fn.resolve(h.file)
  local bufnr = vim.fn.bufnr(target_file)
  if bufnr ~= -1 then
    vim.api.nvim_set_current_buf(bufnr)
  else
    vim.cmd("edit " .. vim.fn.fnameescape(target_file))
  end
  vim.api.nvim_win_set_cursor(0, { h.lnum, 0 })
  vim.cmd("normal! zz")
end

local function navigate_heading(dir)
  local st = get_state()
  local cur = vim.api.nvim_win_get_cursor(st.winid)[1]
  local dm = st.display_map
  local max = #dm
  for i = 1, max do
    local idx = dir == 1 and cur + i or cur - i
    if idx < 1 or idx > max then
      break
    end
    local h = dm[idx]
    if h and h.level == 1 then
      vim.api.nvim_win_set_cursor(st.winid, { idx, 0 })
      vim.cmd("normal! zz")
      return
    end
  end
end

local function set_level(level)
  get_state().view_level = level
  render()
end

function outline.toggle()
  local st = get_state()
  if st.winid and vim.api.nvim_win_is_valid(st.winid) then
    outline.close()
    return
  end

  local main = get_main_file()
  if not main then
    vim.notify("[TypstOutline] No Typst file found", vim.log.levels.WARN)
    return
  end
  st.main_file = main
  st.view_level = get_config().max_level
  st.prev_win = vim.api.nvim_get_current_win()
  st.alt_buf = vim.fn.bufnr("#")

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
  vim.api.nvim_set_option_value("swapfile", false, { buf = buf })
  vim.api.nvim_buf_set_name(buf, "[TypstOutline]")
  st.bufnr = buf

  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buf,
    once = true,
    callback = function()
      if st.bufnr == buf then
        st.winid = nil
        st.bufnr = nil
        st.display_map = {}
        st.hl_map = {}
      end
    end,
  })

  local direction = get_config().split_direction or "left"
  local cmd = direction == "right" and "botright vsplit"
    or direction == "above" and "topleft split"
    or direction == "below" and "botright split"
    or "topleft vsplit"

  vim.cmd(cmd)
  vim.api.nvim_win_set_buf(0, buf)
  st.winid = vim.api.nvim_get_current_win()

  vim.api.nvim_win_set_width(st.winid, get_config().split_width or 35)
  vim.api.nvim_set_option_value("number", false, { scope = "local", win = st.winid })
  vim.api.nvim_set_option_value("relativenumber", false, { scope = "local", win = st.winid })
  vim.api.nvim_set_option_value("signcolumn", "no", { scope = "local", win = st.winid })
  vim.api.nvim_set_option_value("foldcolumn", "0", { scope = "local", win = st.winid })
  vim.api.nvim_set_option_value("cursorline", true, { scope = "local", win = st.winid })
  vim.api.nvim_set_option_value("winfixwidth", true, { scope = "local", win = st.winid })

  local opts = { buffer = buf, nowait = true, silent = true }
  vim.keymap.set("n", "<CR>", jump, opts)
  vim.keymap.set("n", "<2-LeftMouse>", jump, opts)
  vim.keymap.set("n", "q", function() outline.close() end, opts)
  vim.keymap.set("n", "r", function() outline.refresh() end, opts)
  vim.keymap.set("n", "o", jump, opts)
  vim.keymap.set("n", "]]", function() navigate_heading(1) end, opts)
  vim.keymap.set("n", "[[", function() navigate_heading(-1) end, opts)
  vim.keymap.set("n", "<Esc>", function() outline.close() end, opts)
  vim.keymap.set("n", "0", function() set_level(nil) end, { buffer = buf, nowait = true, silent = true, desc = "Show all levels" })
  for i = 1, 9 do
    vim.keymap.set("n", tostring(i), function() set_level(i) end, {
      buffer = buf,
      nowait = true,
      silent = true,
      desc = string.format("Show up to level %d", i),
    })
  end

  outline.refresh()
  if get_config().focus_on_open then
    outline.sync()
  end
end

function outline.is_open()
  local st = get_state()
  return st.winid and vim.api.nvim_win_is_valid(st.winid)
end

function outline.close()
  local st = get_state()
  if st.winid and vim.api.nvim_win_is_valid(st.winid) then
    if #vim.api.nvim_list_wins() == 1 then
      vim.api.nvim_set_current_win(st.winid)
      vim.cmd("enew")
    else
      vim.api.nvim_win_close(st.winid, true)
    end
  end
  if st.prev_win and vim.api.nvim_win_is_valid(st.prev_win) then
    vim.api.nvim_set_current_win(st.prev_win)
  end
  if st.alt_buf and st.alt_buf ~= -1 and vim.api.nvim_buf_is_valid(st.alt_buf) then
    vim.fn.setreg("#", tostring(st.alt_buf))
  end
  st.winid = nil
  st.bufnr = nil
  st.main_file = nil
  st.view_level = nil
  st.prev_win = nil
  st.display_map = {}
  st.hl_map = {}
  st.sync_file = nil
  st.sync_lnum = 0
  st.alt_buf = nil
end

function outline.refresh()
  local st = get_state()
  if not st.main_file or vim.uv.fs_stat(st.main_file) == nil then
    st.main_file = get_main_file()
  end
  render()
end

function outline.sync()
  local st = get_state()
  if not st.winid or not vim.api.nvim_win_is_valid(st.winid) then
    return
  end
  if not st.bufnr or not vim.api.nvim_buf_is_valid(st.bufnr) then
    return
  end

  local src_win = vim.api.nvim_get_current_win()
  if src_win == st.winid then
    src_win = nil
  else
    local buf = vim.api.nvim_win_get_buf(src_win)
    local bt = vim.api.nvim_get_option_value("buftype", { buf = buf })
    if bt ~= "" then
      src_win = nil
    end
  end
  if not src_win then
    src_win = find_target_window()
  end
  if not src_win then
    return
  end

  local src_buf = vim.api.nvim_win_get_buf(src_win)
  local cur_file = vim.api.nvim_buf_get_name(src_buf)
  if cur_file == "" then
    return
  end
  cur_file = vim.fn.resolve(cur_file)

  local cur_lnum = vim.api.nvim_win_get_cursor(src_win)[1]
  if cur_file == st.sync_file and cur_lnum == st.sync_lnum then
    return
  end

  local best_idx = nil
  local best_lnum = 0

  for i, h in ipairs(st.display_map) do
    if h.level > 0 and h.file == cur_file and h.lnum <= cur_lnum and h.lnum > best_lnum then
      best_idx = i
      best_lnum = h.lnum
    end
  end

  if best_idx then
    vim.api.nvim_win_set_cursor(st.winid, { best_idx, 0 })
    vim.api.nvim_win_call(st.winid, function()
      vim.cmd("normal! zz")
    end)
  end
  st.sync_file = cur_file
  st.sync_lnum = cur_lnum
end

return outline
