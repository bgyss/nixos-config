# aws-cdk-cli overlay - the `cdk` CLI (AWS CDK Toolkit).
#
# nixpkgs builds aws-cdk-cli from source via yarn and pins an older version
# (2.1100.1 at time of writing). The aws-cdk app in this setup uses the
# aws-cdk-lib 2.260.x construct library, which requires CLI >= 2.1128.1 (older
# CLIs fail `cdk synth` with a cloud-assembly schema mismatch).
#
# The published npm `aws-cdk` package is a fully self-contained, zero-dependency
# bundle (webpacked into lib/, bin/cdk is a plain node script), so we install it
# directly as a prebuilt instead of doing the heavy source build.

final: prev:

let
  inherit (prev) stdenvNoCC fetchurl lib nodejs makeWrapper;
  version = "2.1128.1";
in
{
  aws-cdk-cli = stdenvNoCC.mkDerivation {
    pname = "aws-cdk-cli";
    inherit version;

    src = fetchurl {
      url = "https://registry.npmjs.org/aws-cdk/-/aws-cdk-${version}.tgz";
      sha256 = "sha256-OCHi5OnyE2ILNbkwkaQHza0drEiw1d1Y9IW/qIDispA=";
    };

    sourceRoot = "package";

    nativeBuildInputs = [ makeWrapper ];

    dontBuild = true;
    dontFixup = true;

    installPhase = ''
      runHook preInstall

      mkdir -p "$out/lib/node_modules/aws-cdk"
      cp -r . "$out/lib/node_modules/aws-cdk/"

      makeWrapper ${nodejs}/bin/node "$out/bin/cdk" \
        --add-flags "$out/lib/node_modules/aws-cdk/bin/cdk"

      runHook postInstall
    '';

    meta = with lib; {
      description = "AWS CDK Toolkit (cdk CLI)";
      homepage = "https://docs.aws.amazon.com/cdk/v2/guide/cli.html";
      license = licenses.asl20;
      maintainers = with maintainers; [ ];
      mainProgram = "cdk";
      platforms = platforms.all;
    };
  };
}
