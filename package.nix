{
  lib,
  stdenv,
  stdenvNoCC,
  moonHome,
  git,
  cacert,
  python3,
  tinyccForMoonbit ? null,
}:

let
  # Moon resolves versions from moon.mod; Nix pins only the fetched result.
  dependencies = stdenvNoCC.mkDerivation {
    name = "mcpx-moon-dependencies";
    nativeBuildInputs = [ moonHome git python3 ];
    dontUnpack = true;
    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    outputHash = "sha256-u27BOzB7ulnLXUiQpNgKsXHOtyTwP7smat7Lg4BXDbg=";
    SSL_CERT_FILE = "${cacert}/etc/ssl/certs/ca-bundle.crt";
    GIT_SSL_CAINFO = "${cacert}/etc/ssl/certs/ca-bundle.crt";
    buildCommand = ''
      export HOME=$TMPDIR/home
      unset MOON_HOME
      mkdir -p "$HOME" project
      cd project
      cp ${./moon.mod} moon.mod
      touch moon.pkg
      moon update
      moon check --target native
      moon tree --json > graph.json
      mkdir -p "$out"
      cp -rL .mooncakes "$out/.mooncakes"

      # Keep only Moon's resolved registry records, not the global checkout.
      python3 - "$out" <<'PY'
      import json
      import os
      from pathlib import Path
      import sys

      output = Path(sys.argv[1])
      registry = Path(os.environ['HOME']) / '.moon/registry/index'
      graph = json.loads(Path('graph.json').read_text())
      assert graph['status'] == 'success'
      for module in graph['modules']:
          if module['source']['kind'] == 'local':
              continue
          assert module['source']['kind'] == 'registry', module
          name = module['name']
          version = module['version']
          relative = Path('user') / (name + '.index')
          records = [line for line in (registry / relative).read_text().splitlines()
                     if json.loads(line)['version'] == version]
          assert len(records) == 1, (name, version)
          target = output / 'registry/index' / relative
          target.parent.mkdir(parents=True, exist_ok=True)
          target.write_text(records[0] + '\n')
      PY
    '';
  };
in
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

    cp -rL ${dependencies}/registry "$writable_home/registry"
    cp -rL ${dependencies}/.mooncakes .mooncakes
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
