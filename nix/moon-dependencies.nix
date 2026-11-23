{
  lib,
  fetchurl,
  runCommand,
  unzip,
}:

let
  packages = builtins.fromJSON (builtins.readFile ./moon-lock.json);
  installPackage =
    record:
    let
      archive = fetchurl {
        url = "https://download.mooncakes.io/user/${record.name}/${record.version}.zip";
        sha256 = record.checksum;
      };
      modulePath = lib.escapeShellArg record.name;
    in
    ''
      mkdir -p "$out/.mooncakes/$(dirname ${modulePath})"
      mkdir -p "$out/registry/index/user/$(dirname ${modulePath})"
      unzip -q ${archive} -d "$out/.mooncakes/"${modulePath}
      printf '%s\n' ${lib.escapeShellArg (builtins.toJSON record)} >> "$out/registry/index/user/"${modulePath}.index
    '';
in
runCommand "mcpx-moon-dependencies" { nativeBuildInputs = [ unzip ]; } ''
  mkdir -p "$out/.mooncakes" "$out/registry/index/user"
  ${lib.concatMapStringsSep "\n" installPackage packages}
''
