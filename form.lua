local M = {}

local type_transformers = {
  ["nil"] = function(x) return "nil" end,
  boolean = tostring,
  number = tostring,
  string = function(x) return string.format("%q", x) end,
  table = function(x) return x:to_lua() end
}

local function to_lua(x)
  local type_transformer = type_transformers[type(x)]
  if not type_transformer then
    error("cannot transform: " .. tostring(x))
  end
  return type_transformer(x)
end
M.to_lua = to_lua

local function form(type, init, to_lua)
  local mt = {__index = {type = type, to_lua = to_lua}}
  return function(...)
    return setmetatable(init(...), mt)
  end
end

M.symbol = form(
  "symbol",
  function(name)
    return {name = name}
  end,
  function(self)
    return self.name
end)

local function cons_to_explist(cons)
  local codes = {}
  local function collect(cons)
    if cons == nil then
      return
    end
    table.insert(codes, to_lua(cons.car))
    collect(cons.cdr)
  end
  collect(cons)
  return table.concat(codes, ", ")
end

M.cons = form(
  "cons",
  function(car, cdr)
    return {car = car, cdr = cdr or empty_list}
  end,
  function(self)
    return "(" .. to_lua(self.car) .. "(" .. cons_to_explist(self.cdr) .. "))"
end)

return M
