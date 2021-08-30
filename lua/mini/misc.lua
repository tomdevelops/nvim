-- MIT License Copyright (c) 2021 Evgeni Chasnovski
--
-- Lua module which implements miscellaneous useful functions.
--
-- This module is designed to not need activation, but it can be done to
-- improve usability. To activate, put this file somewhere into 'lua' folder
-- and call module's `setup()`. For example, put as 'lua/mini/misc.lua' and
-- execute `require('mini.misc').setup()` Lua code. It may have `config`
-- argument which should be a table overwriting default values using same
-- structure.
--
-- Default `config`:
-- {
--   -- List of fields to make global (to be used as independent variables)
--   make_global = { 'put', 'put_text' }
-- }
--
-- Features are described for every function separately.

-- Module and its helper
local MiniMisc = {}
local H = {}

-- Module setup
function MiniMisc.setup(config)
  -- Export module
  _G.MiniMisc = MiniMisc

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)
end

-- Module settings
---- List of fields to make global (to be used as independent variables)
MiniMisc.make_global = { 'put', 'put_text' }

-- Module functionality
---- Helper to print Lua objects in command line
function MiniMisc.put(...)
  local objects = {}
  -- Not using `{...}` because it removes `nil` input
  for i = 1, select('#', ...) do
    local v = select(i, ...)
    table.insert(objects, vim.inspect(v))
  end

  print(table.concat(objects, '\n'))

  return ...
end

---- Helper to print Lua objects in current buffer
function MiniMisc.put_text(...)
  local objects = {}
  -- Not using `{...}` because it removes `nil` input
  for i = 1, select('#', ...) do
    local v = select(i, ...)
    table.insert(objects, vim.inspect(v))
  end

  local lines = vim.split(table.concat(objects, '\n'), '\n')
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  vim.fn.append(lnum, lines)

  return ...
end

---- Execute `f` once and time how long it took
---- @param f Function which execution to benchmark
---- @param ... Arguments when calling `f`
---- @return duration, output Duration (in seconds; up to microseconds) and
----   output of function execution
function MiniMisc.bench_time(f, ...)
  local start_sec, start_usec = vim.loop.gettimeofday()
  local output = f(...)
  local end_sec, end_usec = vim.loop.gettimeofday()
  local duration = (end_sec - start_sec) + 0.000001 * (end_usec - start_usec)

  return duration, output
end

