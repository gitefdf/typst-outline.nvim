local parser = {}

local CACHE_VERSION = "v1"

local parse_cache = {}
local main_cache = {}

local function get_mtime(path)
  local stat = vim.uv.fs_stat(path)
  return stat and stat.mtime.sec
end

function parser.invalidate()
  parse_cache = {}
  main_cache = {}
end

local function is_comment(line)
  return line:match("^%s*//") ~= nil
end

local function extract_include(line)
  for _, pattern in ipairs({ '#include%s*"([^"]+)"', '#include%s*%("([^"]+)"%)' }) do
    local path = line:match(pattern)
    if path then
      return path
    end
  end
  local path = line:match('#import%s*"([^"]+)"')
  if not path then
    path = line:match('#import%s*%("([^"]+)"%)')
  end
  if path and not path:match("^@") then
    return path
  end
  return nil
end

local function resolve_include(base, rel)
  local dir = vim.fn.fnamemodify(base, ":h")
  if dir == "" then
    dir = "."
  end
  return vim.fs.normalize(dir .. "/" .. rel)
end

local function file_readable(path)
  local stat = vim.uv.fs_stat(path)
  return stat and stat.type == "file"
end

local cache_dir = vim.fn.stdpath("cache") .. "/typst-outline"
local cache_file = cache_dir .. "/cache.json"

function parser.load_cache()
  local f = io.open(cache_file, "r")
  if not f then
    return
  end
  local ok, data = pcall(vim.json.decode, f:read("*a"))
  f:close()
  if not ok or type(data) ~= "table" or data.version ~= CACHE_VERSION then
    return
  end
  if data.parse then
    for abs, entry in pairs(data.parse) do
      if entry and entry.mtime and get_mtime(abs) == entry.mtime then
        parse_cache[abs] = entry
      end
    end
  end
end

function parser.save_cache()
  vim.fn.mkdir(cache_dir, "p")
  local f = io.open(cache_file, "w")
  if not f then
    return
  end
  f:write(vim.json.encode({ version = CACHE_VERSION, parse = parse_cache }))
  f:close()
end

local function try_resolve(base, rel)
  local path = resolve_include(base, rel)
  if file_readable(path) then
    return path
  end
  path = resolve_include(base, rel .. ".typ")
  if file_readable(path) then
    return path
  end
  return nil
end

