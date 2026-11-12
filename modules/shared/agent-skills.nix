# Declarative agent skills and the Claude Code settings keys that nix owns.
#
# Returns `{ files; activation; }` for a home-manager user module:
#   home.file = agentSkills.files;
#   home.activation.claudeSettings = agentSkills.activation;
#
# To add a third-party skill: add (or reuse) a rev-pinned flake input in
# flake.nix, then list the skill below. To add one of your own: put it under
# ./config/agent-skills/<name>/ (that directory is on the public-sync denylist)
# and `git add` it, or the flake evaluator cannot see it.
{
  lib,
  pkgs,
  inputs,
}:

let
  fromInput =
    src: prefix: names:
    lib.genAttrs names (name: "${src}/${prefix}/${name}");

  skillSources =
    fromInput inputs.skills-mattpocock "skills/engineering" [
      "codebase-design"
      "domain-modeling"
      "grill-with-docs"
      "improve-codebase-architecture"
      "prototype"
      "research"
      "setup-matt-pocock-skills"
      "to-spec"
      "to-tickets"
      "wayfinder"
    ]
    // fromInput inputs.skills-text-to-cad "skills" [
      "bambu-labs"
      "cad"
      "cad-viewer"
      "dfam-check"
      "dxf"
      "gcode"
      "sdf"
      "sendcutsend"
      "srdf"
      "step-parts"
      "urdf"
    ]
    // fromInput inputs.skills-trailofbits "plugins/ghidra-headless/skills" [ "ghidra-headless" ]
    // fromInput inputs.skills-shader "skills" [ "shader-art-coding" ]
    // ownSkills;

  # Every directory under ./config/agent-skills is one of our own skills. The
  # directory is private (public-sync denylist), so it is discovered rather
  # than named here, and the public mirror still evaluates without it.
  ownDir = ./config/agent-skills;
  ownSkills = lib.optionalAttrs (builtins.pathExists ownDir) (
    lib.mapAttrs (name: _: ownDir + "/${name}") (
      lib.filterAttrs (_: type: type == "directory") (builtins.readDir ownDir)
    )
  );

  # Fail the build with a readable message when a pinned repo no longer has a
  # skill where we expect it (upstreams do restructure).
  checked = lib.mapAttrs (
    name: src:
    if builtins.pathExists "${toString src}/SKILL.md" then
      src
    else
      throw "agent-skills: no SKILL.md for '${name}' at ${toString src}"
  ) skillSources;

  # Keys in ~/.claude/settings.json that this repo owns. Claude Code rewrites
  # that file itself (/model, /plugin, ...), so it cannot be a read-only store
  # symlink; the activation script below merges these keys into it instead.
  # `enabledPlugins`, `extraKnownMarketplaces` and `skillOverrides` are replaced
  # wholesale (so deleting a line here really removes it); `env` is merged.
  # Anything toggled interactively under those keys is reverted on the next
  # activation - change it here instead.
  claudeSettings = {
    env.DISABLE_AUTOUPDATER = "1";
    enabledPlugins = {
      "github@claude-plugins-official" = false;
      "superpowers@claude-plugins-official" = false;
      "claude-md-management@claude-plugins-official" = false;
      "imessage@claude-plugins-official" = false;
      "typescript-lsp@claude-plugins-official" = false;
      "pyright-lsp@claude-plugins-official" = false;
      "code-review@claude-plugins-official" = false;
      "rust-analyzer-lsp@claude-plugins-official" = false;
      "unreal-engine-skills-for-claude-code@claude-plugins-official" = false;
      "comfy-cloud@comfy-skills" = false;
      "universal-modder@universal-modder" = false;
    };
    extraKnownMarketplaces = {
      openai-codex.source = {
        source = "github";
        repo = "openai/codex-plugin-cc";
      };
      claude-code-warp.source = {
        source = "github";
        repo = "warpdotdev/claude-code-warp";
      };
      comfy-skills.source = {
        source = "github";
        repo = "Comfy-Org/comfy-skills";
      };
      universal-modder.source = {
        source = "github";
        repo = "rehan-remade/universal-modder";
      };
    };
    skillOverrides = {
      armbar-local-environment = "off";
      ghidra = "off";
      codebase-design = "off";
      domain-modeling = "off";
      prototype = "off";
      grill-with-docs = "off";
      improve-codebase-architecture = "off";
      to-spec = "off";
      to-tickets = "off";
      wayfinder = "off";
      setup-matt-pocock-skills = "off";
      find-skills = "off";
    };
  };

  managedSettings = pkgs.writeText "claude-settings-managed.json" (builtins.toJSON claudeSettings);
  jq = "${pkgs.jq}/bin/jq";
in
{
  # `force` replaces whatever is already at the target instead of renaming it
  # to `<name>.hm-bak`, which Claude Code would load as a second skill.
  files = lib.mapAttrs' (
    name: src:
    lib.nameValuePair ".claude/skills/${name}" {
      source = src;
      force = true;
    }
  ) checked;

  activation = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    target="$HOME/.claude/settings.json"
    merged="$(mktemp)"
    if [[ -s "$target" ]]; then current="$(cat "$target")"; else current='{}'; fi
    if printf '%s' "$current" | ${jq} --slurpfile managed ${managedSettings} '
        $managed[0] as $m
        | . + ($m | del(.env)) + { env: ((.env // {}) + ($m.env // {})) }
      ' > "$merged"; then
      if ! printf '%s' "$current" | ${jq} -e --slurpfile new "$merged" '. == $new[0]' > /dev/null; then
        run mkdir -p "$HOME/.claude"
        run cp "$merged" "$target"
      fi
    else
      echo "agent-skills: $target is not valid JSON; leaving it untouched" >&2
    fi
    rm -f "$merged"
  '';
}
