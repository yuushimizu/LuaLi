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

function session:push_back(s)
  self.buffer = s .. self.buffer
end

function session:emit(form)
  coroutine.yield(function() self.callback(form) end)
end

function session:next_match(pattern)
  while true do
    local s = self.buffer
    local match_start, match_end = s:find(pattern)
    if match_start and (self.eof or match_end < s:len()) then
      self:spend(match_end)
      return s:match(pattern)
    end
    if self.eof then
      return
    end
    self:read_more()
  end
end

local special_symbols = {
  ["nil"] = function() return nil end,
  ["true"] = function() return true end,
  ["false"] = function() return false end
}

function session:parse_symbol()
  local token = self:next_match("[^%s" .. special_character_class() .. "]+")
  local special_symbol = special_symbols[token]
  if special_symbol then
    return special_symbol()
  end
  local number = tonumber(token)
  if number ~= nil then
    return number
  end
  return form.symbol(token)
end

function session:parse_next(additional_special_characters)
  local token_start = self:next_match("%S")
  if not token_start then
    return
  end
  local special_parser = (additional_special_characters and additional_special_characters[token_start]) or special_characters[token_start]
  if special_parser then
    return special_parser(self), true
  end
  self:push_back(token_start)
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
  local next, parsed = self:parse_next()
  if not parsed then
    error("unexpected eof")
  end
  return form.cons(form.symbol("quote"), form.cons(next))
end

local function define_delimiter(open, close, f)
  special_characters[close] = function()
    error("unexpected " .. close)
  end
  local close_mark = {}
  special_characters[open] = function(self)
    local each, complete = f(self)
    while true do
      local next, parsed = self:parse_next({
          [close] = function(self) return close_mark end
      })
      if not parsed then
        error("unexpected eof")
      elseif next == close_mark then
        return complete()
      end
      each(next)
    end
  end
end

define_delimiter(
  "(", ")",
  function()
    local head = form.cons()
    local current_cons = head
    return function(next)
      current_cons.cdr = form.cons(next)
      current_cons = current_cons.cdr
    end, function() return head.cdr end
end)

define_delimiter(
  "{", "}",
  function(self, values)
    local result = {}
    return function(next)
      local value, parsed = self:parse_next()
      if not parsed then
        error("{} contains odd number of forms")
      end
      result[value] = parsed
    end, function() return result end
end)

define_delimiter(
  "[", "]",
  function()
    local result = {}
    return function(next)
      table.insert(result, next)
    end, function() return result end
end)

function session:parse_toplevel()
  local next, parsed = self:parse_next()
  if parsed then
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