local function match_eq_heading(line)
  local level_str, text = line:match("^(=+)%s+(.*)")
  if not level_str then
    level_str = line:match("^(=+)$")
    text = ""
  end
  if not level_str then
    return nil
  end
  text = text:gsub("%s*<[^>]+>%s*$", "")
  text = text:gsub("%s*//.*$", "")
  text = vim.trim(text)
  return math.min(#level_str, 9), text
end

local function match_func_heading(line)
  local text = line:match("#heading%(.-%)%[([^%]]+)%]$")
  if not text then
    text = line:match("#heading%s*%[([^%]]+)%]$")
  end
  if text then
    local level_str = line:match("level:%s*(%d+)")
    local level = math.min(tonumber(level_str) or 1, 9)
    text = text:gsub("%s*<[^>]+>%s*$", "")
    return level, vim.trim(text)
  end
  return nil
end

function parser.parse(filepath, opts)
  opts = opts or {}
  local max_depth = opts.max_depth or 10
  local depth = opts.depth or 0
  local visited = opts.visited or {}

  if depth > max_depth then
    return {}
  end
  local abs = vim.fn.resolve(filepath)
  if visited[abs] then
    return {}
  end
  visited[abs] = true

  if not file_readable(abs) then
    parse_cache[abs] = nil
    return {}
  end

  local mtime = get_mtime(abs)
  local items

  if parse_cache[abs] and parse_cache[abs].mtime == mtime then
    items = parse_cache[abs].items
  else
    local lines = vim.fn.readfile(abs)
    items = {}
    local in_block = false

    for lnum, line in ipairs(lines) do
      if in_block then
        local endpos = line:find("%*/")
        if not endpos then
          goto continue
        end
        line = line:sub(endpos + 2)
        in_block = false
      end
      line = line:gsub("/%*.-%*/", "")
      local startpos = line:find("/%*")
      if startpos then
        in_block = true
        line = line:sub(1, startpos - 1)
      end
      if line:match("^%s*$") then
        goto continue
      end

      if is_comment(line) then
        goto continue
      end

      if not line:find("[=#]") then
        goto continue
      end

      local has_hash = line:find("#", 1, true)
      if has_hash then
        local included = extract_include(line)
        if included then
          local target = try_resolve(abs, included)
          if target then
            items[#items + 1] = { type = "include", path = target }
            goto continue
          end
        end
      end

      local level, text
      if has_hash then
        level, text = match_func_heading(line)
      end
      if not level then
        level, text = match_eq_heading(line)
      end
      if level then
        items[#items + 1] = {
          type = "heading",
          level = level,
          text = text,
          lnum = lnum,
          file = abs,
        }
      end

      ::continue::
    end

    parse_cache[abs] = { mtime = mtime, items = items }
  end

  local headings = {}
  for _, item in ipairs(items) do
    if item.type == "heading" then
      headings[#headings + 1] = {
        level = item.level,
        text = item.text,
        lnum = item.lnum,
        file = item.file,
      }
    elseif item.type == "include" then
      local sub = parser.parse(item.path, {
        max_depth = max_depth,
        depth = depth + 1,
        visited = visited,
      })
      if #sub == 0 then
        headings[#headings + 1] = {
          level = 0,
          text = "",
          lnum = 1,
          file = item.path,
        }
      else
        for _, h in ipairs(sub) do
          headings[#headings + 1] = h
        end
      end
    end
  end

  return headings
end

local function is_included_by(candidate, target)
  if not file_readable(candidate) or candidate == target then
    return false
  end
  local abs_candidate = vim.fn.resolve(candidate)
  local resolved_target = vim.fn.resolve(target)

  if parse_cache[abs_candidate] then
    for _, item in ipairs(parse_cache[abs_candidate].items) do
      if item.type == "include" and vim.fn.resolve(item.path) == resolved_target then
        return true
      end
    end
    return false
  end

  local lines = vim.fn.readfile(candidate)
  for _, line in ipairs(lines) do
    if is_comment(line) then
      goto continue
    end
    local inc = extract_include(line)
    if inc then
      local abs = try_resolve(candidate, inc)
      if abs and vim.fn.resolve(abs) == resolved_target then
        return true
      end
    end
    ::continue::
  end
  return false
end

local function is_root_hinted(filepath)
  local lines = vim.fn.readfile(filepath, "", 5)
  for _, line in ipairs(lines) do
    if line:match("//%s*typst%-root:%s*true") then
      return true
    end
  end
  return false
end

local function search_upward_from_dir(start_dir, target, visited_dirs)
  visited_dirs = visited_dirs or {}
  local dir = vim.fn.resolve(start_dir)
  local prev = nil

  while dir ~= prev do
    if not visited_dirs[dir] then
      visited_dirs[dir] = true
      local ok, fd = pcall(vim.uv.fs_scandir, dir)
      if ok and fd then
        while true do
          local name, ftype = vim.uv.fs_scandir_next(fd)
          if not name then
            break
          end
          if ftype == "file" and name:match("%.typ$") then
            local f = vim.fs.normalize(dir .. "/" .. name)
            if is_included_by(f, target) then
              return f
            end
          end
        end
      end
    end
    prev = dir
    dir = vim.fn.fnamemodify(dir, ":h")
  end

  return nil
end

function parser.find_main(current_file)
  current_file = vim.fn.expand(current_file)
  local key = vim.fn.resolve(current_file)
  if main_cache[key] and file_readable(main_cache[key]) then
    return main_cache[key]
  end
  if is_root_hinted(key) then
    main_cache[key] = key
    return key
  end
  local target = key
  local visited_dirs = {}

  while true do
    local start_dir = vim.fn.fnamemodify(target, ":h")
    local found = search_upward_from_dir(start_dir, target, visited_dirs)
    if not found then
      local cwd = vim.fn.getcwd()
      found = search_upward_from_dir(cwd, target, visited_dirs)
    end
    if not found then
      break
    end
    target = vim.fn.resolve(found)
    if is_root_hinted(target) then
      break
    end
  end

  main_cache[key] = target
  return target
end

return parser
