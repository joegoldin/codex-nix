{
  pkgs,
  lib,
}:
let
  inherit (lib)
    concatStringsSep
    optional
    optionalAttrs
    ;

  # ─── mkSkill ──────────────────────────────────────────────
  # Produces $out/skills/<name>/SKILL.md (+ optional extraFiles).
  mkSkill =
    {
      name,
      description,
      allowed-tools ? [ ],
      extraFiles ? [ ],
    }:
    body:
    let
      fmFields =
        [
          "name: ${name}"
          "description: ${description}"
        ]
        ++ optional (allowed-tools != [ ]) "allowed-tools: ${toString allowed-tools}";
      frontmatter = "---\n" + concatStringsSep "\n" fmFields + "\n---";
      skillMd = pkgs.writeText "codex-skill-${name}-md" (frontmatter + "\n\n" + body);
      copyExtras = concatStringsSep "\n" (
        map (f: "cp -r ${f} $out/skills/${name}/") extraFiles
      );
    in
    pkgs.runCommand "codex-skill-${name}" { } ''
      mkdir -p $out/skills/${name}
      cp ${skillMd} $out/skills/${name}/SKILL.md
      ${copyExtras}
    '';

  # ─── mkHook ───────────────────────────────────────────────
  # Pure attrset (NOT a derivation) describing one hook entry.
  # The home-manager module collects these from each plugin and writes them
  # into ~/.codex/hooks.json.
  mkHook =
    {
      event,
      matcher ? "",
      name,
      command,
      timeout ? null,
      description ? null,
    }:
    {
      inherit event matcher;
      hook =
        {
          type = "command";
          inherit name command;
        }
        // optionalAttrs (timeout != null) { inherit timeout; }
        // optionalAttrs (description != null) { inherit description; };
    };

  # ─── mkAgent ──────────────────────────────────────────────
  # Produces $out/agents/<name>.toml — the "config layer" a role's
  # `[agents.<name>].config_file` points at. Codex discovers custom agent
  # roles via `[agents.<name>]` tables in config.toml (description +
  # config_file), NOT by scanning ~/.codex/agents, so the home-manager module
  # reads the passthru below to emit that table. The TOML written here is the
  # overlay config for the role and must contain only valid top-level config
  # keys — `description` and `nickname_candidates` belong to the [agents.<name>]
  # table and are therefore excluded from the layer and surfaced via passthru.
  mkAgent =
    {
      name,
      description,
      developer_instructions,
      model ? null,
      sandbox_mode ? null,
      mcp_servers ? null,
      nickname_candidates ? null,
      skills_config ? null,
      ...
    }@args:
    let
      tomlFormat = pkgs.formats.toml { };
      payload =
        (removeAttrs args [
          "name"
          "description"
          "nickname_candidates"
        ])
        // {
          inherit developer_instructions;
        }
        // optionalAttrs (model != null) { inherit model; }
        // optionalAttrs (sandbox_mode != null) { inherit sandbox_mode; }
        // optionalAttrs (mcp_servers != null) { inherit mcp_servers; }
        // optionalAttrs (skills_config != null) { inherit skills_config; };
      tomlFile = tomlFormat.generate "codex-agent-${name}.toml" payload;
    in
    pkgs.runCommand "codex-agent-${name}"
      {
        passthru = {
          agentName = name;
          agentDescription = description;
        }
        // optionalAttrs (nickname_candidates != null) { agentNicknames = nickname_candidates; };
      }
      ''
        mkdir -p $out/agents
        cp ${tomlFile} $out/agents/${name}.toml
      '';

  # ─── mkPlugin ─────────────────────────────────────────────
  # Bundles skill and agent derivations into one buildEnv tree.
  # Hooks, mcpServers, and agents ride along as passthru attributes.
  mkPlugin =
    {
      name,
      description ? "",
      skills ? [ ],
      hooks ? [ ],
      mcpServers ? { },
      agents ? [ ],
    }:
    let
      env = pkgs.buildEnv {
        name = "codex-plugin-${name}";
        paths = skills ++ agents;
      };
    in
    env
    // {
      _codex = {
        inherit hooks mcpServers agents;
        pluginName = name;
        pluginDescription = description;
      };
    };

  # ─── mkCodex ─────────────────────────────────────────────
  # Optional wrapper for callers that want extra args / env vars.
  mkCodex =
    {
      package ? null,
      extraArgs ? [ ],
      env ? { },
    }:
    if package == null then
      throw "codex-nix mkCodex: `package` argument is required"
    else
      let
        envExports = concatStringsSep "\n" (
          lib.mapAttrsToList (k: v: ''export ${k}="${toString v}"'') env
        );
        argsStr = concatStringsSep " " extraArgs;
      in
      pkgs.writeShellScriptBin "codex" ''
        ${envExports}
        exec ${package}/bin/codex ${argsStr} "$@"
      '';
in
{
  inherit
    mkSkill
    mkHook
    mkAgent
    mkPlugin
    mkCodex
    ;
}
