#!/usr/bin/env bash
# NixOS-specific gap tests:
# 1. steam-run warning logic (isolated from install_lumen's network calls)
# 2. nixos_install_hint edge cases
# 3. main --skip-deps on NixOS
set -uo pipefail

RED="\033[0;31m"
GREEN="\033[0;32m"
NC="\033[0m"
PASS=0
FAIL=0

check() {
    local desc="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo -e "${GREEN}✓${NC} $desc"; PASS=$((PASS+1))
    else
        echo -e "${RED}✗${NC} $desc (expected: $expected, got: $actual)"; FAIL=$((FAIL+1))
    fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_SH="${SCRIPT_DIR}/../install.sh"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

export SLSPLUGIN_LIB_ONLY=1
# shellcheck source=/dev/null
source "$INSTALL_SH" >/dev/null 2>&1

echo "=========================================="
echo "  NixOS Gap Tests"
echo "=========================================="
echo ""

# ============================================================================
# 1. nixos_install_hint edge cases
# ============================================================================
echo "--- nixos_install_hint edge cases ---"

HINT=$(nixos_install_hint "")
check "empty list mentions systemPackages" "0" "$(echo "$HINT" | grep -q systemPackages && echo 0 || echo 1)"
check "empty list has empty brackets" "0" "$(echo "$HINT" | grep -q '\[  \]' && echo 0 || echo 1)"

HINT=$(nixos_install_hint "steam steam-run firefox")
check "multiple pkgs mentions systemPackages" "0" "$(echo "$HINT" | grep -q systemPackages && echo 0 || echo 1)"
check "multiple pkgs preserves order" "0" "$(echo "$HINT" | grep -q 'steam steam-run firefox' && echo 0 || echo 1)"

HINT=$(nixos_install_hint "jq")
check "single pkg mentions jq" "0" "$(echo "$HINT" | grep -q 'jq' && echo 0 || echo 1)"
check "single pkg mentions nixos-rebuild" "0" "$(echo "$HINT" | grep -q nixos-rebuild && echo 0 || echo 1)"

echo ""

# ============================================================================
# 2. steam-run: installer does NOT warn (runtime is slsteam-moon's job)
# ============================================================================
echo "--- steam-run: no warning in installer ---"

# Setup: NixOS environment
cat > "$TMPDIR/os-release" << 'OSREL'
ID=nixos
OSREL
OS_RELEASE_FILE="$TMPDIR/os-release" export OS_RELEASE_FILE

# Verify detection
check "distro_id is nixos" "nixos" "$(get_distro_id)"

# The installer patches the wrapper to USE steam-run on NixOS, but it does
# not warn the user about steam-run being missing — that's slsteam-moon's
# responsibility. Check that no log_warn mentions steam-run.
HAS_STEAM_RUN_WARN=$(grep -ci 'log_warn.*steam-run' "$INSTALL_SH" 2>/dev/null || true)
HAS_STEAM_RUN_WARN="${HAS_STEAM_RUN_WARN:-0}"
check "installer has no steam-run warning" "0" "$HAS_STEAM_RUN_WARN"

# Restore NixOS
OS_RELEASE_FILE="$TMPDIR/os-release" export OS_RELEASE_FILE

echo ""

# ============================================================================
# 3. main() flow on NixOS (all heavy functions mocked)
# ============================================================================
echo "--- main() flow on NixOS ---"

# Mock everything that does network/interactive/heavy work
cat > "$TMPDIR/mock_funcs.sh" << 'MOCK'
check_not_root() { return 0; }
check_arch() { return 0; }
check_internet() { return 0; }
check_steam_native() { return 0; }
check_steam_bootstrapped() { return 0; }
stop_steam() { return 0; }
stop_lumen() { return 0; }
cleanup_previous_install() { return 0; }
install_dependencies() {
    # On NixOS, the real install_dependencies shows the configuration.nix hint
    # We replicate the key output for the test
    if [ "$(get_distro_id)" = "nixos" ]; then
        echo "environment.systemPackages = with pkgs; [ jq curl ];"
        echo "Then run: sudo nixos-rebuild switch"
    fi
    return 0
}
install_slsteam_moon() { log_success "slsteam-moon installed"; return 0; }
install_lumen() {
    log_success "lumen installed"
    # No steam-run warning — runtime is slsteam-moon's responsibility
    return 0
}
install_plugin() { log_success "plugin installed"; return 0; }
configure_slsteam() { return 0; }
cleanup_legacy_files() { return 0; }
resolve_component_asset() { RESOLVED_ASSET_URL="file:///dev/null"; RESOLVED_ASSET_INFO="mock"; return 0; }
preask_prompts() { return 0; }
write_versions_stamp() { return 0; }
install_gamemode_hook() { return 0; }
install_cloudredirect() { return 0; }
should_autolaunch() { return 1; }
MOCK

# Source mock functions
# shellcheck source=/dev/null
source "$TMPDIR/mock_funcs.sh"

# Run main
OUTPUT=$(PATH="$PATH" main 2>&1) || true

# Should NOT prompt for sudo/password
if echo "$OUTPUT" | grep -qi "password\|administrador"; then
    check "main does not prompt sudo on NixOS" "no" "yes"
else
    check "main does not prompt sudo on NixOS" "no" "no"
fi

# Should NOT show steam-run warning (removed — runtime is slsteam-moon's job)
if echo "$OUTPUT" | grep -qi "steam-run"; then
    check "main does NOT show steam-run warning" "no" "yes"
else
    check "main does NOT show steam-run warning" "no" "no"
fi

# Should mention nixos (the NixOS dep hint path should have been taken)
if echo "$OUTPUT" | grep -qi "configuration.nix\|nixos-rebuild\|systemPackages"; then
    check "main shows NixOS dependency hint" "yes" "yes"
else
    check "main shows NixOS dependency hint" "yes" "no"
fi

echo ""

# ============================================================================
# Summary
# ============================================================================
echo "=========================================="
echo "  Results: $PASS passed, $FAIL failed"
echo "=========================================="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
