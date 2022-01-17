-- MIT License Copyright (c) 2021 Evgeni Chasnovski

-- Documentation ==============================================================
--- GENERATION OF HELP FILES FROM EMMYLUA-LIKE ANNOTATIONS
---
--- Key design ideas:
--- - Keep documentation next to code by writing EmmyLua-like annotation
---   comments. They mostly will be parsed as is, so formatting should follow
---   built-in guide in |help-writing|. However, custom hooks are allowed at
---   many generation stages for more granular management of output help file.
--- - Generation is done by processing a set of ordered files line by line.
---   Each line can either be considered as a part of documentation block (if
---   it matches certain configurable pattern) or not (considered to be an
---   "afterline" of documentation block). See |MiniDoc.generate()| for more
---   details.
--- - Processing is done by using nested data structures (section, block, file,
---   doc) describing certain parts of help file. See |MiniDoc-data-structures|
---   for more details.
--- - Project specific script can be written as plain Lua file with
---   configuratble path. See |MiniDoc.generate()| for more details.
---
--- # Setup~
---
--- This module needs a setup with `require('mini.doc').setup({})`
--- (replace `{}` with your `config` table). It will create global Lua table
--- `MiniDoc` which you can use for scripting or manually (with
--- `:lua MiniDoc.*`). See |MiniDoc.config| for available config settings.
---
--- # Tips~
---
--- - Some settings tips that might make writing annotation comments easier:
---     - Set up appropriate 'comments' for `lua` file type to respect
---       EmmyLua-like's `---` comment leader. Value `:---,:--` seems to work.
---     - Set up appropriate 'formatoptions' (see also |fo-table|). Consider
---       adding `j`, `n`, `q`, and `r` flags.
---     - Set up appropriate 'formatlistpat' to help auto-formatting lists (if
---       `n` flag is added to 'formatoptions'). One suggestion (not entirely
---       ideal) is a value `^\s*[0-9\-\+\*]\+[\.\)]*\s\+`. This reads as 'at
---       least one special character (digit, `-`, `+`, `*`) possibly followed
---       by some punctuation (`.` or `)`) followed by at least one space is a
---       start of list item'.
--- - Probably one of the most reliable resources for what is considered to be
---   best practice when using this module is this whole plugin. Look at source
---   code for the reference.
---
--- # Comparisons~
---
--- - 'tjdevries/tree-sitter-lua':
---     - Its key design is to use treesitter grammar to parse both Lua code
---       and annotation comments. This makes it not easy to install,
---       customize, and support.
---     - It takes more care about automating output formatting (like auto
---       indentation and line width fit). This plugin leans more to manual
---       formatting with option to supply customized post-processing hooks.
---
--- # Disabling~
---
--- To disable, set `g:minidoc_disable` (globally) or `b:minidoc_disable` (for
--- a buffer) to `v:true`.
---@tag MiniDoc mini.doc

--- DATA STRUCTURES
---
--- Data structures are basically arrays of other structures accompanied with
--- some fields (keys with data values) and methods (keys with function
--- values):
--- - `Section structure` is an array of string lines describing one aspect
---   (determined by section id like '@param', '@return', '@text') of an
---   annotation subject. All lines will be used directly in help file.
--- - `Block structure` is an array of sections describing one annotation
---   subject like function, table, concept.
--- - `File structure` is an array of blocks describing certain file on disk.
---   Basically, file is split into consecutive blocks: annotation lines go
---   inside block, non-annotation - inside `block_afterlines` element of info.
--- - `Doc structure` is an array of files describing a final help file. Each
---   string line from section (when traversed in depth-first fashion) goes
---   directly into output file.
---
--- All structures have these keys:
--- - Fields:
---     - `info` - contains additional information about current structure.
---       For more details see next section.
---     - `parent` - table of parent structure (if exists).
---     - `parent_index` - index of this structure in its parent's array. Useful
---       for adding to parent another structure near current one.
---     - `type` - string with structure type (section, block, file, doc).
--- - Methods (use them as `x:method(args)`):
---     - `insert(self, [index,] child)` - insert `child` to `self` at position
---       `index` (optional; if not supplied, child will be appended to end).
---       Basically, a `table.insert()`, but adds `parent` and `parent_index`
---       fields to `child` while properly updating `self`.
---     - `remove(self [,index])` - remove from `self` element at position
---       `index`. Basically, a `table.remove()`, but properly updates `self`.
---     - `has_descendant(self, predicate)` - whether there is a descendant
---       (structure or string) for which `predicate` returns `true`. In case of
---       success also returns the first such descendant as second value.
---     - `has_lines(self)` - whether structure has any lines (even empty ones)
---       to be put in output file. For section structures this is equivalent to
---       `#self`, but more useful for higher order structures.
---     - `clear_lines(self)` - remove all lines from structure. As a result,
---       this structure won't contribute to output help file.
---
--- Description of `info` fields per structure type:
--- - `Section`:
---     - `id` - captured section identifier. Can be empty string meaning no
---       identifier is captured.
---     - `line_begin` - line number inside file at which section begins.
---     - `line_end` - line number inside file at which section ends.
--- - `Block`:
---     - `afterlines` - array of strings which were parsed from file after
---       this annotation block (up until the next block or end of file).
---       Useful for making automated decisions about what is being documented.
---     - `line_begin` - line number inside file at which block begins.
---     - `line_end` - line number inside file at which block ends.
--- - `File`:
---     - `path` - absolute path to a file.
--- - `Doc`:
---     - `input` - array of input file paths (as in |MiniDoc.generate|).
---     - `output` - output path (as in |MiniDoc.generate|).
---     - `config` - configuration used (as in |MiniDoc.generate|).
---@tag MiniDoc-data-structures

