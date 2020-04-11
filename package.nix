{ stdenv
, parted
, pkgconfig
, dbus
, gettext
, fetchFromGitHub
, lib
, callPackage
, darwin
, llvmPackages
, libxml2
, glib
, libunistring
, makeSetupHook
, writeShellScript
}:

let
  gitignoreSrc = fetchFromGitHub {
    owner = "hercules-ci";
    repo = "gitignore";
    # put the latest commit sha of gitignore Nix library here:
    rev = "2ced4519f865341adcb143c5d668f955a2cb997f";
    # use what nix suggests in the mismatch message here:
    sha256 = "sha256-X8xHVRr8N6SzI8Ju87V+A75r3ZwF+CEuXcx5nfZbhTk=";
  };
  inherit (import gitignoreSrc { inherit lib; }) gitignoreSource;

  rust = callPackage ./rust.nix {
    inherit (darwin.apple_sdk.frameworks) CoreFoundation Security;
  };
  libcroco = callPackage ./libcroco.nix { };

  ccForBuild="${stdenv.cc}/bin/${stdenv.cc.targetPrefix}cc";
  cxxForBuild="${stdenv.cc}/bin/${stdenv.cc.targetPrefix}c++";
  ccForHost="${stdenv.cc}/bin/${stdenv.cc.targetPrefix}cc";
  cxxForHost="${stdenv.cc}/bin/${stdenv.cc.targetPrefix}c++";
  releaseDir = "target/${rustTarget}/release";
  rustTarget = rust.toRustTarget stdenv.hostPlatform;
in
with rust; (makeRustPlatform packages.stable).buildRustPackage rec {
  pname = "distinst";
  version = "0.0.1";

  src = gitignoreSource ./.;

  cargoSha256 = "sha256-f6g8gZCmKyTIhd+tnUf0t29PSRDGhSMWqZTGlwp/Hbk=";

  nativeBuildInputs = [
    pkgconfig
    gettext
    (makeSetupHook {
      name = "rust-fake";
      deps = [];
    } (writeShellScript "rust-fake.sh" ''
      rustFake() {
        ${preBuild}
      }

      shellHook=rustFake
    ''))
  ];

  buildInputs = [
    parted
    dbus
    llvmPackages.clang
    llvmPackages.libclang

    # shadow-deps of gettext rust
    libxml2
    libcroco
    glib
    libunistring
  ];

  preBuild = ''
    export LIBCLANG_PATH=${llvmPackages.libclang}/lib
    export CFLAGS="$CFLAGS -Wno-error=format-security -Wno-error"
  '';

  buildPhase = with builtins; ''
    runHook preBuild

    for m in cli ffi; do
      (
      set -x
      env \
        "CC_${rust.toRustTarget stdenv.buildPlatform}"="${ccForBuild}" \
        "CXX_${rust.toRustTarget stdenv.buildPlatform}"="${cxxForBuild}" \
        "CC_${rust.toRustTarget stdenv.hostPlatform}"="${ccForHost}" \
        "CXX_${rust.toRustTarget stdenv.hostPlatform}"="${cxxForHost}" \
        cargo build \
          --release \
          --target ${rustTarget} \
          --frozen \
          --manifest-path $m/Cargo.toml
      )
    done

    # rename the output dir to a architecture independent one
    mapfile -t targets < <(find "$NIX_BUILD_TOP" -type d | grep '${releaseDir}$')
    for target in "''${targets[@]}"; do
      rm -rf "$target/../../release"
      ln -srf "$target" "$target/../../"
    done

    runHook postBuild
  '';

  doCheck = false;

  installPhase = ''
    make VENDORED=1 DEBUG=0 RELEASE=release prefix=$out install
  '';

  meta = with stdenv.lib; {
    description = "An installer backend";
    homepage = "https://github.com/pop-os/distinst";
    license = licenses.lgpl3;
    maintainers = with maintainers; [ mkg20001 ];
    platforms = [ "x86_64-linux" ];
  };
}