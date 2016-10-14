local form = require("form")

local M = {}

local special_characters = {
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
  while self.reading_string and self.reading_string:len() == 0 do
    coroutine.yield(function() self.reading_string = self.reader() end)
  end
  return self.reading_string
end

function session:spend(length)
  if self.reading_string then
    self.reading_string = self.reading_string:sub(length + 1)
  end
end

function session:emit(form)
  coroutine.yield(function() self.callback(form) end)
end

function session:next_match(pattern)
  local joined = ""
  while true do
    local s = self:read()
    if s then
      joined = joined .. s
    end
    local match_start, match_end = joined:find(pattern)
    if match_start and (not s or match_end < joined:len()) then
      if s then
        self:spend(match_end - (joined:len() - s:len()) - 1)
      end
      return joined:match(pattern)
    end
    if not s then
      break
    end
    self:spend(s:len())
  end
  return nil, joined
end

function session:parse_symbol()
  local token = self:next_match("[^%s" .. special_character_class() .. "]+")
  self:spend(1)
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
  local token_start = self:next_match("%S")
  if token_start then
    return (special_characters[token_start] or self.parse_symbol)(self), true
  end
end

special_characters['"'] = function(self)
  local result = ""
  while true do
    local match = self:next_match('"([^"]*)"')
    local len = match:len()
    result = result .. match
    if match:sub(match:len()) ~= "\\" then
      break
    end
    result = result .. '"'
  end
  return result
end

special_characters["'"] = function(self)
  self:spend(1)
  local next_form, parsed = self:parse_next()
  if not parsed then
    error("unexpected eof")
  end
  return form.list(form.symbol("quote"), next_form)
end

function session:parse_toplevel()
  local form, parsed = self:parse_next()
  if parsed then
    self:emit(form)
    return self:parse_toplevel()
  end
end

local session_mt = {__index = session}

M.parse = function(reader, callback)
  local session = setmetatable(
    {
      reader = reader,
      callback = callback,
      reading_string = reader()
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


