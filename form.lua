function asString(value, tableIndent)
  tableIndent = tableIndent or ""
  local valueType = type(value)
  if valueType == "table" then
    if getmetatable(value) and getmetatable(value).__tostring then
      return tostring(value)
    end
    local result = "{\n"
    local nextTableIndent = tableIndent .. "  "
    for k, v in pairs(value) do
      result = result .. nextTableIndent .. "[" .. asString(k, nextTableIndent) .. "] = " .. asString(v, nextTableIndent) .. ",\n"
    end
    result = result .. tableIndent .. "}"
    return result
  elseif valueType == "string" then
    return '"' .. value .. '"'
  end
  return tostring(value)
end

function dump(value)
  print(asString(value))
end


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

local function each_cons(cons)
  return function(cons, current)
    if not current then
      return cons
    end
    return current.cdr
  end, cons
end

local function cons_to_explist(cons, delimiter)
  local codes = {}
  for cons in each_cons(cons) do
    table.insert(codes, M.to_lua(cons.car))
  end
  return table.concat(codes, delimiter)
end

local function add_return_to_last(cons)
  local result = M.cons()
  local current = result
  for cons in each_cons(cons) do
    if cons.cdr or cons.car.car.name == "return" then
      current.cdr = M.cons(cons.car)
    else
      current.cdr = M.cons(M.cons(M.symbol("return"), M.cons(cons.car)))
    end
    current = current.cdr
  end
  return result.cdr or M.cons(M.cons(M.symbol("return")))
end

local special_forms = {}

special_forms["return"] = function(cdr)
  return "return " .. cons_to_explist(cdr, ", ")
end

special_forms["+"] = function(cdr)
  return "(" .. cons_to_explist(cdr, " + ") .. ")"
end

special_forms["fn"] = function(cdr)
  return "(function(" .. cons_to_explist(cdr.car, ", ") .. ") " .. cons_to_explist(add_return_to_last(cdr.cdr), "\n") .. " end)"
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

return M
