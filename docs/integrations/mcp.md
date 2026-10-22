# Clepso MCP

Clepso includes a local, read-only stdio server. Open **Settings → Integrations**, enter a client label such as
`claude-desktop`, review the disclosure, then choose **Allow**. **Copy setup** gives you a JSON configuration using
the signed CLI embedded in your installed app. Add it to your MCP client's documented configuration yourself.
No client configuration is edited automatically. Revoke access in the same Settings section.

The command is `Clepso.app/Contents/Helpers/clepso mcp --client claude-desktop`. It uses your normal Mac user's
`Library/Application Support/Clepso` directory. It never accepts a database, file path or SQL argument.

| Tool | Contents |
| --- | --- |
| `get_limits` | Provider, window, reported used percentage, observation/reset times, provenance, freshness and state |
| `get_reader_health` | Provider/window freshness, source, observation time and whether the app snapshot is current |

Both accept an optional `provider` filter from the advertised enum. Manual entries retain `source: manual`.
Missing values are null, never zero. Overages remain above 100%. A passed reset becomes `resetExpected`, not
“available again.” Reader freshness is recalculated on every call; an app snapshot older than two minutes is marked
old. Demo data is never shared. Open Clepso to refresh a missing snapshot.

This is local sharing, not authentication between mutually untrusted processes under the same Mac account.
The per-client label is a revocable grant/organization mechanism; another process running as you can read the
shared file. The private directory is mode 0700 and files are 0600. Reads reject symlinks, nonregular files,
other owners, permissive modes, oversized files and invalid schemas. MCP receives a typed allowlist projection,
never the database. There are no paths, prompts, replies, model/session identifiers, email addresses or credentials.
Your MCP client can forward the readings to its AI service; review that client's privacy settings before enabling.

There is no listener, HTTP transport, shell tool, settings writer, resource, prompt or sampling capability.
Each request rechecks permission and rereads the snapshot; revocation applies to running clients. Delete data
revokes grants and removes the shared snapshot. Stdio lines are bounded to 64 KiB without unbounded buffering.

Implementation follows the [MCP lifecycle](https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle),
[stdio transport](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports) and
[tool contract](https://modelcontextprotocol.io/specification/2025-11-25/server/tools), version 2025-11-25.
Verified with official TypeScript SDK 1.32.1 without sending any model prompts.

The reproducible client check is committed in `Tests/MCPClient` and runs in hosted CI after the Swift build:
`npm ci --prefix Tests/MCPClient --ignore-scripts && npm --prefix Tests/MCPClient test`.
It uses a temporary HOME and synthetic readings, launches the real CLI, then removes its test files.
