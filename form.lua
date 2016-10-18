local M = {}

local function table_to_lua(t)
  local code_pairs = {}
  for i, v in pairs(t) do
    table.insert(code_pairs, "[" .. M.to_lua(i) .. "] = " .. M.to_lua(v))
  end
  return "{" .. table.concat(code_pairs, ", ") .. "}"
end

local type_transformers = {
  ["nil"] = function(x) return "nil" end,
  boolean = tostring,
  number = tostring,
  string = function(x) return string.format("%q", x) end,
  table = function(x)
    if x.to_lua then
      return x:to_lua()
    end
    return table_to_lua(x)
  end
}

function M.to_lua(x)
  local type_transformer = type_transformers[type(x)]
  if not type_transformer then
    error("cannot transform: " .. tostring(x))
  end
  return type_transformer(x)
end

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

local function cons_to_explist(cons, delimiter)
  local codes = {}
  local function collect(cons)
    if cons == nil then
      return
    end
    table.insert(codes, M.to_lua(cons.car))
    collect(cons.cdr)
  end
  collect(cons)
  return table.concat(codes, delimiter)
end

local special_forms = {}

special_forms["+"] = function(cdr)
  return "(" .. cons_to_explist(cdr, " + ") .. ")"
end

special_forms["fn"] = function(cdr)
  return "(function(" .. cons_to_explist(cdr.car, ", ") .. ") " .. cons_to_explist(cdr.cdr, "\n") .. " end)"
end

M.cons = form(
  "cons",
  function(car, cdr)
    return {car = car, cdr = cdr}
  end,
  function(self)
    local special_form = type(self.car) == "table" and self.car.type == "symbol" and special_forms[self.car.name]
    if special_form then
      return special_form(self.cdr)
    end
    return M.to_lua(self.car) .. "(" .. cons_to_explist(self.cdr, ", ") .. ")"
end)

M.list = function(...)
  local args = {...}
  local result = nil
  for i = select("#", ...), 1, -1 do
    result = M.cons(args[i], result)
  end
  return result
end

return M
