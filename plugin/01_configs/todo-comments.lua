local has_todo, todo = pcall(require, 'todo-comments')
if not has_todo then
  return
end

todo.setup({
  highlight = {
    before = '',
    keyword = 'bg',
    after = '',
    -- Match without the extra colon
    pattern = [[.*<(KEYWORDS)\s*]],
  },
  search = {
    -- Match without the extra colon
    pattern = [[\b(KEYWORDS)\b]],
  },
})