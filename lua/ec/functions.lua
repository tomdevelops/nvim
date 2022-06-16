-- Helper table
local H = {}

-- Show Neoterm's active REPL, i.e. in which command will be executed when one
-- of `TREPLSend*` will be used
EC.print_active_neoterm = function()
  local msg
  if vim.fn.exists('g:neoterm.repl') == 1 and vim.fn.exists('g:neoterm.repl.instance_id') == 1 then
    msg = 'Active REPL neoterm id: ' .. vim.g.neoterm.repl.instance_id
  elseif vim.g.neoterm.last_id ~= 0 then
    msg = 'Active REPL neoterm id: ' .. vim.g.neoterm.last_id
  else
    msg = 'No active REPL'
  end

  print(msg)
end

-- Create scratch buffer and focus on it
EC.new_scratch_buffer = function()
  local buf = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_win_set_buf(0, buf)
end

-- Make action for `<CR>` which respects completion and autopairs
--
-- Mapping should be done after everything else because `<CR>` can be
-- overridden by something else (notably 'mini-pairs.lua'). This should be an
-- expression mapping:
-- vim.api.nvim_set_keymap('i', '<CR>', 'v:lua._cr_action()', { expr = true })
--
-- Its current logic:
-- - If no popup menu is visible, use "no popup keys" getter. This is where
--   autopairs plugin should be used. Like with 'nvim-autopairs'
--   `get_nopopup_keys` is simply `npairs.autopairs_cr`.
-- - If popup menu is visible:
--     - If item is selected, execute "confirm popup" action and close
--       popup. This is where completion engine takes care of snippet expanding
--       and more.
--     - If item is not selected, close popup and execute '<CR>'. Reasoning
--       behind this is to explicitly select desired completion (currently this
--       is also done with one '<Tab>' keystroke).
EC.cr_action = function()
  if vim.fn.pumvisible() ~= 0 then
    local item_selected = vim.fn.complete_info()['selected'] ~= -1
    if item_selected then
      return H.keys['ctrl-y']
    else
      return H.keys['ctrl-y_cr']
    end
  else
    return require('mini.pairs').cr()
  end
end

-- Insert section
EC.insert_section = function(symbol, total_width)
  symbol = symbol or '='
  total_width = total_width or 79

  -- Insert section template
  local comment_string = vim.bo.commentstring
  local section_template = comment_string:format(string.rep(symbol, total_width - 2))
  vim.fn.append(vim.fn.line('.'), section_template)

  -- Enable Replace mode in appropriate place
  vim.fn.cursor(vim.fn.line('.') + 1, 3)
  vim.cmd([[startreplace]])
end

-- Execute current line with `lua`
EC.execute_lua_line = function()
  local line = 'lua ' .. vim.api.nvim_get_current_line()
  vim.api.nvim_command(line)
  print(line)
  vim.api.nvim_input('<Down>')
end

-- Floating window with lazygit
EC.floating_lazygit = function()
  local buf_id = vim.api.nvim_create_buf(true, true)
  local win_id = vim.api.nvim_open_win(buf_id, true, {
    relative = 'editor',
    width = math.floor(0.8 * vim.o.columns),
    height = math.floor(0.8 * vim.o.lines),
    row = math.floor(0.1 * vim.o.lines),
    col = math.floor(0.1 * vim.o.columns),
    zindex = 99,
  })
  vim.api.nvim_win_set_option(win_id, 'number', false)

  vim.cmd('setlocal bufhidden=wipe')
  vim.b.minipairs_disable = true

  vim.fn.termopen('lazygit', {
    on_exit = function()
      vim.cmd('silent! :checktime')
      vim.cmd('silent! :q')
    end,
  })
  vim.cmd('startinsert')
end

EC.show_minitest_screenshot = function(opts)
  opts = vim.tbl_deep_extend('force', { dir_path = 'tests/screenshots' }, opts or {})
  vim.ui.select(vim.fn.readdir(opts.dir_path), { prompt = 'Choose screenshot:' }, function(screen_path)
    -- Setup
    local buf_id = vim.api.nvim_create_buf(true, true)
    local win_id = vim.api.nvim_open_win(buf_id, true, {
      relative = 'editor',
      width = math.floor(0.8 * vim.o.columns),
      height = math.floor(0.8 * vim.o.lines),
      row = math.floor(0.1 * vim.o.lines),
      col = math.floor(0.1 * vim.o.columns),
      zindex = 99,
    })
    local channel = vim.api.nvim_open_term(buf_id, {})

    --stylua: ignore start
    vim.cmd('setlocal bufhidden=wipe')

    local win_options = {
      colorcolumn = '', fillchars = 'eob: ',    foldcolumn = '0', foldlevel = 999,
      number = false,   relativenumber = false, spell = false,    signcolumn = 'no',
      wrap = true,
    }
    for name, value in pairs(win_options) do
      vim.api.nvim_win_set_option(win_id, name, value)
    end
    --stylua: ignore end

    -- Show
    local lines = vim.fn.readfile(opts.dir_path .. '/' .. screen_path)
    vim.api.nvim_chan_send(channel, table.concat(lines, '\r\n'))

    -- Convenience
    vim.api.nvim_buf_set_keymap(buf_id, 'n', 'q', ':q<CR>', { noremap = true })
    vim.b.miniindentscope_disable = true
    vim.api.nvim_input([[<C-\><C-n>]])
  end)
end

-- Helper data ================================================================
-- Commonly used keys
H.keys = {
  ['cr'] = vim.api.nvim_replace_termcodes('<CR>', true, true, true),
  ['ctrl-y'] = vim.api.nvim_replace_termcodes('<C-y>', true, true, true),
  ['ctrl-y_cr'] = vim.api.nvim_replace_termcodes('<C-y><CR>', true, true, true),
}
