# ja3-play

A Claude Code skill that lets an agent play Jagged Alliance 3 through the Lua debugger of the game, for mod playtests or for play. In prose, the product is "the skill".

## Language

**Debug build**:
`JA3Debug.exe`, the game executable that starts the Lua debugger. The retail `JA3.exe` does not start it.
_Avoid_: dev build, debug mode

**Game session**:
One run of the game, either build, from launch to stop.
_Avoid_: session (alone), instance

**Game log**:
The log file that one game session writes.
_Avoid_: debug log, console

**Block**:
A piece of Lua that the agent sends to the game in one `evaluate` request, which ends with `return <value>`.
_Avoid_: chunk, script

**Test fight**:
A fight that starts from a `TestCombat` preset of the game, with a new game session and no save.
_Avoid_: test combat, skirmish (alone)

**Auto-player**:
Lua that plays the player side of a fight: each merc attacks or moves, and then the turn ends.
_Avoid_: autoplay, bot

**Playtest agent**:
A subagent that runs the skill inline for the game test of other work, and reports PASS or FAIL for each check.
_Avoid_: test agent, game agent

**Mark**:
The text of a `[PROBE]` line that the agent printed, at which a log read starts or stops.
_Avoid_: marker, anchor
