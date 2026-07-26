#!/usr/bin/env bash
# Steam detection matrix test — to be run INSIDE a distrobox with root.
# Creates/removes mock steam binaries at FHS paths + mock flatpak/snap.
#
# Usage: distrobox enter <name> -- sudo bash scripts/test-steam-matrix.sh
#    or: sudo bash scripts/test-steam-matrix.sh   (if running as root)
set -uo pipefail

# Find install.sh: same dir as this script's parent, or fallback to ~/install.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/../install.sh" ]; then
    INSTALL_SH="$SCRIPT_DIR/../install.sh"
elif [ -f "$SCRIPT_DIR/install.sh" ]; then
    INSTALL_SH="$SCRIPT_DIR/install.sh"
elif [ -f "$HOME/install.sh" ]; then
    INSTALL_SH="$HOME/install.sh"
else
    echo "Cannot find install.sh"; exit 1
fi

RED="\033[0;31m"
GREEN="\033[0;32m"
NC="\033[0m"

PASS=0
FAIL=0

check() {
    if [ "$2" = "$3" ]; then
        echo -e "${GREEN}✓${NC} $1"; PASS=$((PASS+1))
    else
        echo -e "${RED}✗${NC} $1 (expected: '$2', got: '$3')"; FAIL=$((FAIL+1))
    fi
}

check_contains() {
    if echo "$2" | grep -qiE "$3"; then
        echo -e "${GREEN}✓${NC} $1"; PASS=$((PASS+1))
    else
        echo -e "${RED}✗${NC} $1 (output missing '$3')"; FAIL=$((FAIL+1))
    fi
}

check_not_contains() {
    if echo "$2" | grep -qiE "$3"; then
        echo -e "${RED}✗${NC} $1 (unexpected '$3' in output)"; FAIL=$((FAIL+1))
    else
        echo -e "${GREEN}✓${NC} $1"; PASS=$((PASS+1))
    fi
}

# Require root to create files at FHS paths
if [ "$(id -u)" -ne 0 ]; then
    echo "This test requires root (creates files at /usr/bin/steam etc.)."
    echo "Run: distrobox enter <name> -- sudo bash $0"
    exit 1
fi

TMPDIR="$(mktemp -d)"
trap 'cleanup_all; rm -rf "$TMPDIR"' EXIT

export SLSPLUGIN_LIB_ONLY=1
# shellcheck source=/dev/null
source "$INSTALL_SH" >/dev/null 2>&1

echo "=========================================="
echo "  Steam Detection Matrix (root)"
echo "=========================================="
echo ""

# ============================================================================
# Helpers
# ============================================================================
setup_distro() {
    local id="$1" like="${2:-}" variant="${3:-}"
    local c="ID=$id"
    [ -n "$like" ] && c="$c
ID_LIKE=\"$like\""
    [ -n "$variant" ] && c="$c
VARIANT_ID=$variant"
    printf '%s\n' "$c" > "$TMPDIR/os-release"
    export OS_RELEASE_FILE="$TMPDIR/os-release"
}

# Place a fake steam binary at every FHS path the installer checks
place_native_steam() {
    for p in /usr/bin/steam /usr/games/steam /usr/local/bin/steam /bin/steam; do
        mkdir -p "$(dirname "$p")"
        printf '#!/bin/sh\necho mock-steam\n' > "$p"
        chmod +x "$p"
    done
}

# Remove all mock steam binaries we placed
remove_native_steam() {
    for p in /usr/bin/steam /usr/games/steam /usr/local/bin/steam /bin/steam; do
        # Only remove if it's our mock (small size, contains "mock-steam")
        if [ -f "$p" ] && grep -q "mock-steam" "$p" 2>/dev/null; then
            rm -f "$p"
        fi
    done
}

# Create a mock flatpak command that pretends Steam is (or isn't) installed via flatpak
# $1 = "has_steam" or "no_steam"
place_flatpak_mock() {
    local has_steam="$1"
    cat > /usr/local/bin/flatpak << 'FLEOF'
#!/usr/bin/env bash
if [[ "$*" == *"list"* ]]; then
    if [ -f /tmp/.flatpak_has_steam ]; then
        printf 'com.valvesoftware.Steam\tactive\tstable\tuser\n'
    else
        printf 'com.valvesoftware.BaseApp\tactive\tstable\tsystem\n'
    fi
fi
FLEOF
    chmod +x /usr/local/bin/flatpak
    if [ "$has_steam" = "has_steam" ]; then
        touch /tmp/.flatpak_has_steam
    else
        rm -f /tmp/.flatpak_has_steam
    fi
}

remove_flatpak_mock() {
    rm -f /usr/local/bin/flatpak /tmp/.flatpak_has_steam
}

