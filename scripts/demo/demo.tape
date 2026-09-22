Output docs/demo.gif

Set Shell "bash"
Set FontSize 18
Set Width 1200
Set Height 720
Set TypingSpeed 45ms
Set PlaybackSpeed 1
Set Framerate 30

Type "nvim --clean -u scripts/demo/init.lua scripts/demo/fixtures/app.lua"
Enter
Sleep 2s

# Settle in two functions, then traverse semantic landing history.
Type "11j"
Sleep 1s
Type "12j"
Sleep 1s
Type "K"
Sleep 2s
Type "J"
Sleep 2s

# Pin the current file as active slot 1.
Type "ga"
Sleep 2s

# Visit and pin a second file.
Type ":edit scripts/demo/fixtures/store.lua"
Enter
Sleep 1s
Type "8j"
Sleep 750ms
Type "ga"
Sleep 2s

# A third visit extends browser-like file history.
Type ":edit scripts/demo/fixtures/router.lua"
Enter
Sleep 2s
Type "7j"
Sleep 750ms

# Walk backward; each file reopens at its saved view.
Type "H"
Sleep 2s
Type "H"
Sleep 2s

# Walk forward, then jump directly through the active working set.
Type "L"
Sleep 2s
Type "gs"
Sleep 3s

Type ":qa!"
Enter
Sleep 1s
