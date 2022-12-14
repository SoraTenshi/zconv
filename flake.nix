{
  description = "Convert input to little-endian encoded binary literals";
  
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };
  
  outputs = inputs@{ self, ...}: inputs.flake-utils.lib.eachDefaultSystem (system:
    let
      pkgs = inputs.nixpkgs.legacyPackages.${system};
    in 
      {
      devShells.default = pkgs.mkShell {
        nativeBuildInputs = with pkgs; [
          zig
        ];
      };
      devShell = self.devShells.${system}.default;
      
      packages.default = pkgs.stdenv.mkDerivation {
        pname = "zconv";
        version = "0.0.1";
        src = self;
        nativeBuildInputs = with pkgs; [
          zig
        ];
        buildPhase = ''
          ${pkgs.zig} build -Drelease-safe=true
        '';
        installPhase = ''
          cp ./zig-out/bin/zconv $out
        '';
      };
      
      apps.${system}.default = {
        type = "app";
        program = "${self}/zig-out/bin/zconv";
      };
    }
  );
}
