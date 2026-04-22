{
  description = "Declarative OpenAI Codex configuration for Nix";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems =
        f:
        nixpkgs.lib.genAttrs systems (
          system:
          f {
            pkgs = import nixpkgs { inherit system; };
            lib = nixpkgs.lib;
            inherit system;
          }
        );
    in
    {
      lib = forAllSystems (
        { pkgs, lib, ... }: import ./lib { inherit pkgs lib; }
      );

      homeManagerModules.default = import ./modules/home-manager.nix;
      homeManagerModules.codex-nix = import ./modules/home-manager.nix;

      packages = forAllSystems (
        { pkgs, lib, ... }:
        {
          example-plugin = import ./examples/example-plugin.nix { inherit pkgs lib; };
        }
      );

      checks = forAllSystems (
        { pkgs, lib, ... }:
        let
          l = import ./lib { inherit pkgs lib; };
        in
        {
          eval-skill = l.mkSkill {
            name = "smoke";
            description = "smoke test";
          } "smoke body";

          eval-hook =
            let
              hook = l.mkHook {
                event = "on_message";
                name = "smoke";
                command = "/bin/true";
              };
            in
            pkgs.runCommand "check-hook" { } ''
              test "${hook.event}" = "on_message"
              test "${hook.hook.name}" = "smoke"
              touch $out
            '';

          eval-agent = l.mkAgent {
            name = "smoke";
            description = "smoke test agent";
            developer_instructions = "You are a smoke test agent.";
          };

          eval-plugin = import ./examples/example-plugin.nix { inherit pkgs lib; };
        }
      );
    };
}
