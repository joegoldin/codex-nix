# codex-nix

Declarative OpenAI Codex configuration for Nix: plugins, skills, agents,
hooks, and MCP servers managed via home-manager.

## Home-manager module

```nix
programs.codex-nix = {
  enable        = true;                # install codex + manage config
  package       = pkgs.codex;          # default
  plugins       = [ ... ];             # list of mkPlugin derivations
  settings      = { ... };             # ~/.codex/config.toml contents
  mcpServers    = { ... };             # [mcp_servers.*] tables (see below)
  agentsMd      = "...";               # ~/.codex/AGENTS.md (written if non-empty)
  extraPackages = [ ... ];             # extra packages installed alongside
};
```

`config.toml` is reconciled on activation via a `yj`/`jq` deep-merge, so
user-managed keys survive rebuilds; generated keys win on conflict.

### MCP servers

`programs.codex-nix.mcpServers` merges into the `[mcp_servers.*]` tables of
`~/.codex/config.toml` alongside plugin-provided servers (the user option wins
on a name conflict). Remote servers use `url` + `bearer_token_env_var` (never a
raw `bearer_token` — Codex rejects it).

```nix
programs.codex-nix.mcpServers = {
  context7 = { command = "npx"; args = [ "-y" "@upstash/context7-mcp" ]; };
  figma = { url = "https://mcp.figma.com/mcp"; bearer_token_env_var = "FIGMA_OAUTH_TOKEN"; };
};
```

## Library — `codexLib`

| Function | Returns | Notes |
|---|---|---|
| `mkSkill { name; description; allowed-tools? []; extraFiles? []; } body` | derivation | `$out/skills/<name>/SKILL.md` |
| `mkAgent { name; description; developer_instructions; ... }` | derivation | `$out/agents/<name>.toml` |
| `mkHook { event; matcher? ""; name; command; timeout?; description?; }` | attrset | Collected into `~/.codex/hooks.json` |
| `mkPlugin { name; description?; skills?; hooks?; mcpServers?; agents?; }` | derivation | `buildEnv` with hooks/MCP/agents as `_codex` passthru |
| `mkCodex { package; extraArgs? []; env? {}; }` | `writeShellScriptBin` | Optional `codex` wrapper |

## License

MIT.
