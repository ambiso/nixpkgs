{
  lib,
  buildPackages,
  rustPlatform,
  fetchFromGitHub,
  fetchurl,
  cmake,
  pkg-config,
  protobuf,
  nix-update-script,
  stdenv,
}:

let
  isCross = stdenv.buildPlatform != stdenv.hostPlatform;
  otelArrow = fetchFromGitHub {
    owner = "GreptimeTeam";
    repo = "otel-arrow";
    rev = "5da284414e9b14f678344b51e5292229e4b5f8d2";
    fetchSubmodules = true;
    hash = "sha256-rUf1jE/StIwWPaqiXyzU4rM7fXu4t5VgKNfIaq3M0V0=";
  };
  dashboardAssets = fetchurl {
    url = "https://github.com/GreptimeTeam/dashboard/releases/download/v0.13.6/build.tar.gz";
    hash = "sha256-9S8lURhLgmtBJjAp1W9fGDjX71Hc6rc8xrHUxUhxFsA=";
  };
in
rustPlatform.buildRustPackage (
  finalAttrs:
  {
    pname = "greptimedb";
    version = "1.1.2";

    src = fetchFromGitHub {
      owner = "GreptimeTeam";
      repo = "greptimedb";
      tag = "v${finalAttrs.version}";
      hash = "sha256-K2E5eGNXSGgd62bU8zk/eEhzGgNsvtnQev/bM057V14=";
    };

    cargoHash = "sha256-GRb01BS311wv8YDx5vx0DY+HqUlt9Z6UJF5oEAdZHKI=";

    nativeBuildInputs = [
      cmake
      pkg-config
      protobuf
      rustPlatform.bindgenHook
    ]
    ++ lib.optionals isCross [
      # Some host build dependencies invoke an unprefixed C compiler directly.
      buildPackages.stdenv.cc
    ];

    postPatch = ''
      tar -xzf ${dashboardAssets} -C src/servers/dashboard

      # Rust renamed the unstable std::sync::Exclusive API to SyncView.
      substituteInPlace src/servers/src/postgres/auth_handler.rs \
        --replace-fail "Exclusive" "SyncView"

      # Rust 1.97 needs a higher limit when computing the frontend's layout.
      substituteInPlace src/frontend/src/lib.rs \
        --replace-fail "pub mod error;" $'#![recursion_limit = "256"]\n\npub mod error;'

      # Cargo only vendors the crate subdirectory, but its build script refers to
      # protobuf definitions elsewhere in the otel-arrow repository.
      cp -r ${otelArrow}/proto "$cargoDepsCopy/proto"
    '';

    cargoBuildFlags = [
      "--package=cmd"
      "--bin=greptime"
      "--features=servers/dashboard"
    ];

    # Upstream deliberately uses unstable Rust features and pins a nightly toolchain.
    env.RUSTC_BOOTSTRAP = 1;

    # The workspace tests include integration tests that require external services.
    doCheck = false;

    passthru.updateScript = nix-update-script { };

    meta = {
      description = "Open-source, cloud-native, distributed time-series database";
      homepage = "https://github.com/GreptimeTeam/greptimedb";
      changelog = "https://github.com/GreptimeTeam/greptimedb/releases/tag/v${finalAttrs.version}";
      license = lib.licenses.asl20;
      maintainers = with lib.maintainers; [ ambiso ];
      mainProgram = "greptime";
    };
  }
  // lib.optionalAttrs isCross {
    preBuild =
      let
        buildTarget = lib.replaceString "-" "_" stdenv.buildPlatform.rust.rustcTarget;
      in
      ''
        # aws-lc-sys is also a host build dependency. Ensure its C probes use
        # the build-platform compiler instead of the cross compiler.
        export CC_${buildTarget}=${buildPackages.stdenv.cc}/bin/cc
        export CXX_${buildTarget}=${buildPackages.stdenv.cc}/bin/c++
      '';
  }
)
