local util = require("luali.util")

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

local lisp_forms = {}

local function lisp_form(form)
  if type(form) ~= "table" then
    return nil
  end
  local mt = getmetatable(form)
  return mt and lisp_forms[mt.lisp_form_type]
end

local function compile_table(t, env)
  local code_pairs = {}
  for i, v in pairs(t) do
    table.insert(code_pairs, "[" .. M.compile(i, env) .. "] = " .. M.compile(v, env))
  end
  return "{" .. table.concat(code_pairs, ", ") .. "}"
end

local function eval_table(t, env)
  local result = {}
  for i, v in pairs(t) do
    result[M.eval(i, env)] = M.eval(v, env)
  end
  return result
end

local type_forms = {
  ["nil"] = {
    compile = function(form, env) return "nil" end
  },
  boolean = {
    compile = tostring,
  },
  number = {
    compile = tostring,
  },
  string = {
    compile = function(form, env) return string.format("%q", form) end,
  },
  table = {
    compile = function(form, env)
      local lf = lisp_form(form)
      if lf then
        return lf.compile(form, env)
      end
      return compile_table(form, env)
    end,
    eval = function(form, env)
      local lf = lisp_form(form)
      if lf then
        return lf.eval(form, env)
      end
      return eval_table(form, env)
    end
  }
}

function M.compile(form, env)
  local type_form = type_forms[type(form)]
  if not type_form then
    error("attempt to transform " .. tostring(form))
  end
  return type_form.compile(form, env)
end

function M.eval(form, env)
  local type_form = type_forms[type(form)]
  if not type_form then
    error("attempt to eval " .. tostring(form))
  end
  if type_form.eval then
    return type_form.eval(form, env)
  end
  return form
end

local function define_form(name, init, methods)
  local mt = {lisp_form_type = name}
  methods.new = function(...)
    return setmetatable(init(...), mt)
  end
  methods.is = function(form)
    return lisp_form(form) == methods
  end
  lisp_forms[name] = methods
  return methods
end

local symbol = define_form(
  "symbol",
  function(name)
    return {name = name}
  end, {
    compile = function(self, env)
      return self.name
    end,
    eval = function(self, env)
      return env:find_value(self.name)
    end
})
M.symbol = symbol.new
M.is_symbol = symbol.is

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

local function cons_to_explist(cons, env, delimiter, return_last)
  local codes = {}
  for cons in each_cons(cons) do
    local code = M.compile(car(cons), env)
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

local cons = define_form(
  "cons",
  function(car, cdr)
    return {car = car, cdr = cdr}
  end, {
    compile = function(self, env)
      local special_form = symbol_special_form(car(self))
      if special_form then
        return special_form.compile(cdr(self), env)
      end
      return M.compile(car(self), env) .. "(" .. cons_to_explist(cdr(self), env, ", ") .. ")"
    end,
    eval = function(self, env)
      local special_form = symbol_special_form(car(self))
      if special_form then
        return special_form.eval(cdr(self), env)
      end
      local args = eval_cons_as_list(cdr(self), env)
      return M.eval(car(self), env)(unpack(args))
    end
})
M.cons = cons.new
M.is_cons = cons.is

local function add_special_form(name, methods)
  special_forms[name] = methods
end

add_special_form(
  ".", {
    compile = function(args, env)
      return M.compile(cadr(args), env) .. "[" .. M.compile(car(args), env) .. "]"
    end,
    eval = function(args, env)
      return M.eval(cadr(args), env)[M.eval(car(args), env)]
    end
})

add_special_form(
  "return", {
    compile = function(args, env)
      error("can not return explicitly")
    end,
    eval = function(args, env)
      error("can not return explicitly")
    end
})

add_special_form(
  "local", {
    compile = function(args, env)
      return "local " .. M.compile(car(args), env) .. " = " .. M.compile(cadr(args), env)
    end,
    eval = function(args, env)
      env:set_local(car(args).name, M.eval(cadr(args), env))
    end
})

add_special_form(
  "+", {
    compile = function(args, env)
      return "(" .. cons_to_explist(args, env, " + ") .. ")"
    end,
    eval = function(args, env)
      return M.eval(car(args), env) + M.eval(cadr(args), env)
    end
})

add_special_form(
  "==", {
    compile = function(args, env)
      return "(" .. cons_to_explist(args, env, " == ") .. ")"
    end,
    eval = function(args, env)
      return M.eval(car(args), env) == M.eval(cadr(args), env)
    end
})

add_special_form(
  "if", {
    compile = function(args, env)
      return "(function() if " .. M.compile(car(args), env) .. " then return " .. M.compile(cadr(args), env) .. " else return " .. M.compile(caddr(args), env) .. " end end)()"
    end,
    eval = function(args, env)
      if M.eval(car(args), env) then
        return M.eval(cadr(args), env)
      else
        return M.eval(caddr(args), env)
      end
    end
})

add_special_form(
  "fn", {
    compile = function(args, env)
      return "(function(" .. cons_to_explist(car(args), env, ", ") .. ") " .. cons_to_explist(cdr(args), env, "\n", true) .. " end)"
    end,
    eval = function(args, env)
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
    end
})

return M
