local form = require("form")

local M = {}

local special_characters = {
  ['"'] = 1,
  ["'"] = 1,
  ["("] = 1,
  [")"] = 1,
  ["{"] = 1,
  ["}"] = 1,
  ["["] = 1,
  ["]"] = 1
}

local function special_character_class()
  local classes = {}
  for character in pairs(special_characters) do
    table.insert(classes, (character:gsub("%W", "%%%0")))
  end
  return table.concat(classes)
end

local special_symbols = {
  ["nil"] = function() return nil end,
  ["true"] = function() return true end,
  ["false"] = function() return false end
}

local session = {}

function session:read()
  if self.reading_string and self.position > self.reading_string:len() then
    coroutine.yield(function() self.reading_string = self.reader() end)
    self.position = 1
  end
  return self.reading_string, self.position
end

function session:seek(position)
  self.position = position
end

function session:emit(form)
  coroutine.yield(function() self.callback(form) end)
end

function session:match(pattern)
  local joined = nil
  local start = 1
  while true do
    local s, pos = self:read()
    if not s then
      break
    end
    if not joined then
      joined = s
      start = pos
    else
      joined = joined .. (pos > 1 and s:sub(pos) or pos)
    end
    local match_start, match_end = joined:find(pattern, start)
    if match_start then
      self:seek(match_end - (joined:len() - s:len()))
      return joined:sub(match_start, match_end), joined:sub(start, match_start - 1)
    end
    self:seek(s:len() + 1)
  end
  return nil, joined and joined:sub(start) or ""
end

function session:parse_symbol()
  local _, token = self:match("[%s" .. special_character_class() .. "]")
  local value = tonumber(token)
  if value ~= nil then
    return value
  end
  local special_symbol = special_symbols[token]
  if special_symbol then
    return special_symbol()
  end
  return form.symbol(token)
end

function session:parse_next()
  local token_start = self:match("%S")
  if token_start then
    return (special_characters[token_start] or self.parse_symbol)(self), true
  end
end

function session:parse_toplevel()
  local form, parsed = self:parse_next()
  if parsed then
    self:emit(form)
    self:parse_toplevel()
  end
end

local session_mt = {__index = session}

M.parse = function(reader, callback)
  local session = setmetatable(
    {
      reader = reader,
      callback = callback,
      reading_string = reader(),
      position = 1
    }, session_mt)
  local coro = coroutine.wrap(function()
      session:parse_toplevel()
  end)
  while true do
    local result = coro()
    if not result then
      break
    end
    result()
  end
end

return M
