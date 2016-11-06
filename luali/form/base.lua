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
        locals = setmetatable({}, {__index = parent.locals})
      } or
      {
        global = setmetatable({}, {__index = _G}),
        locals = {}
      }, env_mt)
end

local lisp_form_handlers = {}

local function lisp_form_handler(form)
  if type(form) ~= "table" then
    return nil
  end
  local mt = getmetatable(form)
  return mt and lisp_form_handlers[mt.lisp_form_type]
end

local function compile_quoted_table(t, env)
  local entries = {}
  for i, v in pairs(t) do
    table.insert(entries, "[" .. M.compile_quoted(i, env) .. "] = " .. M.compile_quoted(v, env))
  end
  return "({" .. table.concat(entries, ", ") .. "})"
end

local data_form_handlers = {
  ["nil"] = {
    compile = tostring
  },
  boolean = {
    compile = tostring
  },
  number = {
    compile = function(form, env)
      if util.is_nan(form) then
        return "(0 / 0)"
      end
      if form == util.inf then
        return "(1 / 0)"
      end
      if form == -util.inf then
        return "(-(1 / 0))"
      end
      return tostring(form)
    end
  },
  string = {
    compile = function(form, env) return string.format("%q", form) end
  },
  table = {
    compile = function(form, env)
      local entries = {}
      for i, v in pairs(form) do
        table.insert(entries, "[" .. M.compile(i, env) .. "] = " .. M.compile(v, env))
      end
      return "({" .. table.concat(entries, ", ") .. "})"
    end,
    eval = function(form, env)
      local result = {}
      for i, v in pairs(form) do
        result[M.eval(i, env)] = M.eval(v, env)
      end
      return result
    end,
    compile_quoted = compile_quoted_table
  }
}

local function form_processor(name, default)
  return function(form, env)
    local lf_handler = lisp_form_handler(form)
    if lf_handler then
      return lf_handler[name](form, env)
    end
    local data_form_handler = data_form_handlers[type(form)]
    if data_form_handler then
      local f = data_form_handler[name] or default
      if f then
        return f(form, env)
      end
    end
    error("attempt to " .. name .. tostring(form))
  end
end

M.compile = form_processor("compile")

M.eval = form_processor("eval", function(form, env) return form end)

M.compile_quoted = form_processor("compile_quoted", function(form, env) return M.compile(form, env) end)

local function define_form(name, init, methods)
  local mt = {lisp_form_type = name}
  methods.new = function(...)
    return setmetatable(init(...), mt)
  end
  methods.is = function(form)
    return lisp_form_handler(form) == methods
  end
  methods.compile_quoted = function(form, env)
    return "setmetatable(" .. compile_quoted_table(form, env) .. ", " .. compile_quoted_table(mt, env) .. ")"
  end
  lisp_form_handlers[name] = methods
  return methods
end

local symbol = define_form(
  "symbol",
  function(name)
    return {name = name}
  end, {
    compile = function(form, env)
      return form.name
    end,
    eval = function(form, env)
      return env:find_value(form.name)
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

local function reverse_list(cons)
  local result = nil
  for cons in each_cons(cons) do
    result = M.cons(car(cons), result)
  end
  return result
end

local function cons_to_table(cons, f)
  local result = {}
  local nil_placeholder = {}
  local index = 1
  for cons in each_cons(cons) do
    result[index] = (f or car)(cons) or nil_placeholder
    index = index + 1
  end
  for i, v in ipairs(result) do
    if v == nil_placeholder then
      result[i] = nil
    end
  end
  return result
end

local function cons_to_codes(cons, env)
  return cons_to_table(cons, function(cons) return M.compile(car(cons), env) end)
end

local function cons_to_explist(cons, env)
  return table.concat(cons_to_codes(cons, env), ", ")
end

local special_forms = {}

local function symbol_special_form(symbol)
  return M.is_symbol(symbol) and special_forms[symbol.name]
end

local cons = define_form(
  "cons",
  function(car, cdr)
    return {car = car, cdr = cdr}
  end, {
    compile = function(form, env)
      local special_form = symbol_special_form(car(form))
      if special_form then
        return special_form.compile(cdr(form), env)
      end
      return M.compile(car(form), env) .. "(" .. cons_to_explist(cdr(form), env) .. ")"
    end,
    eval = function(form, env)
      local special_form = symbol_special_form(car(form))
      if special_form then
        return special_form.eval(cdr(form), env)
      end
      local function call(args, ...)
        if not args then
          return M.eval(car(form), env)(...)
        end
        return call(cdr(args), M.eval(car(args), env), ...)
      end
      return call(reverse_list(cdr(form)))
    end
})
M.cons = cons.new
M.is_cons = cons.is

local function add_special_form(name, methods)
  special_forms[name] = methods
end

add_special_form(
  "quote", {
    compile = function(args, env)
      return M.compile_quoted(car(args), env)
    end,
    eval = function(args, env)
      return car(args)
    end
})

add_special_form(
  ".", {
    compile = function(args, env)
      return M.compile(car(args), env) .. "[" .. M.compile(cadr(args), env) .. "]"
    end,
    eval = function(args, env)
      return M.eval(car(args), env)[M.eval(cadr(args), env)]
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
      local vars = cons_to_codes(args, env)
      local assign = nil
      if #vars > 1 then
        assign = " = " .. table.remove(vars, #vars)
      end
      return "local " .. table.concat(vars, ", ") .. assign
    end,
    eval = function(args, env)
      local arg_list = cons_to_table(args)
      local values = {M.eval(table.remove(arg_list, #arg_list), env)}
      for i, value in ipairs(values) do
        env:set_local(arg_list[i].name, value)
      end
    end
})

add_special_form(
  "=", {
    compile = function(args, env)
      return M.compile(car(args), env) .. " = " .. M.compile(cadr(args))
    end,
    eval = function(args, env)
      --
    end
})

add_special_form(
  "+", {
    compile = function(args, env)
      return "(" .. table.concat(cons_to_codes(args, env), " + ") .. ")"
    end,
    eval = function(args, env)
      return M.eval(car(args), env) + M.eval(cadr(args), env) --
    end
})

add_special_form(
  "==", {
    compile = function(args, env)
      return "(" .. M.compile(car(args), env) .. " == " .. M.compile(cadr(args)) .. ")"
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
      local codes = cons_to_codes(cdr(args), env)
      if #codes > 0 then
        codes[#codes] = "return " .. codes[#codes]
      end
      return "(function(" .. cons_to_explist(car(args), env) .. ") " .. table.concat(codes, ";\n") .. " end)"
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
