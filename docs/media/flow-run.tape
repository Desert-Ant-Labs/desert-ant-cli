# The podcast-clips flow on the demo episode, in real time. Tools/record-demos runs this.
Output docs/media/flow-run.gif
Output docs/media/flow-run.mp4

Set Shell "bash"
Set FontSize 22
Set Width 1600
Set Height 520
Set Padding 28
Set TypingSpeed 45ms
Set Theme "Builtin Dark"

Hide
Type "cd /Users/Shared/desertant-demo && export PATH=/Users/Shared/desertant-demo/bin:$PATH DESERTANT_NO_UPDATE_CHECK=1 PS1='$ ' && rm -f episode_clear_clip-* && clear"
Enter
Show

Sleep 600ms
Type "time da flow run podcast-clips episode.mp4"
Sleep 400ms
Enter
Wait+Screen@60s /real/
Sleep 3s
