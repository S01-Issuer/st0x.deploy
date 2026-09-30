{
  description = "Flake for development workflows.";

  inputs = {
    rainix.url = "github:rainlanguage/rainix";
    flake-utils.url = "github:numtide/flake-utils";
    rain.url = "github:rainlanguage/rain.cli";
    # rain.cli pulls its own rainix; make it follow ours so the lock has a
    # single rainix (and one rust toolchain / nixpkgs) instead of two revs.
    rain.inputs.rainix.follows = "rainix";
  };

  outputs =
    {
      flake-utils,
      rainix,
      rain,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = rainix.pkgs.${system};
      in
      rec {
        packages = {
          # `script/build-meta.sh` runs `rain meta build` out of this.
          rain-cli = rain.defaultPackage.${system};
        }
        // rainix.packages.${system};

        devShells = rainix.devShells.${system} // {
          default = pkgs.mkShell {
            inputsFrom = [ rainix.devShells.${system}.default ];
            packages = [
              packages.rain-cli
              pkgs.gh
            ];
          };
        };
      }
    );

}
