# tracks.nvim

Navigation should remember *where you were working*, not merely a stack of line
numbers.

`tracks.nvim` keeps four related trails through an editing session:

- meaningful cursor landings inside a file;
- chronological visits between files;
- a tiny branch-scoped set of files you are actively working on;
- a bounded MRU cache that keeps those active files loaded.

Together they make moving backward, moving forward, switching tasks, and returning to
an earlier thought feel like one workflow instead of four unrelated plugins.

## Why it exists

Neovim already has jumps, buffers, marks, and alternate files. They are powerful, but
they answer different questions and often preserve coordinates rather than intent.

`tracks.nvim` is opinionated about the questions that matter during ordinary coding:

- **Where was I just reasoning in this file?** Semantic point history records settled
  cursor landings inside functions, methods, classes, and substantial blocks.
- **Which file did I come from?** File history behaves like browser back/forward and
  restores the saved view even after a buffer was unloaded.
- **Which files belong to this task?** Active files are explicit slots persisted per
  project and Git branch.
- **What can Neovim forget?** The buffer cache unloads cold files while protecting
  visible, modified, and active files.

The result is less buffer housekeeping and fewer context-free jumps.

## Status

This is personal software published in the open because inspectable tools are better
tools. It is built around how I navigate Neovim and may change when that workflow
changes. It has no compatibility promise, public roadmap, support commitment, or
contribution process.

The repository is source-available, not open source. No license to copy, modify, or
redistribute the code is granted. See [LICENSE](LICENSE).

## Requirements

- Neovim 0.13 or newer;
- Treesitter parsers for semantic point history;
- `nvim-treesitter-textobjects` queries containing captures such as
  `function.outer`, `method.outer`, `class.outer`, and `block.outer`;
- a Git worktree for branch-scoped active-file persistence. Non-Git files fall back
  to the current working-directory scope.

## Installation

Using Neovim's built-in package manager:

```lua
vim.pack.add({
    { src = "https://github.com/nvim-treesitter/nvim-treesitter" },
    { src = "https://github.com/nvim-treesitter/nvim-treesitter-textobjects" },
    { src = "https://github.com/arubertoson/tracks.nvim" },
})

require("tracks").setup()
```

The plugin owns tracking and lifecycle autocmds but no global mappings.

## Suggested mappings

```lua
local tracks = require("tracks")

-- Semantic landings within the current file.
vim.keymap.set("n", "<C-o>", tracks.point_jump.prev)
vim.keymap.set("n", "<C-i>", tracks.point_jump.next)

-- Chronological file visits.
vim.keymap.set("n", "<M-o>", tracks.file_jump.prev)
vim.keymap.set("n", "<M-i>", tracks.file_jump.next)
vim.keymap.set("n", "<M-Tab>", tracks.file_jump.toggle)

-- A small explicit working set.
vim.keymap.set("n", "<leader>a", tracks.active.add)
vim.keymap.set("n", "<leader>x", tracks.active.remove)
vim.keymap.set("n", "<leader>1", function() tracks.active.select(1) end)
vim.keymap.set("n", "<leader>2", function() tracks.active.select(2) end)
vim.keymap.set("n", "<leader>3", function() tracks.active.select(3) end)
```

## How the tracks behave

### Semantic point history

Cursor movement is debounced so ordinary movement does not flood history. A landing
belongs to the smallest configured Treesitter textobject around it. Revisiting that
semantic area updates its return position and moves it to the recent end of history.
Extmarks keep landings attached through edits; deleting the owning syntax node removes
the stale landing.

Large semantic areas are divided by locality so a long function does not collapse
into one useless point.

### File visit history

Normal file-buffer transitions create a chronological trail. Navigation performed by
the trail itself is invisible to tracking, so moving backward does not immediately
create a new forward branch. Each visit stores the window view and can reopen an
unloaded file from disk.

### Active files

Active files are ordered slots, not a general bookmark database. They are persisted
as project-relative paths under the project root and current Git branch. Switching
branches therefore switches working sets. Missing files are removed when selected.

The plugin emits `User TracksActiveUpdated` after the active set changes.

### Buffer cache

Loaded normal-file buffers are ordered by recent use. Pruning is a soft limit:
visible, modified, active, or explicitly protected buffers stay loaded even above the
configured maximum. Set `vim.b[buf].__bufdel_protected = true` to protect an additional
buffer.

Set `vim.b[buf].tracks_exclude = true` to exclude a normal file buffer from all
tracking.

## Configuration

```lua
require("tracks").setup({
    point_jump = {
        debounce_ms = 250,
        max_history = 10,
        min_block_lines = 12,
        max_semantic_area_lines = 30,
        locality_lines = 20,
        max_ts_field_len = 32,
        exclude_filetypes = {},
    },
    file_jump = {
        max_history = 100,
        exclude_filetypes = {},
    },
    active = {
        max_files = 3,
        storage_path = vim.fs.joinpath(vim.fn.stdpath("state"), "tracks-active.json"),
        before_select = nil,
    },
    buffer_cache = {
        max_buffers = 8,
    },
})
```

`capture_priority` can override semantic textobject precedence. The defaults prefer
blocks, then functions/methods, then classes.

`setup()` initializes the plugin once per Neovim process. A second call is rejected;
restart Neovim to apply configuration changes.

## Non-goals

- replacing every behavior of Neovim's jumplist;
- a general bookmark or project-management system;
- a bufferline or buffer picker;
- session restoration;
- non-Git project-root heuristics;
- preserving arbitrary cursor coordinates that have no semantic owner.

## Development

With Neovim, Mise, and Just installed:

```sh
just setup
just check
```

`just check` verifies formatting and runs the tests in headless Neovim.
