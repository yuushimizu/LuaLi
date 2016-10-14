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

function session:read()
  while not self.eof and self.reading_string:len() == 0 do
    coroutine.yield(function()
        local s = self.reader()
        if s then
          self.reading_string = s
        else
          self.eof = true
        end
    end)
  end
  return self.reading_string
end

function session:spend(length)
  self.reading_string = self.reading_string:sub(length + 1)
end

function session:pushBack(s)
  self.reading_string = s .. self.reading_string
end

function session:emit(form)
  coroutine.yield(function() self.callback(form) end)
end

function session:next_match(pattern)
  local joined = ""
  while true do
    local s = self:read()
    joined = joined .. s
    local match_start, match_end = joined:find(pattern)
    if match_start and (self.eof or match_end < joined:len()) then
      self:spend(match_end - (joined:len() - s:len()))
      return joined:match(pattern)
    end
    if self.eof then
      break
    end
    self:spend(s:len())
  end
  return nil, joined
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
  return self:next_match("%S")
end

function session:parse_next()
  local token_start = self:next_token_start()
  if not token_start then
    return
  end
  local special_parser = special_characters[token_start]
  if special_parser then
    return special_parser(self), true
  end
  self:pushBack(token_start)
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
      break
    end
    self:pushBack(token_start)
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
      reading_string = "",
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


