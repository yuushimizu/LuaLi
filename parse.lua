local form = require("form")

local M = {}

local special_characters = {}

local function special_character_class()
  local classes = {}
  for character in pairs(special_characters) do
    table.insert(classes, (character:gsub("%W", "%%%0")))
  end
  return table.concat(classes)
end

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
  local number = tonumber(token)
  if number ~= nil then
    return number
  end
  return form.symbol(token)
end

function session:next_token_start()
  return self:next_match("%S", true)
end

function session:parse_next(additional_special_characters)
  local token_start = self:next_token_start()
  if not token_start then
    return
  end
  local special_parser = (additional_special_characters and additional_special_characters[token_start]) or special_characters[token_start]
  if special_parser then
    self:spend(1)
    return special_parser(self)
  end
  return self:parse_symbol()
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
  local next = self:parse_next()
  if not next then
    error("unexpected eof")
  end
  return form.list(form.symbol("quote"), next)
end

local function define_delimiter(open, close, f)
  special_characters[close] = function()
    error("unexpected " .. close)
  end
  local close_mark = {}
  special_characters[open] = function(self)
    local values = {}
    while true do
      local next = self:parse_next({
          [close] = function(self) return close_mark end
      })
      if not next then
        error("unexpected eof")
      elseif next == close_mark then
        return f(values)
      end
      table.insert(values, next)
    end
  end
end

define_delimiter(
  "(", ")",
  function(values)
    return form.list(unpack(values))
end)

define_delimiter(
  "{", "}",
  function(values)
    local count = #values
    if count % 2 == 1 then
      error("{} contains odd number of forms")
    end
    local result = {}
    for i = 1, count, 2 do
      result[values[i]] = values[i + 1]
    end
    return result
end)

define_delimiter(
  "[", "]",
  function(values)
    return values
end)

function session:parse_toplevel()
  local next = self:parse_next()
  if next then
    self:emit(next)
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


