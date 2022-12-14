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
          git
        ];
        configurePhase = ''
          ${pkgs.git} submodule init
          ${pkgs.git} submodule update --recursive
        '';
        buildPhase = ''
          ${pkgs.zig} build -Drelease-safe=true
        '';
      };
      
      apps.${system}.default = {
        type = "app";
        program = "${self}/zig-out/bin/zconv";
      };
    }
  );
}