-- Module definition ==========================================================
local MiniDoc = {}
H = {}

--- MODULE SETUP
---
---@param config table: Module config table.
---
---@usage `require('mini.doc').setup({})` (replace `{}` with your `config` table)
function MiniDoc.setup(config)
  -- Export module
  _G.MiniDoc = MiniDoc

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)
end

--- MODULE CONFIG
---
--- Default values:
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
---@text # Notes ~
--- - Hooks are expected to be functions. Their default values might do many
---   things which might change over time, so for more information please look
---   at source code.
--- - Default inference of documented object metadata (tag and object signature
---   at the moment) is done in `block_pre`. Inference is based on string
---   pattern matching, so can lead to false results, although works in most
---   cases. It intentionally works only if first line after block has no
---   indentation and contains all necessary information to determine if
---   inference should happen.
MiniDoc.config = {
  -- Lua string pattern to determine if line has documentation annotation.
  -- First capture group should describe possible section id. Default value
  -- means that annotation line should:
  -- - Start with `---` at first column.
  -- - Anything non-whitespace after `---` will be treated as new section id.
  -- - Single whitespace at the start of main text will be ignored.
  annotation_pattern = '^%-%-%-(%S*) ?',

  -- Identifier of block annotation lines until first captured identifier
  default_section_id = '@text',

  -- Hooks to be applied at certain stage of document life cycle. Should modify
  -- its input in place (and not return new one).
  hooks = {
    -- Applied to block before anything else
    --minidoc_replace_start block_pre = <function that infers header sections (tag and/or signature)>,
    block_pre = function(b)
      -- Infer metadata based on afterlines
      if b:has_lines() and #b.info.afterlines > 0 then
        H.infer_header(b)
      end
    end,
    --minidoc_replace_end

    -- Applied to section before anything else
    --minidoc_replace_start section_pre = <function that replaces current aliases>,
    section_pre = function(s)
      H.replace_aliases(s)
    end,
    --minidoc_replace_end

    -- Applied if section has specified captured id
    sections = {
      --minidoc_replace_start ['@alias'] = <function that registers alias in MiniDoc.current.aliases>,
      ['@alias'] = function(s)
        H.register_alias(s)
        -- NOTE: don't use `s.parent:remove(s.parent_index)` here because it
        -- disrupts iteration over block's section during hook application
        -- (skips next section).
        s:clear_lines()
      end,
      --minidoc_replace_end
      --minidoc_replace_start ['@class'] = <function>,
      ['@class'] = function(s)
        H.enclose_first_word(s, '{%1}')
        H.add_section_heading(s, 'Class')
      end,
      --minidoc_replace_end
      -- For most typical usage see |MiniDoc.afterlines_to_code|
      --minidoc_replace_start ['@eval'] = <function which evaluates its lines and replaces them with returned value>,
      ['@eval'] = function(s)
        local src = table.concat(s, '\n')
        local is_loaded, code = pcall(function()
          return assert(loadstring(src))
        end)
        local output
        if is_loaded then
          MiniDoc.current.eval_section = s
          output = code()
          MiniDoc.current.eval_section = nil
        else
          output = 'MINIDOC ERROR. Parsing Lua code gave the following error:\n' .. code
        end

        s:clear_lines()

        if output == nil then
          return
        end
        if type(output) == 'string' then
          output = vim.split(output, '\n')
        end
        if type(output) ~= 'table' then
          s[1] = 'MINIDOC ERROR. Returned value should be `nil`, `string`, or `table`.'
          return
        end
        for _, x in ipairs(output) do
          s:insert(x)
        end
      end,
      --minidoc_replace_end
      --minidoc_replace_start ['@field'] = <function>,
      ['@field'] = function(s)
        H.enclose_first_word(s, '{%1}')
      end,
      --minidoc_replace_end
      --minidoc_replace_start ['@param'] = <function>,
      ['@param'] = function(s)
        H.enclose_first_word(s, '{%1}')
      end,
      --minidoc_replace_end
      --minidoc_replace_start ['@private'] = <function which registers block for removal>,
      ['@private'] = function(s)
        s.parent.info._is_private = true
      end,
      --minidoc_replace_end
      --minidoc_replace_start ['@return'] = <function>,
      ['@return'] = function(s)
        H.add_section_heading(s, 'Return')
      end,
      --minidoc_replace_end
      --minidoc_replace_start ['@seealso'] = <function>,
      ['@seealso'] = function(s)
        H.add_section_heading(s, 'See also')
      end,
      --minidoc_replace_end
      --minidoc_replace_start ['@signature'] = <function which formats signature of documented object>,
      ['@signature'] = function(s)
        for i, _ in ipairs(s) do
          -- Add extra formatting to make it stand out
          s[i] = H.format_signature(s[i])

          -- Align accounting for concealed characters
          s[i] = H.align_text(s[i], 78, 'center')
        end
      end,
      --minidoc_replace_end
      --minidoc_replace_start ['@tag'] = <function which turns its line in proper tag lines>,
      ['@tag'] = function(s)
        for i, _ in ipairs(s) do
          -- Enclose every word in `*`
          s[i] = s[i]:gsub('(%S+)', '%*%1%*')

          -- Align to right edge accounting for concealed characters
          s[i] = H.align_text(s[i], 78, 'right')
        end
      end,
      --minidoc_replace_end
      --minidoc_replace_start ['@text'] = <function which purposefully does nothing>,
      ['@text'] = function() end,
      --minidoc_replace_end
      --minidoc_replace_start ['@usage'] = <function>,
      ['@usage'] = function(s)
        H.add_section_heading(s, 'Usage')
      end,
      --minidoc_replace_end
    },

    -- Applied to section after all previous steps
    --minidoc_replace_start section_post = <function>,
    section_post = function(s) end,
    --minidoc_replace_end

    -- Applied to block after all previous steps
    --minidoc_replace_start block_post = <function which does many things>,
    block_post = function(b)
      -- Remove block if it is private
      if b.info._is_private then
        b:clear_lines()
        return
      end

      local found_param, found_field = false, false
      H.apply_recursively(function(x)
        if not (type(x) == 'table' and x.type == 'section') then
          return
        end

        -- Add headings before first occurence of a section which type usually
        -- appear several times
        if not found_param and x.info.id == '@param' then
          H.add_section_heading(x, 'Parameters')
          found_param = true
        end
        if not found_field and x.info.id == '@field' then
          H.add_section_heading(x, 'Fields')
          found_field = true
        end

        -- Move all tag sections in the beginning. NOTE: due to depth-first
        -- nature, this approach will reverse order of tag sections if there
        -- are more than one; doesn't seem to be a big deal.
        if x.info.id == '@tag' then
          x.parent:remove(x.parent_index)
          x.parent:insert(1, x)
        end
      end, b)

      if b:has_lines() then
        b:insert(1, H.as_struct({ H.separator_block }, 'section'))
        b:insert(H.as_struct({ '' }, 'section'))
      end
    end,
    --minidoc_replace_end

    -- Applied to file after all previous steps
    --minidoc_replace_start file = <function>,
    file = function(f)
      if f:has_lines() then
        f:insert(1, H.as_struct({ H.as_struct({ H.separator_file }, 'section') }, 'block'))
        f:insert(H.as_struct({ H.as_struct({ '' }, 'section') }, 'block'))
      end
    end,
    --minidoc_replace_end

    -- Applied to doc after all previous steps
    --minidoc_replace_start doc = <function>,
    doc = function(d)
      d:insert(
        H.as_struct(
          { H.as_struct({ H.as_struct({ ' vim:tw=78:ts=8:noet:ft=help:norl:' }, 'section') }, 'block') },
          'file'
        )
      )
    end,
    --minidoc_replace_end
  },

  -- Path (relative to current directory) to script which handles project
  -- specific help file generation (like custom input files, hooks, etc.).
  script_path = 'minidoc.lua',
}
--minidoc_afterlines_end

