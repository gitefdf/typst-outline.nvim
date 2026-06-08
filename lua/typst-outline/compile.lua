local compile = {}

local typst_job = nil
local zathura_job = nil
local last_errors = {}

local function find_pdf(main_file)
  return main_file:gsub("%.typ$", "") .. ".pdf"
end

local function get_main()
  return require("typst-outline.parser").find_main(vim.fn.expand("%:p"))
end

function compile.start()
  if compile.is_running() then
    vim.notify("[TypstCompile] Already running", vim.log.levels.WARN)
    return
  end
  local main = get_main()
  if not main then
    vim.notify("[TypstCompile] No main file found", vim.log.levels.WARN)
    return
  end
  local pdf = find_pdf(main)

  local error_timer = nil
  last_errors = {}
  typst_job = vim.fn.jobstart({ "typst", "watch", main }, {
    on_stderr = function(_, data)
      if not data then
        return
      end
      local text = table.concat(data, "\n")
      local lines = vim.split(text, "\n")
      local has_error = false
      if not error_timer then
        last_errors = {}
      end
      for _, line in ipairs(lines) do
        if line ~= "" then
          table.insert(last_errors, line)
        end
        if not has_error and line:lower():find("error") then
          has_error = true
        end
      end
      if has_error then
        if not error_timer then
          error_timer = vim.uv.new_timer()
        end
        error_timer:stop()
        error_timer:start(300, 0, vim.schedule_wrap(function()
          vim.notify("[typst] compiled with errors", vim.log.levels.WARN)
        end))
      end
    end,
  })

  vim.defer_fn(function()
    zathura_job = vim.fn.jobstart({ "zathura", pdf })
    vim.notify("[TypstCompile] Started: " .. vim.fn.fnamemodify(main, ":t"))
  end, 1000)
end

function compile.stop()
  local function stop(job)
    if job then
      pcall(vim.fn.jobstop, job)
    end
  end
  stop(typst_job)
  stop(zathura_job)
  typst_job = nil
  zathura_job = nil
  vim.notify("[TypstCompile] Stopped")
end

function compile.is_running()
  if not typst_job then
    return false
  end
  local ok = pcall(vim.fn.jobpid, typst_job)
  return ok and vim.fn.jobpid(typst_job) > 0
end

function compile.toggle()
  if compile.is_running() then
    compile.stop()
  else
    compile.start()
  end
end

function compile.errors()
  if #last_errors == 0 then
    vim.notify("[TypstCompile] No errors", vim.log.levels.INFO)
    return
  end
  vim.cmd("botright split")
  local buf = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, last_errors)
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
  vim.api.nvim_win_set_buf(0, buf)
  vim.api.nvim_set_option_value("wrap", false, { win = 0 })
  vim.api.nvim_set_option_value("list", false, { win = 0 })
  local opts = { buffer = buf, nowait = true, silent = true }
  vim.keymap.set("n", "q", function() vim.api.nvim_buf_delete(buf, { force = true }) end, opts)
  vim.keymap.set("n", "<Esc>", function() vim.api.nvim_buf_delete(buf, { force = true }) end, opts)
end

return compile
