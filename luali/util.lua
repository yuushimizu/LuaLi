local M = {}

local function as_string(value, table_indent)
  table_indent = table_indent or ""
  local value_type = type(value)
  if value_type == "table" then
    if getmetatable(value) and getmetatable(value).__tostring then
      return tostring(value)
    end
    local result = "{\n"
    local next_table_indent = table_indent .. "  "
    for k, v in pairs(value) do
      result = result .. next_table_indent .. "[" .. as_string(k, next_table_indent) .. "] = " .. as_string(v, next_table_indent) .. ",\n"
    end
    result = result .. table_indent .. "}"
    return result
  elseif value_type == "string" then
    return '"' .. value .. '"'
  end
  return tostring(value)
end

function M.dump(...)
  for _, arg in ipairs({...}) do
    print(as_string(arg))
  end
end

function M.identity(x)
  return x
end

function M.identity1(x)
  return (x)
end

function M.constantly(x)
  return function() return x end
end

return M
