local form = require("form")
local parse = require("parse")

local cons = form.cons

print(form.to_lua(cons(form.symbol("print"), cons(123, cons("hoge", cons(false))))))
print(form.to_lua(cons(form.symbol("print"))))

-- print(parser.next("(print 23.4e3 \"foo\" true)"))
local function print_parse(s)
  parse.parse(coroutine.wrap(function() coroutine.yield(s) end), function(f) print(form.to_lua(f)) end)
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