---- Fuzzy filtering and matching
----
---- `fuzzy_match()` reduces a list of `cadidates` to those matching the
---- `word`.  By default it also sorts the output from best to worst matching.
---- Its design is mainly focused on `fuzzy typing completion` use case.
----
---- The current approach is a slightly modified and simplified version of
---- FZF's fast (version 1) algorithm. It is mainly designed for speed
---- sacrificing small amount of match precision. Core ideas:
---- - Word and candidate are matched only if all of word's letters appear in
----   candidate in the same order. The exact matching of word's letters to
----   candidate ones is done in two steps:
----     - Find word's first letter starting from candidate's left and looking
----       forward. Then find word's second letter after the first match, and
----       so on. Candidate is matched if word's last letter is found.
----     - In case of a match, improve it: starting from candidate's match for
----       word's last letter, find word's second to last letter looking
----       backward, and so on. This step tries to improve match for cases like
----       `word='time', candidate='get_time'`: without it word's 't' will be
----       matched with candidate's third letter when in practice fifth letter
----       is more appropriate.
---- - Sorting is done based on comparing candidate's matching of word's
----   letters. It has the following logic (with examples for `word = 'time'`):
----     - Tighter match is more favourable (measured by 'index of last letter'
----       minus 'index of first letter'). So '_time' is a better match than
----       't_ime'. NOTE: due to the fact that currently only one "match
----       improvement" is done, this rule might not always hold. For example,
----       't__ime__time' is a worse match than `t_ime`, despite the fact that
----       it contains an exact word (which didn't end up being matched).
----     - In case of equally tight matches, the one starting earlier is
----       better. So 'time_a' is better than 'a_time'.
----     - In case of equally tight and early matches, the one having more
----       letters matched earlier is better. This is measured by the sum of
----       matched letter indexes. So 'tim_e' is better than 't_ime'.
----     - If previous steps can't decide a better candidate, the one with
----       earlier table index is better. This preserves input ordering of
----       candidates.
----
---- NOTE: currently doesn't work with multibyte symbols.
----
---- @param candidates Lua array of strings inside which word will be searched
---- @param word String which will be searched
---- @param sort (default: `true`) Whether to sort output candidates from best
----   to worst match
---- @param case_sensitive (default: `false`) Whether search is case sensitive.
---- @return matched_candidates, matched_indexes Arrays of matched candidates
----   and their indexes in original input.
function MiniMisc.fuzzy_match(candidates, word, sort, case_sensitive)
  sort = sort or true
  case_sensitive = case_sensitive or false

  local matches = H.fuzzy_filter_impl(word, candidates, case_sensitive)
  if sort then
    table.sort(matches, H.fuzzy_compare)
  end

  return H.matches_to_tuple(matches)
end

---- Fuzzy matching for `MiniCompletion.lsp_completion.process_items`
function MiniMisc.fuzzy_process_lsp_items(items, base, sort, case_sensitive)
  -- Extract completion words from items
  local words = vim.tbl_map(function(x)
    if type(x.textEdit) == 'table' and x.textEdit.newText then
      return x.textEdit.newText
    end
    return x.insertText or x.label or ''
  end, items)

  -- Fuzzy match
  local _, match_inds = MiniMisc.fuzzy_match(words, base, sort, case_sensitive)
  return vim.tbl_map(function(i)
    return items[i]
  end, match_inds)
end

---- Return "first" elements of table as decided by `pairs`
----
---- NOTE: order of elements might be different.
----
---- @param t Table
---- @param n (default: 5) Maximum number of first elements
---- @return Table with at most `n` first elements of `t` (with same keys)
function MiniMisc.head(t, n)
  n = n or 5
  local res, n_res = {}, 0
  for k, val in pairs(t) do
    if n_res >= n then
      return res
    end
    res[k] = val
    n_res = n_res + 1
  end
  return res
end

---- Return "last" elements of table as decided by `pairs`
----
---- This function makes two passes through elements of `t`:
---- - First to count number of elements.
---- - Second to construct result.
----
---- NOTE: order of elements might be different.
----
---- @param t Table
---- @param n (default: 5) Maximum number of last elements
---- @return Table with at most `n` last elements of `t` (with same keys)
function MiniMisc.tail(t, n)
  n = n or 5

  -- Count number of elements on first pass
  local n_all = 0
  for _, _ in pairs(t) do
    n_all = n_all + 1
  end

  -- Construct result on second pass
  local res = {}
  local i, start_i = 0, n_all - n + 1
  for k, val in pairs(t) do
    i = i + 1
    if i >= start_i then
      res[k] = val
    end
  end
  return res
end

-- Helper data
---- Module default config
H.config = {
  make_global = MiniMisc.make_global,
}

-- Helper functions
---- Settings
function H.setup_config(config)
  -- General idea: if some table elements are not present in user-supplied
  -- `config`, take them from default config
  vim.validate({ config = { config, 'table', true } })
  config = vim.tbl_deep_extend('force', H.config, config or {})

  vim.validate({
    make_global = {
      config.make_global,
      function(x)
        if type(x) ~= 'table' then
          return false
        end
        local present_fields = vim.tbl_keys(MiniMisc)
        for _, v in pairs(x) do
          if not vim.tbl_contains(present_fields, v) then
            return false
          end
        end
        return true
      end,
      '`make_global` should be a table with `MiniMisc` actual fields',
    },
  })

  return config
end

function H.apply_config(config)
  for _, v in pairs(config.make_global) do
    _G[v] = MiniMisc[v]
  end
end

---- Fuzzy matching
function H.fuzzy_filter_impl(word, candidates, case_sensitive)
  local insensitive = not case_sensitive

  -- Precompute a table of word's letters
  local n_word = #word
  local letters = {}
  for i = 1, n_word do
    letters[i] = word:sub(i, i)
  end

  local res = {}
  local cand_to_match, let_i, match, pos_last
  for i, cand in ipairs(candidates) do
    -- Make early decision of "not matched" if number of word's letters is
    -- bigger than number of candidate's letters
    if n_word <= #cand then
      cand_to_match = insensitive and cand:lower() or cand
      pos_last, let_i = 0, 1
      while pos_last and let_i <= n_word do
        pos_last = string.find(cand_to_match, letters[let_i], pos_last + 1)
        let_i = let_i + 1
      end
      -- Candidate is a match only if word's last letter is found
      if pos_last then
        match = H.improve_match(pos_last, cand_to_match, letters)
        match.candidate, match.index = cand, i
        table.insert(res, match)
      end
    end
  end

  return res
end

function H.improve_match(pos_last, candidate, letters)
  if #letters == 1 then
    return { pos_width = 0, pos_first = pos_last, pos_sum = pos_last }
  end

  local rev_line = candidate:reverse()
  local n = #candidate
  local rev_last = n - pos_last + 1

  -- Do backward search
  local pos, pos_sum = rev_last, pos_last
  for i = #letters - 1, 1, -1 do
    pos = rev_line:find(letters[i], pos + 1)
    pos_sum = pos_sum + (n - pos + 1)
  end
  local pos_first = n - pos + 1

  return {
    pos_width = pos_last - pos_first,
    pos_first = pos_first,
    pos_sum = pos_sum,
  }
end

function H.fuzzy_compare(a, b)
  -- '_time' is better than 't_ime'
  if a.pos_width < b.pos_width then
    return true
  end
  if a.pos_width == b.pos_width then
    -- 'time_aa' is better than 'aa_time'
    if a.pos_first < b.pos_first then
      return true
    end
    if a.pos_first == b.pos_first then
      -- 'tim_e' is better than 't_ime'
      if a.pos_sum < b.pos_sum then
        return true
      end
      if a.pos_sum == b.pos_sum then
        -- Make sorting stable by preserving index order
        return a.index < b.index
      end
    end
  end
  return false
end

function H.matches_to_tuple(matches)
  local candidates, indexes = {}, {}
  for _, m in pairs(matches) do
    table.insert(candidates, m.candidate)
    table.insert(indexes, m.index)
  end

  return candidates, indexes
end

return MiniMisc