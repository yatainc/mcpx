{
  lib,
  stdenv,
  moonHome,
  moonDependencies,
  tinyccForMoonbit ? null,
}:

stdenv.mkDerivation {
  name = "mcpx";
  src = ./.;
  MOON_HOME = "${moonHome}";

  # Package builds should produce the native CLI only. The native test suite
  # exercises chmod, daemon, and socket behavior that is covered in CI but is
  # not reliable inside every Nix sandbox.
  doCheck = false;

  buildPhase = ''
    # Use a writable toolchain copy for the registry and Linux tcc shim.
    # Point the copied Moon wrapper at this home instead of the Nix store.
    writable_home=$TMPDIR/moon_home
    cp -rL $MOON_HOME $writable_home
    chmod -R u+w $writable_home
    cat > "$writable_home/bin/moon" <<EOF
    #!${stdenv.shell}
    export MOON_HOME='$writable_home'
    export MOON_TOOLCHAIN_ROOT='$writable_home'
    exec -a "\$0" "$writable_home/bin/.moon-wrapped" "\$@"
    EOF
    chmod +x "$writable_home/bin/moon"

    ${lib.optionalString (stdenv.hostPlatform.isLinux && tinyccForMoonbit != null) ''
      cat > "$writable_home/lib/tcc-mzero.c" <<'EOF'
      const float __mzerosf = -0.0f;
      const double __mzerodf = -0.0;
      EOF

      rm -f "$writable_home/bin/internal/tcc"
      cat > "$writable_home/bin/internal/tcc" <<'EOF'
      #!${stdenv.shell}
      set -e

      self_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
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
              tmp="$(mktemp)"
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
                rm -f "$tmp"
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

      exec ${tinyccForMoonbit.out}/bin/tcc -B${tinyccForMoonbit.lib}/lib/tcc "''${args[@]}"
      EOF
      chmod +x "$writable_home/bin/internal/tcc"
    ''}

    cp -rL ${moonDependencies}/registry "$writable_home/registry"
    cp -rL ${moonDependencies}/.mooncakes .mooncakes
    chmod -R u+w "$writable_home/registry" .mooncakes
    export MOON_HOME=$writable_home
    export MOON_TOOLCHAIN_ROOT=$writable_home
    export HOME=$TMPDIR

    "$MOON_HOME/bin/moon" build \
      --target native \
      --release \
      --frozen \
      --warn-list +73 \
      --deny-warn \
      cli
  '';

  installPhase = ''
    mkdir -p "$out/bin"
    install -Dm755 "_build/native/release/build/cli/cli.exe" "$out/bin/mcpx"
  '';

  meta = {
    description = "Native CLI for MCP servers";
    homepage = "https://github.com/yatainc/mcpx";
    license = lib.licenses.mit;
    mainProgram = "mcpx";
  };
}
