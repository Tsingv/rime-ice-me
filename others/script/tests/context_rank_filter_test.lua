-- 在仓库根目录运行：lua others/script/tests/context_rank_filter_test.lua
local filter = dofile("lua/context_rank_filter.lua")
local passed = 0

local function candidate(text, start, finish)
  return { text = text, start = start, _end = finish }
end

local function check(name, candidates, expected, options)
  options = options or {}
  local env = {
    last_text = options.no_context and nil or "我",
    freq = { ["我"] = options.counts or { ["是"] = 10000, ["事情"] = 10 } },
    max_context_chars = 4,
    max_token_chars = 8,
    min_count = 2,
    boost = 4,
    scan_limit = options.scan_limit or 50,
  }
  if options.no_context then env.last_text = nil end
  local position = 0
  local input = {}
  function input:iter()
    return function()
      position = position + 1
      return candidates[position]
    end
  end
  local actual = {}
  _G.yield = function(cand) actual[#actual + 1] = cand.text end
  filter.func(input, env)
  assert(table.concat(actual, "|") == expected, name .. ": " .. table.concat(actual, "|"))
  passed = passed + 1
end

check("双拼完整词优先", {
  candidate("是", 0, 2), candidate("时间", 0, 4), candidate("事情", 0, 4),
}, "事情|时间|是")
check("全拼完整词优先", {
  candidate("是", 0, 3), candidate("时间", 0, 7),
}, "时间|是")
check("简拼按编码范围而非字数", {
  candidate("是", 0, 1), candidate("时间", 0, 2),
}, "时间|是")
check("带分隔符的输入", {
  candidate("是", 0, 3), candidate("时间", 0, 8),
}, "时间|是")
check("部分上屏后起点非零", {
  candidate("是", 4, 6), candidate("时间", 4, 8),
}, "时间|是")
check("同范围仍可学习单字", {
  candidate("时", 0, 2), candidate("是", 0, 2),
}, "是|时")
check("多级部分匹配", {
  candidate("是", 0, 2), candidate("事情", 0, 4), candidate("时间表", 0, 6),
}, "时间表|事情|是")
check("低于学习阈值保持原顺序", {
  candidate("时", 0, 2), candidate("是", 0, 2),
}, "时|是", { counts = { ["是"] = 1 } })
check("没有上下文保持原顺序", {
  candidate("时间", 0, 4), candidate("是", 0, 2),
}, "时间|是", { no_context = true })
check("没有历史记录保持原顺序", {
  candidate("时间", 0, 4), candidate("是", 0, 2),
}, "时间|是", { counts = {} })
check("扫描边界不丢失或重复候选", {
  candidate("时间", 0, 4), candidate("事情", 0, 4), candidate("是", 0, 2),
}, "事情|时间|是", { scan_limit = 2 })
print(string.format("PASS: %d context_rank_filter regression cases", passed))
