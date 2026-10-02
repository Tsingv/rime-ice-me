-- 根据上一个上屏词，学习并重排当前普通候选。
-- 数据保存到 Rime 同步目录；将 installation.yaml 的 sync_dir 指向共享目录即可跨设备读取。

local M = {}

local function is_han_codepoint(cp)
  return (cp >= 0x3400 and cp <= 0x4DBF)
      or (cp >= 0x4E00 and cp <= 0x9FFF)
      or (cp >= 0xF900 and cp <= 0xFAFF)
      or (cp >= 0x20000 and cp <= 0x2FA1F)
end

local function char_count(text)
  local ok, n = pcall(utf8.len, text)
  if not ok then return nil end
  return n
end

local function is_han_token(text, max_chars)
  if not text or text == "" then return false end
  local n = char_count(text)
  if not n or n < 1 or n > max_chars then return false end
  for _, cp in utf8.codes(text) do
    if not is_han_codepoint(cp) then return false end
  end
  return true
end

local function to_chars(text)
  local chars = {}
  for _, cp in utf8.codes(text) do
    chars[#chars + 1] = utf8.char(cp)
  end
  return chars
end

-- 返回从长到短的上下文后缀。
-- 例如“中国银行”且 max_chars=3：国银行、银行、行。
local function context_suffixes(text, max_chars)
  local chars = to_chars(text)
  local result = {}
  local max_len = math.min(#chars, max_chars)
  for len = max_len, 1, -1 do
    result[#result + 1] = table.concat(chars, "", #chars - len + 1, #chars)
  end
  return result
end

local function add_count(freq, context, word, delta)
  local row = freq[context]
  if not row then
    row = {}
    freq[context] = row
  end
  row[word] = (row[word] or 0) + delta
end

local function load_freq(path)
  local freq = {}
  local file = io.open(path, "r")
  if not file then return freq end

  for line in file:lines() do
    local context, word, count = line:match("^(.-)\t(.-)\t(%d+)$")
    if context and word and count then
      add_count(freq, context, word, tonumber(count))
    end
  end
  file:close()
  return freq
end

local function append_pair(path, context, word)
  local file = io.open(path, "a")
  if not file then return false end
  file:write(context, "\t", word, "\t1\n")
  file:close()
  return true
end

-- 对每个候选优先采用最长上下文的词频；该候选没有记录时再退化到短后缀。
local function candidate_count(env, contexts, word)
  for _, context in ipairs(contexts) do
    local row = env.freq[context]
    local count = row and row[word]
    if count then return count end
  end
  return 0
end

local function has_context_data(env, contexts)
  for _, context in ipairs(contexts) do
    if env.freq[context] then return true end
  end
  return false
end

local function learn_pair(env, previous, current)
  for _, context in ipairs(context_suffixes(previous, env.max_context_chars)) do
    add_count(env.freq, context, current, 1)
    append_pair(env.data_path, context, current)
  end
end

function M.init(env)
  local config = env.engine.schema.config
  local namespace = env.name_space:gsub("^%*", "")

  env.boost = config:get_int(namespace .. "/boost") or 4
  env.scan_limit = config:get_int(namespace .. "/scan_limit") or 50
  env.max_context_chars = config:get_int(namespace .. "/max_context_chars") or 4
  env.max_token_chars = config:get_int(namespace .. "/max_token_chars") or 8
  env.min_count = config:get_int(namespace .. "/min_count") or 1

  -- ponytail: one append-only file; concurrent cloud writes can conflict, split by device if needed.
  env.data_path = rime_api.get_sync_dir() .. "/context_bigram.tsv"
  env.freq = load_freq(env.data_path)
  env.last_text = nil

  env.commit_connection = env.engine.context.commit_notifier:connect(function(ctx)
    local current = ctx:get_commit_text()

    if is_han_token(current, env.max_token_chars) then
      if is_han_token(env.last_text, env.max_token_chars) then
        learn_pair(env, env.last_text, current)
      end
      env.last_text = current
    else
      -- 标点、英文、数字等打断上下文，避免跨句误学习。
      env.last_text = nil
    end
  end)
end

function M.func(input, env)
  local previous = env.last_text
  if not is_han_token(previous, env.max_token_chars) then
    for cand in input:iter() do yield(cand) end
    return
  end

  local contexts = context_suffixes(previous, env.max_context_chars)
  if not has_context_data(env, contexts) then
    for cand in input:iter() do yield(cand) end
    return
  end

  local buffered = {}
  local index = 0

  for cand in input:iter() do
    index = index + 1
    local count = 0
    if is_han_token(cand.text, env.max_token_chars) then
      count = candidate_count(env, contexts, cand.text)
      if count < env.min_count then count = 0 end
    end

    buffered[#buffered + 1] = {
      cand = cand,
      index = index,
      -- 按候选实际消耗的编码长度排序，兼容全拼、双拼、简拼和分隔符。
      -- 不按中文字数判断，避免高频单字越过覆盖更多输入的词语。
      matched_length = cand._end - cand.start,
      -- 原始名次作为基础；上下文出现一次，大约可前移 boost 位。
      score = count * env.boost - index,
    }

    if index >= env.scan_limit then break end
  end

  table.sort(buffered, function(a, b)
    if a.matched_length ~= b.matched_length then
      return a.matched_length > b.matched_length
    end
    -- 只有覆盖同一段输入的候选才比较上下文分数。
    if a.cand.start ~= b.cand.start then return a.cand.start < b.cand.start end
    if a.score == b.score then return a.index < b.index end
    return a.score > b.score
  end)

  for _, item in ipairs(buffered) do
    yield(item.cand)
  end
  for cand in input:iter() do
    yield(cand)
  end
end

function M.fini(env)
  if env.commit_connection then
    env.commit_connection:disconnect()
    env.commit_connection = nil
  end
end

return M
