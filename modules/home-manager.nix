{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.codex-nix;
  inherit (lib)
    mkOption
    mkEnableOption
    mkIf
    mkMerge
    types
    optionalAttrs
    ;

  tomlFormat = pkgs.formats.toml { };

  # Combine all plugin derivations into a single tree.
  combined = pkgs.buildEnv {
    name = "codex-nix-plugins";
    paths = cfg.plugins;
  };

  # Collect hooks from every plugin's _codex.hooks passthru and group them
  # by event then matcher.
  collectHooks =
    plugins:
    let
      all = lib.concatMap (p: p._codex.hooks or [ ]) plugins;
      byEvent = lib.groupBy (h: h.event) all;
    in
    lib.mapAttrs (
      _event: hs:
      let
        byMatcher = lib.groupBy (h: h.matcher) hs;
      in
      lib.mapAttrsToList (matcher: items: {
        inherit matcher;
        hooks = map (h: h.hook) items;
      }) byMatcher
    ) byEvent;

  collectedHooks = collectHooks cfg.plugins;

  # Collect MCP servers from all plugins.
  collectMcpServers =
    plugins:
    lib.foldl' (acc: p: acc // (p._codex.mcpServers or { })) { } plugins;

  collectedMcpServers = collectMcpServers cfg.plugins;

  # Collect agent derivations from all plugins.
  collectAgents =
    plugins:
    lib.concatMap (p: p._codex.agents or [ ]) plugins;

  collectedAgents = collectAgents cfg.plugins;

  # Merge settings with collected MCP servers.
  mergedSettings = lib.recursiveUpdate cfg.settings (
    optionalAttrs (collectedMcpServers != { }) { mcp_servers = collectedMcpServers; }
  );

  # Generate config TOML file.
  configToml = tomlFormat.generate "codex-nix-config.toml" mergedSettings;

  # Generate hooks JSON file.
  hooksJson = pkgs.writeText "codex-nix-hooks.json" (builtins.toJSON collectedHooks);

in
{
  options.programs.codex-nix = {
    enable = mkEnableOption "codex managed declaratively by codex-nix";

    package = mkOption {
      type = types.package;
      default = pkgs.codex or pkgs.codex-cli;
      defaultText = lib.literalExpression "pkgs.codex";
      description = "The codex package to install.";
    };

    plugins = mkOption {
      type = types.listOf types.package;
      default = [ ];
      description = ''
        List of plugin derivations produced by `codex-nix.lib.mkPlugin`.
        Their contents (skills/, agents/) are merged via
        `pkgs.buildEnv` and symlinked into `~/.codex/`.
      '';
    };

    settings = mkOption {
      type = types.attrs;
      default = { };
      description = ''
        Contents of `~/.codex/config.toml`. MCP servers collected from
        `plugins` are merged on top of this attrset.
      '';
    };

    extraPackages = mkOption {
      type = types.listOf types.package;
      default = [ ];
      description = "Extra packages to install alongside codex.";
    };

    agentsMd = mkOption {
      type = types.str;
      default = "";
      description = ''
        Contents of `~/.codex/AGENTS.md`. Written only if non-empty.
      '';
    };
  };

  config = mkIf cfg.enable {
    home.packages = [ cfg.package ] ++ cfg.extraPackages;

    home.activation.copyCodexNixConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      codexDir=${config.home.homeDirectory}/.codex
      configFile="$codexDir/config.toml"
      hooksFile="$codexDir/hooks.json"
      generatedConfig=${configToml}
      generatedHooks=${hooksJson}

      run mkdir -p "$codexDir"
      run mkdir -p "$codexDir/agents"

      # ── config.toml ──
      if [[ -L "$configFile" ]]; then
        run unlink "$configFile"
      fi

      if [[ -f "$configFile" ]]; then
        tmpFile=$(mktemp)
        ${lib.getExe pkgs.yj} -tj < "$configFile" \
          | ${lib.getExe pkgs.jq} -s '.[0] * .[1]' - <(${lib.getExe pkgs.yj} -tj < "$generatedConfig") \
          | ${lib.getExe pkgs.yj} -jt > "$tmpFile"
        run mv "$tmpFile" "$configFile"
      else
        run cp "$generatedConfig" "$configFile"
      fi
      run chmod 600 "$configFile"

      # ── hooks.json ──
      if [[ -L "$hooksFile" ]]; then
        run unlink "$hooksFile"
      fi

      if [[ -f "$hooksFile" ]]; then
        tmpFile=$(mktemp)
        ${lib.getExe pkgs.jq} -s '.[0] * .[1]' "$hooksFile" "$generatedHooks" > "$tmpFile"
        run mv "$tmpFile" "$hooksFile"
      else
        run cp "$generatedHooks" "$hooksFile"
      fi
      run chmod 600 "$hooksFile"

      # ── agent TOML files ──
      ${lib.concatMapStringsSep "\n" (agent: ''
        if [[ -d "${agent}/agents" ]]; then
          for f in ${agent}/agents/*.toml; do
            run cp "$f" "$codexDir/agents/"
          done
        fi
      '') collectedAgents}

      # ── AGENTS.md ──
      ${lib.optionalString (cfg.agentsMd != "") ''
        agentsMdFile="$codexDir/AGENTS.md"
        generatedAgentsMd=${pkgs.writeText "codex-nix-agents-md" cfg.agentsMd}
        run cp "$generatedAgentsMd" "$agentsMdFile"
        run chmod 600 "$agentsMdFile"
      ''}
    '';

    home.file = mkMerge [
      (mkIf (builtins.pathExists "${combined}/skills") {
        ".agents/skills".source = "${combined}/skills";
      })
    ];
  };
}
