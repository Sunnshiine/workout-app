# TASK — MCP availability probe (spike, issue #472, bare variant)

You are running inside a CI spike. Your ONLY job is to report which MCP tools
this session has. Do not build anything, do not boot a simulator, do not
modify or commit any files tracked by git.

Using the Bash tool, write a file `spike-result-bare.json` in the current
directory with exactly this shape:

```json
{
  "variant": "bare",
  "xcodebuildmcpLoaded": false,
  "context7Loaded": false,
  "mcpToolSample": []
}
```

- `xcodebuildmcpLoaded`: true if and only if your available tools include any
  whose name starts with `mcp__XcodeBuildMCP__`.
- `context7Loaded`: true if and only if any tool name starts with
  `mcp__context7__`.
- `mcpToolSample`: up to 10 of the `mcp__`-prefixed tool names you actually
  have (empty array if none).

Answer from your actual tool list, not from expectations. Then stop.
