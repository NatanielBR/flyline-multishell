Output demo_flycomp_zsh.gif
Output demo_flycomp_zsh.svg

Require claude
Source demo_settings.tape
Set Shell /bin/zsh
Set Width 1450
Set Height 650

# Wait for zle-line-init to launch flyline-standalone.
Hide
Sleep 2000ms
Type@40ms ` clear`
Enter
Sleep 800ms
Show

Hide
Type@40ms ` clear && echo "zsh/fish: Esc dismisses generic file completions, then Tab offers flycomp:" && echo ""`
Enter
Sleep 500ms
Show

# Leave the caption on screen long enough to read.
Sleep 5000ms
Type "claude "
Sleep 1200ms
Escape
Sleep 600ms
Tab
Sleep 3000ms
Enter
Sleep 4000ms
