# Browser diagnosis

When a web page under development behaves unexpectedly (no data, blank
sections, nothing responding), check the browser console FIRST — before
reading code:

- `browser action: console_logs`
- Also `browser action: network_get_log`

A single JS syntax error anywhere in a script file will silently prevent
the entire file from loading. The server-rendered HTML shell still appears
in the page, but zero API calls are made and nothing updates. The console
is the fastest way to see whether this happened.

This applies to any web project an agent works on, regardless of framework
or language. The console is always the first diagnostic step.