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

local function form(init, to_lua)
  local mt = {__index = {to_lua = to_lua}}
  local new = function(...)
    return setmetatable(init(...), mt)
  end
  local is = function(form)
    return type(form) == "table" and getmetatable(form) == mt
  end
  return new, is
end

M.symbol, M.is_symbol = form(
  function(name)
    return {name = name}
  end,
  function(self)
    return self.name
end)

local function car(cons)
  return cons and cons.car
end

local function cdr(cons)
  return cons and cons.cdr
end

local function each_cons(cons)
  return function(cons, current)
    if not current then
      return cons
    end
    return cdr(current)
  end, cons
end

local function cons_to_explist(cons, delimiter)
  local codes = {}
  for cons in each_cons(cons) do
    table.insert(codes, M.to_lua(car(cons)))
  end
  return table.concat(codes, delimiter)
end

local special_forms = {}

M.cons, M.is_cons = form(
  function(car, cdr)
    return {car = car, cdr = cdr}
  end,
  function(self)
    local special_form = M.is_symbol(car(self)) and special_forms[car(self).name]
    if special_form then
      return special_form(cdr(self))
    end
    return M.to_lua(car(self)) .. "(" .. cons_to_explist(cdr(self), ", ") .. ")"
end)

function M.add_return(form)
  if M.is_cons(form) and M.is_symbol(car(form)) and car(form).name == "return" then
    return form
  end
  return M.cons(M.symbol("return"), M.cons(form))
end

local function add_return_to_last(cons)
  local result = M.cons()
  local current = result
  for cons in each_cons(cons) do
    current.cdr = cdr(cons) and M.cons(car(cons)) or M.cons(M.add_return(car(cons)))
    current = cdr(current)
  end
  return cdr(result) or M.cons(M.cons(M.symbol("return")))
end

special_forms["return"] = function(args)
  return "return " .. cons_to_explist(args, ", ")
end

special_forms["local"] = function(args)
  return "local " .. M.to_lua(car(args)) .. " = " .. M.to_lua(car(cdr(args)))
end

special_forms["+"] = function(args)
  return "(" .. cons_to_explist(args, " + ") .. ")"
end

special_forms["=="] = function(args)
  return "(" .. cons_to_explist(args, " == ") .. ")"
end

special_forms["if"] = function(args)
  return "(function() if " .. M.to_lua(car(args)) .. " then " .. M.to_lua(M.add_return(car(cdr(args)))) .. " else " .. M.to_lua(M.add_return(car(cdr(cdr(args))))) .. " end end)()"
end

special_forms["fn"] = function(args)
  return "(function(" .. cons_to_explist(car(args), ", ") .. ") " .. cons_to_explist(add_return_to_last(cdr(args)), "\n") .. " end)"
end

return M
