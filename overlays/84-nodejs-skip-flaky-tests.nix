# nodejs_26 ships a TLS test (test/parallel/test-tls-getcipher.js) that opens a
# real network socket and fails with ECONNRESET inside the Nix build sandbox
# (no network). nodejs_26 is only pulled in as a *build-time* tool to bundle
# llama-cpp's web UI, so running its full test suite is pure overhead here.
# Disable checks rather than play whack-a-mole with individual flaky network
# tests. Mirror the rationale of overlays/81-python313-disable-checks.nix.
final: prev:
let
  skipNodeChecks =
    node:
    node.overrideAttrs (_old: {
      doCheck = false;
    });
in
{
  # In current nixpkgs the heavy compile + the full test suite run in the
  # nodejs-slim derivation; the plain nodejs package is a thin layer on top of
  # it. Disable checks on the slim build (the one that actually fails) and the
  # full package rebuilds against it via the overlay's `final` set.
  nodejs-slim_26 = skipNodeChecks prev.nodejs-slim_26;
  nodejs-slim_latest = skipNodeChecks prev.nodejs-slim_latest;
  nodejs_26 = skipNodeChecks prev.nodejs_26;
  nodejs_latest = skipNodeChecks prev.nodejs_latest;
}
