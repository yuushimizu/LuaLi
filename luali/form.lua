local PARENT = string.match((...) or "", "(.-)%.[^.]+$") or ""
local util = require(PARENT .. ".util")

local M = {}

local env_mt = {
  __index = {
    find_value = function(self, name)
      local local_var = self.locals[name]
      if local_var then
        return local_var[1]
      end
      return self.global[name]
    end,
    set_local = function(self, name, value)
      self.locals[name] = {value}
    end
  }
}

function M.env(parent)
  return setmetatable(
    parent and
      {
        global = parent.global,
        locals = {__index = parent.locals}
      } or
      {
        global = setmetatable({}, {__index = _G}),
        locals = {}
      }, env_mt)
end

local lisp_form_mark = {}

local function is_lisp_form(form)
  local mt = getmetatable(form)
  return mt and mt.lisp_form_mark == lisp_form_mark
end

local function table_to_lua(t)
  local code_pairs = {}
  for i, v in pairs(t) do
    table.insert(code_pairs, "[" .. M.to_lua(i) .. "] = " .. M.to_lua(v))
  end
  return "{" .. table.concat(code_pairs, ", ") .. "}"
end

local type_forms = {
  ["nil"] = {
    to_lua = function(form) return "nil" end,
    eval = util.identity
  },
  boolean = {
    to_lua = tostring,
    eval = util.identity
  },
  number = {
    to_lua = tostring,
    eval = util.identity
  },
  string = {
    to_lua = function(form) return string.format("%q", form) end,
    eval = util.identity
  },
  table = {
    to_lua = function(form)
      if is_lisp_form(form) then
        return form:to_lua()
      end
      return table_to_lua(form)
    end,
    eval = function(form, env)
      if is_lisp_form(form) then
        return form:eval(env)
      end
      return form
    end
  }
}

function M.to_lua(form)
  local type_form = type_forms[type(form)]
  if not type_form then
    error("cannot transform: " .. tostring(form))
  end
  return type_form.to_lua(form)
end

function M.eval(form, env)
  local type_form = type_forms[type(form)]
  if not type_form then
    error("cannot eval: " .. tostring(form))
  end
  return type_form.eval(form, env)
end

local function form(init, to_lua, eval)
  local mt = {
    lisp_form_mark = lisp_form_mark,
    __index = {
      to_lua = to_lua,
      eval = eval
    }
  }
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
  end,
  function(self, env)
    return env:find_value(self.name)
end)

local function car(cons)
  return cons and cons.car
end

local function cdr(cons)
  return cons and cons.cdr
end

local function cadr(cons)
  return car(cdr(cons))
end

local function caddr(cons)
  return car(cdr(cdr(cons)))
end

local function each_cons(cons)
  return function(cons, current)
    if not current then
      return cons
    end
    return cdr(current)
  end, cons
end

local function cons_to_explist(cons, delimiter, return_last)
  local codes = {}
  for cons in each_cons(cons) do
    local code = M.to_lua(car(cons))
    if not cdr(cons) and return_last then
      code = "return " .. code
    end
    table.insert(codes, code)
  end
  return table.concat(codes, delimiter)
end

local special_forms = {}

local function symbol_special_form(symbol)
  return M.is_symbol(symbol) and special_forms[symbol.name]
end

local function eval_cons_as_list(cons, env)
  local index = 1
  local result = {}
  for cons in each_cons(cons) do
    result[index] = M.eval(car(cons), env)
    index = index + 1
  end
  return result
end

M.cons, M.is_cons = form(
  function(car, cdr)
    return {car = car, cdr = cdr}
  end,
  function(self)
    local special_form = symbol_special_form(car(self))
    if special_form then
      return special_form.to_lua(cdr(self))
    end
    return M.to_lua(car(self)) .. "(" .. cons_to_explist(cdr(self), ", ") .. ")"
  end,
  function(self, env)
    local special_form = symbol_special_form(car(self))
    if special_form then
      return special_form.eval(cdr(self), env)
    end
    local args = eval_cons_as_list(cdr(self), env)
    return M.eval(car(self), env)(unpack(args))
end)

local function add_special_form(name, to_lua, eval)
  special_forms[name] = {to_lua = to_lua, eval = eval}
end

add_special_form(
  ".",
  function(args)
    return M.to_lua(cadr(args)) .. "[" .. M.to_lua(car(args)) .. "]"
  end,
  function(args, env)
    return M.eval(cadr(args), env)[M.eval(car(args), env)]
end)

add_special_form(
  "return",
  function(args)
    error("can not use return")
  end,
  function(args, env)
    error("can not use return")
end)

add_special_form(
  "local",
  function(args)
    return "local " .. M.to_lua(car(args)) .. " = " .. M.to_lua(cadr(args))
  end,
  function(args, env)
    env:set_local(car(args).name, M.eval(cadr(args), env))
end)

add_special_form(
  "+",
  function(args)
    return "(" .. cons_to_explist(args, " + ") .. ")"
  end,
  function(args, env)
    return M.eval(car(args), env) + M.eval(cadr(args), env)
end)

add_special_form(
  "==",
  function(args)
    return "(" .. cons_to_explist(args, " == ") .. ")"
  end,
  function(args, env)
    return M.eval(car(args), env) == M.eval(cadr(args), env)
end)

add_special_form(
  "if",
  function(args)
    return "(function() if " .. M.to_lua(car(args)) .. " then return " .. M.to_lua(cadr(args)) .. " else return " .. M.to_lua(caddr(args)) .. " end end)()"
  end,
  function(args, env)
    if M.eval(car(args), env) then
      return M.eval(cadr(args), env)
    else
      return M.eval(caddr(args), env)
    end
end)

add_special_form(
  "fn",
  function(args)
    return "(function(" .. cons_to_explist(car(args), ", ") .. ") " .. cons_to_explist(cdr(args), "\n", true) .. " end)"
  end,
  function(args, env)
    local arg_names = {}
    for cons in each_cons(car(args)) do
      table.insert(arg_names, car(cons).name)
    end
    return function(...)
      local fn_env = M.env(env)
      local fn_args = {...}
      for i, name in ipairs(arg_names) do
        fn_env:set_local(name, fn_args[i])
      end
      local result = nil
      for cons in each_cons(cdr(args)) do
        result = M.eval(car(cons), fn_env)
      end
      return result
    end
end)

return M
