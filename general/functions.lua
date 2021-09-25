local H = {}

-- Show Neoterm's active REPL, i.e. in which command will be executed when one
-- of `TREPLSend*` will be used
_G.print_active_neoterm = function()
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

-- Zoom in and out of a buffer, making it full screen in a floating window.
-- This function is useful when working with multiple windows but temporarily
-- needing to zoom into one to see more of the code from that buffer.
local zoom_winid = nil
_G.zoom_toggle = function()
  if zoom_winid and vim.api.nvim_win_is_valid(zoom_winid) then
    vim.api.nvim_win_close(zoom_winid, true)
    zoom_winid = nil
  else
    -- Currently very big `width` and `height` get truncated to maximum allowed
    local opts = { relative = 'editor', row = 0, col = 0, width = 1000, height = 1000 }
    zoom_winid = vim.api.nvim_open_win(0, true, opts)
    vim.cmd([[normal! zz]])
  end
end

-- Create scratch buffer and focus on it
_G.new_scratch_buffer = function()
  local buf = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_win_set_buf(0, buf)
end

-- Compute width of gutter in window with id (`:h win_getid()`) `win_id`
_G.gutter_width = function(win_id)
  -- Compute number of 'editable' columns in current window
  ---- Store current window metadata
  local virtualedit = vim.opt.virtualedit
  local curpos = vim.api.nvim_win_get_cursor(win_id)

  ---- Move cursor to the last visible column
  local last_col = vim.api.nvim_win_call(win_id, function()
    vim.opt.virtualedit = 'all'
    vim.cmd([[normal! g$]])
    return vim.fn.virtcol('.')
  end)

  ---- Restore current window metadata
  vim.opt.virtualedit = virtualedit
  vim.api.nvim_win_set_cursor(win_id, curpos)

  -- Compute result
  return vim.api.nvim_win_get_width(win_id) - last_col
end

-- Resize window to have exactly `text_width` editable columns
-- @param win_id Identifier of window to be resized (`:h win_getid()`). Default:
--   current window.
-- @param text_width Number of editable columns resized window will display.
--   Default: computed based on 'colorcolumn', 'textwidth', and 'winwidth'.
_G.resize_window = function(win_id, text_width)
  win_id = win_id or 0
  text_width = text_width or H.default_text_width(win_id)

  vim.api.nvim_win_set_width(win_id, text_width + _G.gutter_width(win_id))
end

---- Default editable width is computed based on:
---- - If 'colorcolumn' is set, then width is equal to its first element
----   converted to absolute number of columns.
---- - If 'colorcolumn' is not set, then return textwidth.
---- - NOTE: if 'textwidth' is zero, 'winwidth' option is used instead.
H.default_text_width = function(win_id)
  local buf = vim.api.nvim_win_get_buf(win_id)
  local textwidth = vim.api.nvim_buf_get_option(buf, 'textwidth')
  textwidth = (textwidth == 0) and vim.api.nvim_get_option('winwidth') or textwidth

  local colorcolumn = vim.api.nvim_win_get_option(win_id, 'colorcolumn')
  if colorcolumn ~= '' then
    local cc = vim.split(colorcolumn, ',')[1]
    local is_cc_relative = vim.tbl_contains({ '-', '+' }, cc:sub(1, 1))

    if is_cc_relative then
      return textwidth + tonumber(cc)
    else
      return tonumber(cc)
    end
  else
    return textwidth
  end
end

-- Add possibility of nested comment leader. This works by parsing
-- 'commentstring' buffer option, extracting non-whitespace comment leader
-- (symbols on the left of commented line), and modifying 'comments' option (by
-- prepending `n:<leader>`). Does nothing if 'commentstring' is empty or has
-- comment symbols both in front and back (like '/*%s*/').
--
-- Nested comment leader added with this function is useful for formatting
-- nested comments. For example, have in Lua have 'first-level' comments with
-- '--' and 'second-level' comments with '----'. With nested comment leader
-- second type can be formatted with `gq` in the same way as first one.
--
-- Recommended usage is with `autocmd`:
-- `autocmd BufEnter * lua pcall(_G.add_nested_comment_leader)`
--
-- @param buf_id Identifier of buffer in which function will operate. Default:
--   current buffer (identifier 0). NOTE: for most filetypes 'commentstring'
--   option is added only when buffer with this filetype is entered, so using
--   non-current `buf_id` can not lead to desired effect.
_G.add_nested_comment_leader = function(buf_id)
  buf_id = buf_id or 0

  local commentstring = vim.api.nvim_buf_get_option(buf_id, 'commentstring')
  if commentstring == '' then
    return
  end

  -- Extract raw comment leader from 'commentstring' option
  local comment_parts = vim.tbl_filter(function(x)
    return x ~= ''
  end, vim.split(commentstring, '%s', true))

  -- Don't do anything if 'commentstring' is like '/*%s*/' (as in 'json')
  if #comment_parts > 1 then
    return
  end

  -- Get comment leader. Remove whitespace and escape 'dangerous' characters
  local leader = vim.trim(comment_parts[1])

  local comments = vim.api.nvim_buf_get_option(buf_id, 'comments')
  local new_comments = string.format('n:%s,%s', leader, comments)
  vim.api.nvim_buf_set_option(buf_id, 'comments', new_comments)
end
