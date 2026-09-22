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

# Record the deterministic terminal demo to docs/demo.gif.
demo:
    @command -v vhs >/dev/null || { echo "error: VHS is required; run 'just tools-install'" >&2; exit 1; }
    @command -v ttyd >/dev/null || { echo "error: ttyd is required; run 'just tools-install'" >&2; exit 1; }
    @command -v ffmpeg >/dev/null || { echo "error: ffmpeg is required" >&2; exit 1; }
    @mkdir -p docs
    @rm -f docs/demo.gif
    @vhs scripts/demo/demo.tape
    @test -s docs/demo.gif || { echo "error: VHS completed without creating docs/demo.gif" >&2; exit 1; }

# Publish the generated GIF to the reusable demo-assets GitHub prerelease.
publish-demo: demo
    @command -v gh >/dev/null || { echo "error: GitHub CLI is required" >&2; exit 1; }
    @gh auth status >/dev/null
    @if gh release view demo-assets >/dev/null 2>&1; then gh release upload demo-assets docs/demo.gif --clobber; else gh release create demo-assets docs/demo.gif --target main --title "Demo assets" --notes "Generated README media." --prerelease; fi

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
