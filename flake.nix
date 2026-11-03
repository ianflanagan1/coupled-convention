{
  description = "coupled-tags-lint: check the COUPLED:<key>: tags in a repository";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs: rec {
        # The tools the script calls are pinned, so it behaves the same on macOS, Linux and CI.
        coupled-tags-lint = pkgs.writeShellApplication {
          name = "coupled-tags-lint";
          runtimeInputs = [ pkgs.coreutils pkgs.git pkgs.gawk pkgs.gnugrep pkgs.gnused ];
          text = ''
            exec ${pkgs.dash}/bin/dash ${./skills/ianf-coupled-tags/scripts/coupled-tags-lint.sh} "$@"
          '';
        };
        default = coupled-tags-lint;
      });
    };
}
