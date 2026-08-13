{
  description = "mcpx - native MCP CLI and portable MCP client runtime";

  nixConfig = {
    extra-substituters = [
      "https://yatainc.github.io/mcpx"
    ];
    extra-trusted-public-keys = [
      "yata-one-mcpx-1:0GPBIC52/PszrTcDzKJIZ7qMmcRvKAWK2WzZYKskgCs="
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    moonbit-overlay.url = "github:moonbit-community/moonbit-overlay/v0.10.4+2cc641edf+75c7e1f";
  };

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      flake = {
        overlays.default = final: prev:
          let
            moonAttrs = inputs.moonbit-overlay.overlays.default final prev;
          in
          {
            mcpx = final.callPackage ./package.nix {
              moonPlatform = final.moonPlatform or moonAttrs.moonPlatform;
              tinyccForMoonbit = if final.stdenv.hostPlatform.isLinux then final.tinycc else null;
            };
          };
      };

      perSystem = { system, ... }:
        let
          pkgs = import inputs.nixpkgs {
            inherit system;
            overlays = [ inputs.moonbit-overlay.overlays.default ];
          };

          mcpx = pkgs.callPackage ./package.nix {
            tinyccForMoonbit = if pkgs.stdenv.hostPlatform.isLinux then pkgs.tinycc else null;
          };

          baseMoonHome = pkgs.moonPlatform.bundleWithRegistry {
            cachedRegistry = pkgs.moonPlatform.buildCachedRegistry {
              moonModJson = ./moon.mod.json;
              registryIndexSrc = ./nix/moon-registry;
            };
          };

          # moonbit-overlay replaces the upstream Linux internal/tcc with
          # nixpkgs tinycc. MoonBit native tests execute tcc in -run mode via
          # rspfiles; tinycc may emit helper symbols such as __mzerodf before
          # libtcc1.a is pulled from its archive. Provide tinycc's lib path and
          # inject a tiny source file defining the missing zero constants.
          moonHome =
            if pkgs.stdenv.isLinux then
              pkgs.runCommand "moonPlatform-moonHome-with-tcc-libs" { } ''
                cp -rL ${baseMoonHome} "$out"
                chmod -R u+w "$out"

                cat > "$out/bin/moon" <<EOF
                #!${pkgs.runtimeShell}
                export MOON_HOME='$out'
                export MOON_TOOLCHAIN_ROOT='$out'
                exec -a "\$0" "$out/bin/.moon-wrapped" "\$@"
                EOF
                chmod +x "$out/bin/moon"

                cat > "$out/lib/tcc-mzero.c" <<'EOF'
                const float __mzerosf = -0.0f;
                const double __mzerodf = -0.0;
                EOF

                rm -f "$out/bin/internal/tcc"
                cat > "$out/bin/internal/tcc" <<'EOF'
                #!${pkgs.runtimeShell}
                set -e

                self_dir="$(CDPATH= cd -- "$(${pkgs.coreutils}/bin/dirname -- "$0")" && pwd)"
                tcc_mzero="$self_dir/../../lib/tcc-mzero.c"
                args=()
                inserted_global=0

                for arg in "$@"; do
                  case "$arg" in
                    -run)
                      if [ "$inserted_global" = 0 ]; then
                        args+=("$tcc_mzero")
                        inserted_global=1
                      fi
                      args+=("$arg")
                      ;;
                    @*)
                      rsp="''${arg#@}"
                      if [ -f "$rsp" ]; then
                        tmp="$(${pkgs.coreutils}/bin/mktemp)"
                        inserted=0
                        printf '%s\n' "$tcc_mzero" >> "$tmp"
                        while IFS= read -r line || [ -n "$line" ]; do
                          if [ "$line" = "-run" ]; then
                            inserted=1
                          fi
                          printf '%s\n' "$line" >> "$tmp"
                        done < "$rsp"

                        if [ "$inserted" = 1 ]; then
                          inserted_global=1
                          args+=("@$tmp")
                        else
                          ${pkgs.coreutils}/bin/rm -f "$tmp"
                          args+=("$arg")
                        fi
                      else
                        args+=("$arg")
                      fi
                      ;;
                    *)
                      args+=("$arg")
                      ;;
                  esac
                done

                exec ${pkgs.tinycc.out}/bin/tcc -B${pkgs.tinycc.lib}/lib/tcc "''${args[@]}"
                EOF
                chmod +x "$out/bin/internal/tcc"
              ''
            else
              baseMoonHome;
        in
        {
          packages = {
            default = mcpx;
            inherit mcpx;
          };

          apps = {
            default = {
              type = "app";
              program = "${mcpx}/bin/mcpx";
            };
            mcpx = {
              type = "app";
              program = "${mcpx}/bin/mcpx";
            };
          };

          devShells.default = pkgs.mkShell {
            packages = [
              moonHome
              pkgs.bash
              pkgs.curl
              pkgs.git
            ] ++ pkgs.lib.optionals pkgs.stdenv.isLinux [
              pkgs.openssl
            ];
            env = {
              MOON_HOME = "${moonHome}";
              MOON_TOOLCHAIN_ROOT = "${moonHome}";
            } // pkgs.lib.optionalAttrs pkgs.stdenv.isLinux {
              LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath [ pkgs.openssl ];
            };
          };
        };
    };
}
