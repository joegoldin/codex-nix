{ pkgs, lib }:
let
  l = import ../lib { inherit pkgs lib; };
in
l.mkPlugin {
  name = "example";
  description = "Smoke-test plugin used by codex-nix flake checks.";
  skills = [
    (l.mkSkill {
      name = "demo";
      description = "Demo skill that does nothing.";
    } "Demo body.")
  ];
  agents = [
    (l.mkAgent {
      name = "demo";
      description = "Demo agent";
      developer_instructions = "You are a demo agent for testing.";
    })
  ];
  hooks = [
    (l.mkHook {
      event = "on_message";
      name = "demo";
      command = "/bin/true";
    })
  ];
  mcpServers = {
    demo = {
      command = "/bin/true";
    };
  };
}