-- Module data ================================================================
--- TABLE WITH INFORMATION ABOUT CURRENT STATE OF AUTO-GENERATION
---
--- It is reset at the beginning and end of `MiniDoc.generate()`.
---
--- At least these keys are supported:
--- - {aliases} - table with keys being alias name and values - alias
---   description and single string (using `\n` to separate lines).
--- - {eval_section} - input section of `@eval` section hook. Can be used for
---   information about current block, etc.
MiniDoc.current = {}

--- DEFAULT HOOKS
---
--- This is default value of `MiniDoc.config.hooks`. Use it if only a little
--- tweak is needed.
MiniDoc.default_hooks = MiniDoc.config.hooks

-- Module functionality =======================================================
--- GENERATE HELP FILE
---
--- # Process~
--- - Main parameters for help generation are an array of input file paths and
---   path to output help file.
--- - Parse all inputs:
---   - For each file, lines are processed top to bottom in order to create an
---     array of documentation blocks. Each line is tested on match to certain
---     pattern (`MiniDoc.config.annotation_pattern`) to determine if line is a
---     part of annotation (goes to "current block" after removing matched
---     characters) or not (goes to afterlines of "current block"). Also each
---     matching pattern should provide one capture group extracting section id.
---   - Each block's annotation lines are processed top to bottom. If line had
---     captured section id, it is a first line of "current section" (first
---     block lines are allowed to not specify section id; by default it is
---     `@text`). All subsequent lines without captured section id go into
---     "current section".
--- - Apply hooks (they should modify its input in place, which is possible due
---   to 'table nature' of all possible inputs):
---     - Each block is processed by `MiniDoc.config.hooks.block_pre`. This is a
---       designated step for auto-generation of sections from descibed
---       annotation subject (like sections with id `@tag`, `@type`).
---     - Each section is processed by `MiniDoc.config.hooks.section_pre`.
---     - Each section is processed by corresponding
---       `MiniDoc.config.hooks.sections` function (table key equals to section
---       id). This is a step where most of formatting should happen (like
---       wrap first word of `@param` section with `{` and `}`, append empty
---       line to section, etc.).
---     - Each section is processed by `MiniDoc.config.hooks.section_post`.
---     - Each block is processed by `MiniDoc.config.hooks.block_post`. This is
---       a step for processing block after formatting is done (like add first
---       line with `----` delimiter).
---     - Each file is processed by `MiniDoc.config.hooks.file`. This is a step
---       for adding any file-related data (like add first line with `====`
---       delimiter).
---     - Doc is processed by `MiniDoc.config.hooks.doc`. This is a step for
---       adding any helpfile-related data (maybe like table of contents).
--- - Collect all strings from sections in depth-first fashion (equivalent to
---   nested "for all files -> for all blocks -> for all sections -> for all
---   strings -> add string to output") and write them to output file. Strings
---   can have `\n` character indicating start of new line.
---
--- # Project specific script~
--- If no arguments are supplied, first there is an attempt to source project
--- specific script. This is basically a `luafile <MiniDoc.config.script_path>`
--- with current Lua runtime while caching and restoring current
--- `MiniDoc.config`. Its successful execution stops any further generation
--- actions while error means proceeding generation as if no script was found.
---
--- Typical script content might include definition of custom hooks, input and
--- output files with eventual call to `require('mini.doc').generate()` (with
--- or without arguments).
---
---@param input `table` Array of file paths which will be processed in supplied
---   order. Default: all '.lua' files from current directory following by all
---   such files in these subdirectories: 'lua/', 'after/', 'colors/'. Note:
---   any 'init.lua' file is placed before other files from the same directory.
---@param output `string` Path for output help file. Default:
---   `doc/<current_directory>.txt` (designed to be used for generating help
---   file for plugin).
---@param config `table` Configuration overriding parts of `MiniDoc.config`.
---
---@return `table` Document structure which was generated and used for output
---   help file or `nil` in case `minidoc.lua` was successfully used.
function MiniDoc.generate(input, output, config)
  -- Try sourcing local 'minidoc.lua' first (if not already doing it)
  if not H.generate_is_active and input == nil and output == nil and config == nil then
    local config_cache = MiniDoc.config
    -- Prevent recursion
    H.generate_is_active = true

    local success = pcall(vim.cmd, 'luafile ' .. MiniDoc.config.script_path)

    MiniDoc.config = config_cache
    H.generate_is_active = nil

    if success then
      return
    end
  end

  input = input or H.default_input()
  output = output or H.default_output()
  config = vim.tbl_deep_extend('force', MiniDoc.config, config or {})

  -- Prepare table for current information
  MiniDoc.current = {}

  -- Parse input files
  local doc = H.new_struct('doc', { input = input, output = output, config = config })
  for _, path in ipairs(input) do
    local lines = H.file_read(path)
    local block_arr = H.lines_to_block_arr(lines, config)
    local file = H.new_struct('file', { path = path })
    for _, b in ipairs(block_arr) do
      file:insert(b)
    end

    doc:insert(file)
  end

  -- Apply hooks
  H.apply_hooks(doc, config.hooks)

  -- Gather string lines in depth-first fashion
  local help_lines = H.collect_strings(doc)

  -- Write helpfile
  H.file_write(output, help_lines)

  -- Clear current information
  MiniDoc.current = {}

  return doc
end

--- CONVERT AFTERLINES TO CODE
---
--- This function is designed to be used together with `@eval` section to
--- automate documentation of certain values (notable default values of a
--- table). It processes afterlines based on certain directives and makes
--- output looking like a code block.
---
--- Most common usage is by adding the following section in your annotation:
--- `@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)`
---
--- # Directives ~
--- Directives are special comments that are processed using Lua string pattern
--- capabilities (so beware of false positives). Each directive should be put
--- on its separate line. Supported directives:
--- - `--minidoc_afterlines_end` denotes a line at afterlines end. Only all
---   lines before it will be considered as afterlines. Useful if there is
---   extra code in afterlines which shouldn't be used.
--- - `--minidoc_replace_start <replacement>` and `--minidoc_replace_end`
---   denote lines between them which should be replaced with `<replacement>`.
---   Useful for manually changing what should be placed in output like in case
---   of replacing function body with something else.
---
--- Here is an example. Suppose having these afterlines:
--- >
---   --minidoc_replace_start {
---   M.config = {
---     --minidoc_replace_end
---     param_one = 1,
---     --minidoc_replace_start param_fun = <function>
---     param_fun = function(x)
---       return x + 1
---     end
---     --minidoc_replace_end
---   }
---   --minidoc_afterlines_end
---
---   return M
--- <
---
--- After adding `@eval` section those will be formatted as:
--- >
---   {
---     param_one = 1,
---     param_fun = <function>
---   }
--- <
---@param struct `table` Block or section structure which after lines will be
---   converted to code.
---
---@return `string` Single string (using `\n` to separate lines) describing
---   afterlines as code block in help file.
function MiniDoc.afterlines_to_code(struct)
  if not (type(struct) == 'table' and (struct.type == 'section' or struct.type == 'block')) then
    H.notify('Input to `MiniDoc.afterlines_to_code()` should be either section or block.')
    return
  end

  if struct.type == 'section' then
    struct = struct.parent
  end
  local src = table.concat(struct.info.afterlines, '\n')

  -- Process directives
  -- Try to extract afterlines
  src = src:match('^(.-)\n%s*%-%-minidoc_afterlines_end') or src

  -- Make replacements
  src = src:gsub('%-%-minidoc_replace_start%s*(.-)\n.-%-%-minidoc_replace_end', '%1')

  -- Convert to a standalone code. NOTE: indent is needed because of how `>`
  -- and `<` work (any line starting in column 1 stops code block).
  src = H.ensure_indent(src, 2)
  return '>\n' .. src .. '\n<'
end

-- Helper data ================================================================
-- Module default config
H.default_config = MiniDoc.config

-- Alias registry. Keys are alias name, values - single string of alias
-- description with '\n' separating output lines.
H.alias_registry = {}

-- Structure separators
H.separator_block = string.rep('-', 78)
H.separator_file = string.rep('=', 78)

-- Patterns for working with afterlines. At the moment deliberately crafted to
-- work only on first line without indent.
--stylua: ignore start
H.afterlines_patterns = {
  -- Determine if line is a function definition. Captures function name and
  -- arguments. For reference see '2.5.9 – Function Definitions' in Lua manual.
  function_definition = {
    '^function%s+(%S-)(%b())',             -- Regular definition
    '^local%s+function%s+(%S-)(%b())',     -- Local definition
    '^(%S*)%s*=%s*function(%b())',         -- Regular assignment
    '^local%s+(%S*)%s*=%s*function(%b())', -- Local assignment
  },

  -- Determine if line is a general assignment
  general_assignment = {
    '^(%S-)%s*=',         -- General assignment
    '^local%s+(%S-)%s*=', -- Local assignment
  }
}
--stylua: ignore end

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
function H.setup_config(config)
  -- General idea: if some table elements are not present in user-supplied
  -- `config`, take them from default config
  vim.validate({ config = { config, 'table', true } })
  config = vim.tbl_deep_extend('force', H.default_config, config or {})

  vim.validate({
    ['annotation_pattern'] = { config.default_section_id, 'string' },
    ['default_section_id'] = { config.default_section_id, 'string' },

    hooks = { config.hooks, 'table' },
    ['hooks.block_pre'] = { config.hooks.block_pre, 'function' },

    ['hooks.sections'] = { config.hooks.sections, 'table' },
    ['hooks.sections.@alias'] = { config.hooks.sections['@alias'], 'function' },
    ['hooks.sections.@class'] = { config.hooks.sections['@class'], 'function' },
    ['hooks.sections.@eval'] = { config.hooks.sections['@eval'], 'function' },
    ['hooks.sections.@field'] = { config.hooks.sections['@field'], 'function' },
    ['hooks.sections.@param'] = { config.hooks.sections['@param'], 'function' },
    ['hooks.sections.@private'] = { config.hooks.sections['@private'], 'function' },
    ['hooks.sections.@return'] = { config.hooks.sections['@return'], 'function' },
    ['hooks.sections.@seealso'] = { config.hooks.sections['@seealso'], 'function' },
    ['hooks.sections.@signature'] = { config.hooks.sections['@signature'], 'function' },
    ['hooks.sections.@tag'] = { config.hooks.sections['@tag'], 'function' },
    ['hooks.sections.@text'] = { config.hooks.sections['@text'], 'function' },
    ['hooks.sections.@usage'] = { config.hooks.sections['@usage'], 'function' },

    ['hooks.block_post'] = { config.hooks.block_post, 'function' },
    ['hooks.file'] = { config.hooks.file, 'function' },
    ['hooks.doc'] = { config.hooks.doc, 'function' },

    ['script_path'] = { config.script_path, 'string' },
  })

  return config
end

function H.apply_config(config)
  MiniDoc.config = config
end

function H.is_disabled()
  return vim.g.minidoc_disable == true or vim.b.minidoc_disable == true
end

-- Default documentation targets ----------------------------------------------
function H.default_input()
  -- Search in current and recursively in other directories for files with
  -- 'lua' extension
  local res = {}
  for _, dir_glob in ipairs({ '.', 'lua/**', 'after/**', 'colors/**' }) do
    local files = vim.fn.globpath(dir_glob, '*.lua', false, true)

    -- Use full paths
    files = vim.tbl_map(function(x)
      return vim.fn.fnamemodify(x, ':p')
    end, files)

    -- Put 'init.lua' first among files from same directory
    table.sort(files, function(a, b)
      if vim.fn.fnamemodify(a, ':h') == vim.fn.fnamemodify(b, ':h') then
        if vim.fn.fnamemodify(a, ':t') == 'init.lua' then
          return true
        end
        if vim.fn.fnamemodify(b, ':t') == 'init.lua' then
          return false
        end
      end

      return a < b
    end)
    table.insert(res, files)
  end

  return vim.tbl_flatten(res)
end

function H.default_output()
  local cur_dir = vim.fn.fnamemodify(vim.loop.cwd(), ':t:r')
  return ('doc/%s.txt'):format(cur_dir)
end

-- Parsing --------------------------------------------------------------------
function H.lines_to_block_arr(lines, config)
  local matched_prev, matched_cur

  local res = {}
  local block_raw = { annotation = {}, section_id = {}, afterlines = {}, line_begin = 1 }

  for i, l in ipairs(lines) do
    local from, to, section_id = string.find(l, config.annotation_pattern)
    matched_prev, matched_cur = matched_cur, from ~= nil

    if matched_cur then
      if not matched_prev then
        -- Finish current block
        block_raw.line_end = i - 1
        table.insert(res, H.raw_block_to_block(block_raw, config))

        -- Start new block
        block_raw = { annotation = {}, section_id = {}, afterlines = {}, line_begin = i }
      end

      -- Add annotation line without matched annotation pattern
      table.insert(block_raw.annotation, ('%s%s'):format(l:sub(0, from - 1), l:sub(to + 1)))

      -- Add section id (it is empty string in case of no section id capture)
      table.insert(block_raw.section_id, section_id or '')
    else
      -- Add afterline
      table.insert(block_raw.afterlines, l)
    end
  end
  block_raw.line_end = #lines
  table.insert(res, H.raw_block_to_block(block_raw, config))

  return res
end

-- Raw block structure is an intermediate step added for convenience. It is
-- a table with the following keys:
-- - `annotation` - lines (after removing matched annotation pattern) that were
--   parsed as annotation.
-- - `section_id` - array with length equal to `annotation` length with strings
--   captured as section id. Empty string of no section id was captured.
-- - Everything else is used as block info (like `afterlines`, etc.).
function H.raw_block_to_block(block_raw, config)
  if #block_raw.annotation == 0 and #block_raw.afterlines == 0 then
    return nil
  end

  local block = H.new_struct('block', {
    afterlines = block_raw.afterlines,
    line_begin = block_raw.line_begin,
    line_end = block_raw.line_end,
  })
  local block_begin = block.info.line_begin

  -- Parse raw block annotation lines from top to bottom. New section starts
  -- when section id is detected in that line.
  local section_cur = H.new_struct('section', { id = config.default_section_id, line_begin = block_begin })

  for i, annotation_line in ipairs(block_raw.annotation) do
    local id = block_raw.section_id[i]
    if id ~= '' then
      -- Finish current section
      if #section_cur > 0 then
        section_cur.info.line_end = block_begin + i - 2
        block:insert(section_cur)
      end

      -- Start new section
      section_cur = H.new_struct('section', { id = id, line_begin = block_begin + i - 1 })
    end

    section_cur:insert(annotation_line)
  end

  if #section_cur > 0 then
    section_cur.info.line_end = block_begin + #block_raw.annotation - 1
    block:insert(section_cur)
  end

  return block
end

-- Hooks ----------------------------------------------------------------------
function H.apply_hooks(doc, hooks)
  for _, file in ipairs(doc) do
    for _, block in ipairs(file) do
      hooks.block_pre(block)

      for _, section in ipairs(block) do
        hooks.section_pre(section)

        local hook = hooks.sections[section.info.id]
        if hook ~= nil then
          hook(section)
        end

        hooks.section_post(section)
      end

      hooks.block_post(block)
    end

    hooks.file(file)
  end

  hooks.doc(doc)
end

function H.register_alias(s)
  if #s == 0 then
    return
  end

  -- Remove first word (and its surrounding whitespace) while capturing it
  local alias_name
  s[1] = s[1]:gsub('%s*(%S+)%s*', function(x)
    alias_name = x
    return ''
  end, 1)
  if alias_name == nil then
    return
  end

  MiniDoc.current.aliases = MiniDoc.current.aliases or {}
  MiniDoc.current.aliases[alias_name] = table.concat(s, '\n')
end

function H.replace_aliases(s)
  if MiniDoc.current.aliases == nil then
    return
  end

  for i, _ in ipairs(s) do
    for alias_name, alias_desc in pairs(MiniDoc.current.aliases) do
      s[i] = s[i]:gsub(vim.pesc(alias_name), vim.pesc(alias_desc))
    end
  end
end

function H.add_section_heading(s, heading)
  if #s == 0 or s.type ~= 'section' then
    return
  end

  -- Add heading
  s:insert(1, ('%s~'):format(heading))
end

function H.enclose_first_word(s, pattern)
  if #s == 0 or s.type ~= 'section' then
    return
  end

  s[1] = s[1]:gsub('(%S*)', pattern, 1)
end

-- Infer data from afterlines -------------------------------------------------
function H.infer_header(b)
  local has_signature = b:has_descendant(function(x)
    return type(x) == 'table' and x.type == 'section' and x.info.id == '@signature'
  end)
  local has_tag = b:has_descendant(function(x)
    return type(x) == 'table' and x.type == 'section' and x.info.id == '@tag'
  end)

  if has_signature and has_tag then
    return
  end

  local l_all = table.concat(b.info.afterlines, ' ')
  local tag, signature

  -- Try function definition
  local fun_capture = H.capture_afterlines_patterns(l_all, 'function_definition')
  if #fun_capture > 0 then
    tag = tag or ('%s()'):format(fun_capture[1])
    signature = signature or ('%s%s'):format(fun_capture[1], fun_capture[2])
  end

  -- Try general assignment
  local assign_capture = H.capture_afterlines_patterns(l_all, 'general_assignment')
  if #assign_capture > 0 then
    tag = tag or assign_capture[1]
    signature = signature or assign_capture[1]
  end

  if tag ~= nil then
    -- First insert signature (so that it will appear after tag section)
    if not has_signature then
      b:insert(1, H.as_struct({ signature }, 'section', { id = '@signature' }))
    end

    -- Insert tag
    if not has_tag then
      b:insert(1, H.as_struct({ tag }, 'section', { id = '@tag' }))
    end
  end
end

function H.capture_afterlines_patterns(l, patterns_id)
  local matches = {}
  for _, pattern in ipairs(H.afterlines_patterns[patterns_id]) do
    if #matches == 0 then
      matches = { l:match(pattern) }
    end
  end
  return matches
end

function H.format_signature(line)
  -- Try capture function signature
  local name, args = line:match('(%S-)(%b())')
  -- Otherwise pick first word
  name = name or line:match('(%S*)')

  if not name then
    return ''
  end

  -- Tidy arguments
  if args and args ~= '()' then
    local arg_parts = vim.split(args:sub(2, -2), ',')
    local arg_list = {}
    for _, a in ipairs(arg_parts) do
      -- Enclose argument in `{}` while controlling whitespace
      table.insert(arg_list, ('{%s}'):format(vim.trim(a)))
    end
    args = ('(%s)'):format(table.concat(arg_list, ', '))
  end

  return ('`%s`%s'):format(name, args or '')
end

-- Work with structures -------------------------------------------------------
-- Constructor
function H.new_struct(struct_type, info)
  local output = {
    info = info or {},
    type = struct_type,
  }

  output.insert = function(self, index, child)
    if child == nil then
      child, index = index, #self + 1
    end

    if type(child) == 'table' then
      child.parent = self
      child.parent_index = index
    end

    table.insert(self, index, child)

    H.sync_parent_index(self)
  end

  output.remove = function(self, index)
    index = index or #self
    table.remove(self, index)

    H.sync_parent_index(self)
  end

  output.has_descendant = function(self, predicate)
    local bool_res, descendant = false, nil
    H.apply_recursively(function(x)
      if not bool_res and predicate(x) then
        bool_res = true
        descendant = x
      end
    end, self)
    return bool_res, descendant
  end

  output.has_lines = function(self)
    return self:has_descendant(function(x)
      return type(x) == 'string'
    end)
  end

  output.clear_lines = function(self)
    for i, x in ipairs(self) do
      if type(x) == 'string' then
        self[i] = nil
      else
        x:clear_lines()
      end
    end
  end

  return output
end

function H.sync_parent_index(x)
  for i, _ in ipairs(x) do
    if type(x[i]) == 'table' then
      x[i].parent_index = i
    end
  end
  return x
end

-- Converter (this ensures that children have proper parent-related data)
function H.as_struct(array, struct_type, info)
  local res = H.new_struct(struct_type, info)
  for _, x in ipairs(array) do
    res:insert(x)
  end
  return res
end

-- Utilities ------------------------------------------------------------------
function H.apply_recursively(f, x)
  f(x)

  if type(x) == 'table' then
    for _, t in ipairs(x) do
      H.apply_recursively(f, t)
    end
  end
end

function H.collect_strings(x)
  local res = {}
  H.apply_recursively(function(y)
    if type(y) == 'string' then
      -- Allow `\n` in strings
      table.insert(res, vim.split(y, '\n'))
    end
  end, x)
  -- Flatten to only have strings and not table of strings (from `vim.split`)
  return vim.tbl_flatten(res)
end

function H.file_read(path)
  local file = assert(io.open(path))
  local contents = file:read('*all')
  file:close()

  return vim.split(contents, '\n')
end

function H.file_write(path, lines)
  -- Ensure target directory exists
  local dir = vim.fn.fnamemodify(path, ':h')
  vim.fn.mkdir(dir, 'p')

  -- Write to file
  vim.fn.writefile(lines, path, 'b')
end

function H.ensure_indent(s, n_indent_target)
  local lines = vim.split(s, '\n')
  local n_indent, n_indent_cur = math.huge, math.huge

  -- Find number of characters in indent
  for _, l in ipairs(lines) do
    -- Update lines indent: minimum of all indents except empty lines
    if n_indent > 0 then
      _, n_indent_cur = l:find('^%s*')
      -- Condition "current n-indent equals line length" detects empty line
      if (n_indent_cur < n_indent) and (n_indent_cur < l:len()) then
        n_indent = n_indent_cur
      end
    end
  end

  -- Ensure indent
  local indent = string.rep(' ', n_indent_target)
  for i, l in ipairs(lines) do
    if l ~= '' then
      lines[i] = indent .. l:sub(n_indent + 1)
    end
  end

  return table.concat(lines, '\n')
end

function H.align_text(s, width, direction)
  if type(s) ~= 'string' then
    return
  end
  s = vim.trim(s)
  width = width or 78
  direction = direction or 'left'

  -- Don't do anything if aligning left or line is a whitespace
  if direction == 'left' or s:find('^%s*$') then
    return s
  end

  -- Ignore concealed characters (usually "invisible" in 'help' filetype)
  local _, n_concealed_chars = s:gsub('([*|`])', '%1')
  local n_left = math.max(0, 78 - vim.fn.strdisplaywidth(s) + n_concealed_chars)
  if direction == 'center' then
    n_left = math.floor(0.5 * n_left)
  end

  return (' '):rep(n_left) .. s
end

function H.notify(msg)
  vim.notify(('(mini.doc) %s'):format(msg))
end

return MiniDoc
