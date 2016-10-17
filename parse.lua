local form = require("form")

local M = {}

local special_characters = {
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

function session:read_more()
  if not self.eof then
    local s
    coroutine.yield(function() s = self.reader() end)
    if s then
      self.buffer = self.buffer .. s
    else
      self.eof = true
    end
  end
end

function session:spend(length)
  self.buffer = self.buffer:sub(length + 1)
end

function session:emit(form)
  coroutine.yield(function() self.callback(form) end)
end

function session:next_match(pattern, keep_last)
  while true do
    local s = self.buffer
    local match_start, match_end = s:find(pattern)
    if match_start and (self.eof or match_end < s:len()) then
      self:spend(match_end - (keep_last and 1 or 0))
      return s:match(pattern)
    end
    if self.eof then
      return
    end
    self:read_more()
  end
end

function session:parse_symbol()
  local token = self:next_match("[^%s" .. special_character_class() .. "]+")
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

function session:next_token_start()
  return self:next_match("%S", true)
end

function session:parse_next()
  local token_start = self:next_token_start()
  if not token_start then
    return
  end
  local special_parser = special_characters[token_start]
  if special_parser then
    self:spend(1)
    return special_parser(self), true
  end
  return self:parse_symbol(), true
end

special_characters['"'] = function(self)
  local result = ""
  while true do
    local match = self:next_match('([^"]*)"')
    local len = match:len()
    result = result .. match
    if match:sub(match:len()) ~= "\\" then
      return result
    end
    result = result .. '"'
  end
end

special_characters["'"] = function(self)
  local next_form, parsed = self:parse_next()
  if not parsed then
    error("unexpected eof")
  end
  return form.list(form.symbol("quote"), next_form)
end

special_characters["("] = function(self)
  local elements = {}
  while true do
    local token_start = self:next_token_start()
    if token_start == ")" then
      self:spend(1)
      break
    end
    local next_form, parsed = self:parse_next()
    if not parsed then
      error("unexpected eof")
    end
    table.insert(elements, next_form)
  end
  return form.list(unpack(elements))
end

special_characters[")"] = function()
  error("unexpected )")
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
      buffer = "",
      eof = false
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


