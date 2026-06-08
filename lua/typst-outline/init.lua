local M = {}

local defaults = {
  auto_refresh = true,
  focus_on_open = true,
  split_direction = "left",
  split_width = 35,
  max_depth = 10,
  max_level = nil,
  sync_cursor = true,
  sync_debounce = 50,
  highlights = {
    H1 = { fg = "#cba6f7", bold = true },
    H2 = { fg = "#94e2d5" },
    H3 = { fg = "#f9e2af" },
    H4 = { fg = "#fab387" },
    H5 = { fg = "#f5c2e7" },
    H6 = { fg = "#b4befe" },
    H7 = { fg = "#89dceb" },
    H8 = { fg = "#a6e3a1" },
    H9 = { fg = "#f2cdcd" },
    File = { fg = "#9399b2", bold = true },
  },
}

M.config = vim.deepcopy(defaults)

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  if opts and opts.highlights then
    M.config.highlights = vim.tbl_deep_extend("keep", defaults.highlights, opts.highlights)
  end

  require("typst-outline.parser").load_cache()

  vim.api.nvim_create_user_command("TypstOutline", function()
    require("typst-outline.outline").toggle()
  end, {})

  vim.api.nvim_create_user_command("TypstOutlineRefresh", function()
    require("typst-outline.outline").refresh()
  end, {})

  vim.api.nvim_create_user_command("TypstOutlineClose", function()
    require("typst-outline.outline").close()
  end, {})

  vim.api.nvim_create_user_command("TypstCompile", function()
    require("typst-outline.compile").start()
  end, {})

  vim.api.nvim_create_user_command("TypstCompileStop", function()
    require("typst-outline.compile").stop()
  end, {})

  vim.api.nvim_create_user_command("TypstCompileToggle", function()
    require("typst-outline.compile").toggle()
  end, {})

  vim.api.nvim_create_user_command("TypstCompileErrors", function()
    require("typst-outline.compile").errors()
  end, {})

  local group = vim.api.nvim_create_augroup("TypstOutline", { clear = true })

  if M.config.auto_refresh then
    local refresh_timer = nil
    vim.api.nvim_create_autocmd("BufWritePost", {
      group = group,
      pattern = "*.typ",
      callback = function()
        local outline = require("typst-outline.outline")
        if outline.is_open() then
          if not refresh_timer then
            refresh_timer = vim.uv.new_timer()
          end
          refresh_timer:stop()
          refresh_timer:start(100, 0, vim.schedule_wrap(function()
            outline.refresh()
          end))
        end
      end,
    })
  end

  if M.config.sync_cursor then
    local sync_timer = nil
    vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
      group = group,
      pattern = "*.typ",
      callback = function()
        if not require("typst-outline.outline").is_open() then
          return
        end
        if not sync_timer then
          sync_timer = vim.uv.new_timer()
        end
        sync_timer:stop()
        sync_timer:start(M.config.sync_debounce, 0, vim.schedule_wrap(function()
          require("typst-outline.outline").sync()
        end))
      end,
    })
  end

  vim.api.nvim_create_autocmd("FocusGained", {
    group = group,
    callback = function()
      local outline = require("typst-outline.outline")
      if outline.is_open() then
        outline.refresh()
      end
    end,
  })

  vim.api.nvim_create_autocmd("FileChangedShellPost", {
    group = group,
    pattern = "*.typ",
    callback = function()
      local outline = require("typst-outline.outline")
      if outline.is_open() then
        outline.refresh()
      end
    end,
  })

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      require("typst-outline.parser").save_cache()
      require("typst-outline.compile").stop()
    end,
  })
end

return M
