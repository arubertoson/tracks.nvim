# Development guidelines

- Treat semantic points, file visits, active files, and buffer retention as one
  navigation lifecycle while keeping their state ownership explicit.
- Preserve meaning rather than arbitrary coordinates where semantic ownership exists.
- Keep persistent paths separate from volatile buffers, windows, timers, and extmarks.
- Validate Neovim, filesystem, Git, Treesitter, and asynchronous data at boundaries;
  trust established internal contracts.
- Fail visibly on invariant violations and guard genuine asynchronous races.
- Test observable navigation and lifecycle outcomes through real Neovim APIs, files,
  parsers, and Git metadata.
- Format Lua with StyLua and run `just check` before committing.