# Create a mock snap command
# $1 = "has_steam" or "no_steam"
place_snap_mock() {
    local has_steam="$1"
    cat > /usr/local/bin/snap << 'SNEOF'
#!/usr/bin/env bash
if [[ "$*" == *"list"* ]]; then
    if [ -f /tmp/.snap_has_steam ]; then
        printf 'Name    Version   Rev    Tracking       Notes\nsteam   1.0.0.81  4173   latest/stable   -\ncore22  20240111  1122   latest/stable   -\n'
    else
        printf 'Name    Version   Rev    Tracking       Notes\ncore22  20240111  1122   latest/stable   -\n'
    fi
fi
SNEOF
    chmod +x /usr/local/bin/snap
    if [ "$has_steam" = "has_steam" ]; then
        touch /tmp/.snap_has_steam
    else
        rm -f /tmp/.snap_has_steam
    fi
}

remove_snap_mock() {
    rm -f /usr/local/bin/snap /tmp/.snap_has_steam
}

cleanup_all() {
    remove_native_steam
    remove_flatpak_mock
    remove_snap_mock
}

# ============================================================================
# Test matrix per distro
# ============================================================================

run_tests() {
    local label="$1" id="$2" like="${3:-}" variant="${4:-}"

    echo "--- $label ---"
    setup_distro "$id" "$like" "$variant"
    echo "  ID=$(get_distro_id)  Family=$(get_distro_family)"

    # -- none --
    cleanup_all
    check "[$label] detect: none" "none" "$(detect_steam_type)"

    # flatpak-no-steam
    cleanup_all
    place_flatpak_mock "no_steam"
    check "[$label] detect: flatpak-no-steam → none" "none" "$(detect_steam_type)"
    remove_flatpak_mock

    # snap-no-steam
    cleanup_all
    place_snap_mock "no_steam"
    check "[$label] detect: snap-no-steam → none" "none" "$(detect_steam_type)"
    remove_snap_mock

    # -- native (each FHS path) --
    for p in /usr/bin/steam /usr/games/steam /usr/local/bin/steam /bin/steam; do
        cleanup_all
        mkdir -p "$(dirname "$p")"
        printf '#!/bin/sh\necho mock\n' > "$p"; chmod +x "$p"
        check "[$label] detect: native $p" "native" "$(detect_steam_type)"
        # only remove our mock
        grep -q "mock" "$p" 2>/dev/null && rm -f "$p"
    done

    # -- flatpak with Steam --
    cleanup_all
    place_flatpak_mock "has_steam"
    check "[$label] detect: flatpak" "flatpak" "$(detect_steam_type)"
    remove_flatpak_mock

    # -- snap with Steam --
    cleanup_all
    place_snap_mock "has_steam"
    check "[$label] detect: snap" "snap" "$(detect_steam_type)"
    remove_snap_mock

    # -- native + flatpak → native wins --
    cleanup_all
    place_native_steam
    place_flatpak_mock "has_steam"
    check "[$label] detect: native+flatpak → native" "native" "$(detect_steam_type)"

    # -- native + snap → native wins --
    cleanup_all
    place_native_steam
    place_snap_mock "has_steam"
    check "[$label] detect: native+snap → native" "native" "$(detect_steam_type)"
    cleanup_all

    # -- suggest_native_steam_install --
    local sug
    sug="$(suggest_native_steam_install)"
    echo "  suggest: $sug"

    # -- check_steam_native: native → success --
    cleanup_all
    place_native_steam
    local chk
    chk="$(check_steam_native 2>&1)" || true
    check_not_contains "[$label] check_steam_native: native → no abort" "$chk" "Abortado|Aborted"
    cleanup_all

    echo ""
}

# ============================================================================
# NixOS: special PATH-based detection
# ============================================================================

