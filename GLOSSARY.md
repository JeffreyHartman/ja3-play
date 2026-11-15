# ja3-play

A Claude Code skill that lets an agent play Jagged Alliance 3 through the Lua debugger of the game, for mod playtests or for play. In prose, the product is "the skill".

## Language

**Debug build**:
`JA3Debug.exe`, the game executable that starts the Lua debugger. The retail `JA3.exe` does not start it.
_Avoid_: dev build, debug mode

**Game session**:
One run of the debug build, from launch to stop.
_Avoid_: session (alone), instance

**Block**:
A piece of Lua that the agent sends to the game in one `evaluate` request, which ends with `return <value>`.
_Avoid_: chunk, script
