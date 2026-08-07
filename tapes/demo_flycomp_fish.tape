Output demo_flycomp_fish.gif
Output demo_flycomp_fish.svg

Require claude
Source demo_settings.tape
Set Shell /usr/bin/fish
Set Width 1450
Set Height 650

# Wait for fish_prompt to launch flyline-standalone.
Hide
Sleep 2500ms
Type@40ms ` clear`
Enter
Sleep 1200ms
Show

Hide
Type@40ms ` clear && echo "zsh/fish: Esc dismisses generic file completions, then Tab offers flycomp:" && echo ""`
Enter
Sleep 1000ms
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
Sleep 8000ms
