# List available commands.
default:
    @just --list

# Install repository-owned tools and run the quality gate.
setup: tools-install check

# Install pinned development tools.
tools-install:
    @mise install

# Run every check expected to pass before committing.
check: version-check format-check test

# Verify the documented minimum Neovim version.
version-check:
    @nvim --headless --clean -u NONE -c "lua assert(vim.fn.has('nvim-0.13') == 1, 'tracks.nvim requires Neovim 0.13 or newer')" +qa

# Format every Lua file.
format:
    @mise exec -- stylua .

# Verify formatting without changing files.
format-check:
    @mise exec -- stylua --check .

# Run the complete test suite.
test:
    @nvim --headless --noplugin -u tests/init.lua -c "lua MiniTest.run()"

# Run one test file.
test-file file:
    @nvim --headless --noplugin -u tests/init.lua -c "lua MiniTest.run_file('{{file}}')"