run_nixos_tests() {
    local label="NixOS"
    echo "--- $label ---"
    setup_distro "nixos"
    echo "  ID=$(get_distro_id)  Family=$(get_distro_family)"

    # -- none: need to also hide any real steam from PATH --
    cleanup_all
    # Temporarily hide real steam if present
    REAL_STEAM=""
    if command -v steam >/dev/null 2>&1; then
        REAL_STEAM="$(command -v steam)"
        mv "$REAL_STEAM" "${REAL_STEAM}.bak"
    fi
    check "[$label] detect: none (no steam on PATH)" "none" "$(detect_steam_type)"
    if [ -n "$REAL_STEAM" ]; then
        mv "${REAL_STEAM}.bak" "$REAL_STEAM"
    fi

    # -- native via FHS paths (same as other distros) --
    for p in /usr/bin/steam /usr/games/steam /usr/local/bin/steam /bin/steam; do
        cleanup_all
        mkdir -p "$(dirname "$p")"
        printf '#!/bin/sh\necho mock\n' > "$p"; chmod +x "$p"
        check "[$label] detect: native $p" "native" "$(detect_steam_type)"
        grep -q "mock" "$p" 2>/dev/null && rm -f "$p"
    done

    # -- native via PATH (NixOS-specific path, not FHS) --
    cleanup_all
    if [ -n "$REAL_STEAM" ]; then
        mv "$REAL_STEAM" "${REAL_STEAM}.bak"
    fi
    mkdir -p "$TMPDIR/nix-store/bin"
    printf '#!/bin/sh\necho mock\n' > "$TMPDIR/nix-store/bin/steam"
    chmod +x "$TMPDIR/nix-store/bin/steam"
    # On NixOS with steam on PATH (but not FHS): should detect native
    local SAVED_PATH="$PATH"
    export PATH="$TMPDIR/nix-store/bin:$PATH"
    check "[$label] detect: PATH-only steam → native" "native" "$(detect_steam_type)"
    # On non-NixOS with same PATH-only: should detect none
    setup_distro "ubuntu" "debian"
    check "[$label] non-nixos + PATH-only → none" "none" "$(detect_steam_type)"
    setup_distro "nixos"  # restore
    export PATH="$SAVED_PATH"
    if [ -n "$REAL_STEAM" ]; then
        mv "${REAL_STEAM}.bak" "$REAL_STEAM"
    fi

    # -- flatpak / snap not checked on NixOS (flatpak check is after NixOS check) --
    cleanup_all
    place_flatpak_mock "has_steam"
    # On NixOS, flatpak check is skipped (NixOS PATH check fires first if steam is on PATH)
    # But if steam is NOT on PATH, flatpak check should still work
    if [ -n "$REAL_STEAM" ]; then
        mv "$REAL_STEAM" "${REAL_STEAM}.bak"
    fi
    # Note: detect_steam_type checks NixOS PATH before flatpak, so if steam is on PATH it returns native.
    # If steam is NOT on PATH and only flatpak has it, it should return flatpak.
    check "[$label] detect: flatpak (no steam on PATH)" "flatpak" "$(detect_steam_type)"
    remove_flatpak_mock
    if [ -n "$REAL_STEAM" ]; then
        mv "${REAL_STEAM}.bak" "$REAL_STEAM"
    fi

    # -- suggest --
    local sug
    sug="$(suggest_native_steam_install)"
    check_contains "[$label] suggest mentions configuration.nix" "$sug" "configuration.nix"

    cleanup_all
    echo ""
}

# ============================================================================
# Immutable distros: suggest message
# ============================================================================

run_immutable_tests() {
    echo "--- Immutable distros (suggest) ---"
    for combo in "bazzite:fedora:" "steamos:arch:" "silverblue:fedora:silverblue" "bluefin:fedora:" "aurora:fedora:" "holoiso:arch:"; do
        IFS=: read -r fid flike fvar <<< "$combo"
        setup_distro "$fid" "$flike" "$fvar"
        local sug
        sug="$(suggest_native_steam_install)"
        check_contains "[$fid] suggest → OS image message" "$sug" "OS image|imagem do SO"
    done
    echo ""
}

# ============================================================================
# Main
# ============================================================================

# Debian family
run_tests "Debian" "debian" "debian"
run_tests "Ubuntu" "ubuntu" "debian"
run_tests "Linux Mint" "linuxmint" "ubuntu debian"
run_tests "Pop!_OS" "pop" "ubuntu debian"

# Fedora family
run_tests "Fedora" "fedora"
run_tests "RHEL" "rhel" "fedora"
run_tests "Rocky" "rocky" "rhel fedora"
run_tests "AlmaLinux" "alma" "rhel fedora"

# Arch family
run_tests "Arch" "arch"
run_tests "Manjaro" "manjaro" "arch"
run_tests "EndeavourOS" "endeavouros" "arch"
run_tests "Garuda" "garuda" "arch"

# openSUSE family
run_tests "openSUSE Leap" "opensuse-leap" "suse opensuse"
run_tests "openSUSE TW" "opensuse-tumbleweed" "suse opensuse"

# NixOS
run_nixos_tests

# Immutable suggest
run_immutable_tests

# check_steam_native error messages
echo "--- check_steam_native error messages ---"
setup_distro "debian" "debian"

cleanup_all
place_flatpak_mock "has_steam"
CHK="$(check_steam_native 2>&1)" || true
check_contains "flatpak → mentions Flatpak" "$CHK" "Flatpak"
check_contains "flatpak → mentions NATIVE" "$CHK" "NATIVE|NATIVA"
check_contains "flatpak → suggests uninstall" "$CHK" "flatpak uninstall"
remove_flatpak_mock

cleanup_all
place_snap_mock "has_steam"
CHK="$(check_steam_native 2>&1)" || true
check_contains "snap → mentions Snap" "$CHK" "Snap"
check_contains "snap → suggests remove" "$CHK" "snap remove"
remove_snap_mock

cleanup_all
CHK="$(check_steam_native 2>&1)" || true
check_contains "none → mentions no Steam" "$CHK" "No native Steam|nenhuma.*Steam"
check_contains "none → shows install command" "$CHK" "install|instale"

echo ""

# Summary
echo "=========================================="
echo "  Results: $PASS passed, $FAIL failed"
echo "=========================================="
cleanup_all
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
