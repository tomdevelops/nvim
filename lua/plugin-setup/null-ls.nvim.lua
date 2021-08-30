local lspconfig = require('lspconfig')
local null_ls = require('null-ls')
local helpers = require('null-ls.helpers')

-- Define 'styler' formatting for R. Package should be installed in library
-- used by `R` command.
local r_styler = {
  name = 'styler',
  method = null_ls.methods.FORMATTING,
  filetypes = { 'r', 'rmd' },
  generator = helpers.formatter_factory({
    command = 'R',
    args = {
      '--slave',
      '--no-restore',
      '--no-save',
      '-e',
      'con <- file("stdin")',
      '-e',
      'res <- styler::style_text(readLines(con))',
      '-e',
      'close(con)',
      '-e',
      'print(res, colored = FALSE)',
    },
    to_stdin = true,
  }),
}

null_ls.register(r_styler)

-- Configuring null-ls for other sources
null_ls.config({
  sources = {
    -- `black` should be set up as callable from command line (be in '$PATH')
    null_ls.builtins.formatting.black,
    -- `stylua` should be set up as callable from command line (be in '$PATH')
    null_ls.builtins.formatting.stylua,
  },
})

-- Set up null-ls server
-- NOTE: currently mappings for formatting with `vim.lsp.buf.formatting()` and
-- `vim.lsp.buf.range_formatting()` are set up for every buffer in
-- 'mappings-leader.vim'. This is done to make 'which-key' respect labels.
lspconfig['null-ls'].setup({})