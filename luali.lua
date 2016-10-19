local form = require("form")
local parse = require("parse")

local cons = form.cons

local function print_parse(s)
  parse.parse(coroutine.wrap(function() coroutine.yield(s) end), function(f) print(form.to_lua(f)) end)
end

local function eval_parse(s)
  parse.parse(coroutine.wrap(function() coroutine.yield(s) end), function(f) loadstring("return " .. form.to_lua(f))() end)
end

print_parse("  hoge piyo foo")
print_parse("hoge   ")
print_parse("true")
print_parse("false")
print_parse("nil")
print_parse("-23.4e5")
print_parse('"foo"')
print_parse('"fo\\\"oo"')
print_parse("'bar")
print_parse("''bar")
print_parse("'nil")
print_parse("(foo)")
print_parse("(print a 123 nil true -123)")
print_parse("()")
print_parse(" ( ) ")
print_parse("(list 'foo (f 1 2 3) (b nil false true \"hoge\"))")
print_parse('{"x" 12 "y" 34}')
print_parse('["a" "b" "c"]')
print_parse("(fn (x y) (print (+ x y)))")
print_parse("(fn ())")
print_parse("(fn (x) (print x) (return (+ x 1)))")

eval_parse("(print ((fn (x y) (+ 100 (+ x y))) 12 34))")
