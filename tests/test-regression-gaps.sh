#!/usr/bin/env bash
# Regression gap tests for distro detection across families:
# - Arch Linux family detection
# - Immutable distros (Bazzite/Silverblue) isolation from NixOS
# - Distro family inheritance (ubuntu->debian, mint->debian, etc.)
# Uses synthetic os-release fixtures so it runs on any host.
#
# Run: bash scripts/test-regression-gaps.sh
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_SH="$SCRIPT_DIR/../install.sh"

failures=0
check() { # $1 desc  $2 result(0/1)
    if [ "$2" -eq 0 ]; then printf 'ok:   %s\n' "$1"
    else printf 'FAIL: %s\n' "$1"; failures=$((failures+1)); fi
}

TESTDIR="$(mktemp -d)"
trap 'rm -rf "$TESTDIR"' EXIT
export SLSPLUGIN_LIB_ONLY=1

# shellcheck source=/dev/null
source "$INSTALL_SH" >/dev/null 2>&1

fixture() { OS_RELEASE_FILE="$TESTDIR/os-release"; printf '%s\n' "$1" > "$OS_RELEASE_FILE"; export OS_RELEASE_FILE; }

echo "=========================================="
echo "  Regression Gap Tests"
echo "=========================================="
echo ""

# ============================================================================
# 1. Arch Linux family detection
# ============================================================================
echo "--- Arch family detection ---"

fixture 'ID=arch
ID_LIKE="archlinux"'
[ "$(get_distro_family)" = "arch" ]; check "family: arch -> arch" $?

fixture 'ID=endeavouros
ID_LIKE="arch"'
[ "$(get_distro_family)" = "arch" ]; check "family: endeavouros -> arch" $?

fixture 'ID=manjaro
ID_LIKE="arch"'
[ "$(get_distro_family)" = "arch" ]; check "family: manjaro -> arch" $?

fixture 'ID=garuda
ID_LIKE="arch"'
[ "$(get_distro_family)" = "arch" ]; check "family: garuda -> arch" $?

# Arch is NOT immutable
fixture 'ID=arch'
if is_immutable_distro; then r=1; else r=0; fi
check "immutable: arch -> no" "$r"

# Arch sudo should work normally
fixture 'ID=arch'
SUDO_RESULT=$(sudo_prefix)
[ "$SUDO_RESULT" = "sudo" ]; check "sudo_prefix on arch returns sudo" $?

echo ""

# ============================================================================
# 2. Immutable distros must NOT match NixOS family
# ============================================================================
echo "--- Immutable distros vs NixOS ---"

fixture 'ID=bazzite
ID_LIKE="fedora"'
FAMILY=$(get_distro_family)
[ "$FAMILY" = "fedora" ]; check "family: bazzite -> fedora (not nixos)" $?
if is_immutable_distro; then r=0; else r=1; fi
check "immutable: bazzite -> yes" $?

fixture 'ID=silverblue
ID_LIKE="fedora"'
FAMILY=$(get_distro_family)
[ "$FAMILY" = "fedora" ]; check "family: silverblue -> fedora (not nixos)" $?

fixture 'ID=bluefin
ID_LIKE="fedora"'
FAMILY=$(get_distro_family)
[ "$FAMILY" = "fedora" ]; check "family: bluefin -> fedora (not nixos)" $?

fixture 'ID=aurora
ID_LIKE="fedora"'
FAMILY=$(get_distro_family)
[ "$FAMILY" = "fedora" ]; check "family: aurora -> fedora (not nixos)" $?

# NixOS is NOT immutable (per our is_immutable_distro check)
fixture 'ID=nixos'
if is_immutable_distro; then r=1; else r=0; fi
check "immutable: nixos -> no" $?

# NixOS family should be nixos, not "unknown"
fixture 'ID=nixos'
FAMILY=$(get_distro_family)
[ "$FAMILY" = "nixos" ]; check "family: nixos -> nixos" $?

echo ""

# ============================================================================
# 3. Distro family inheritance
# ============================================================================
echo "--- Family inheritance ---"

fixture 'ID=ubuntu
ID_LIKE=debian'
[ "$(get_distro_family)" = "debian" ]; check "family: ubuntu -> debian" $?

fixture 'ID=debian'
[ "$(get_distro_family)" = "debian" ]; check "family: debian -> debian" $?

fixture 'ID=linuxmint
ID_LIKE="ubuntu debian"'
[ "$(get_distro_family)" = "debian" ]; check "family: mint -> debian" $?

fixture 'ID=pop
ID_LIKE="ubuntu debian"'
[ "$(get_distro_family)" = "debian" ]; check "family: pop!_os -> debian" $?

fixture 'ID=zorin
ID_LIKE="ubuntu debian"'
[ "$(get_distro_family)" = "debian" ]; check "family: zorin -> debian" $?

fixture 'ID=kali
ID_LIKE="debian"'
[ "$(get_distro_family)" = "debian" ]; check "family: kali -> debian" $?

fixture 'ID=raspbian
ID_LIKE="debian"'
[ "$(get_distro_family)" = "debian" ]; check "family: raspbian -> debian" $?

fixture 'ID=fedora'
[ "$(get_distro_family)" = "fedora" ]; check "family: fedora -> fedora" $?

fixture 'ID=rhel
ID_LIKE="fedora"'
[ "$(get_distro_family)" = "fedora" ]; check "family: rhel -> fedora" $?

fixture 'ID=centos
ID_LIKE="rhel fedora"'
[ "$(get_distro_family)" = "fedora" ]; check "family: centos -> fedora" $?

fixture 'ID=rocky
ID_LIKE="rhel fedora"'
[ "$(get_distro_family)" = "fedora" ]; check "family: rocky -> fedora" $?

fixture 'ID=alma
ID_LIKE="rhel fedora"'
[ "$(get_distro_family)" = "fedora" ]; check "family: alma -> fedora" $?

fixture 'ID=opensuse-leap
ID_LIKE="suse opensuse"'
[ "$(get_distro_family)" = "opensuse" ]; check "family: opensuse-leap -> opensuse" $?

fixture 'ID=opensuse-tumbleweed
ID_LIKE="suse opensuse"'
[ "$(get_distro_family)" = "opensuse" ]; check "family: opensuse-tumbleweed -> opensuse" $?

echo ""

# ============================================================================
# 4. SteamOS inherits arch family, not nixos
# ============================================================================
echo "--- SteamOS isolation ---"

fixture 'ID=steamos
ID_LIKE="arch"'
FAMILY=$(get_distro_family)
[ "$FAMILY" = "arch" ]; check "family: steamos -> arch (not nixos)" $?
if is_immutable_distro; then r=0; else r=1; fi
check "immutable: steamos -> yes" $?

fixture 'ID=steamdeck
ID_LIKE="steamos arch"'
FAMILY=$(get_distro_family)
[ "$FAMILY" = "arch" ]; check "family: steamdeck -> arch (not nixos)" $?

echo ""

# ============================================================================
# 5. Unknown distros
# ============================================================================
echo "--- Unknown distros ---"

fixture 'ID=void'
[ "$(get_distro_family)" = "unknown" ]; check "family: void -> unknown" $?

fixture 'ID=alpine'
[ "$(get_distro_family)" = "unknown" ]; check "family: alpine -> unknown" $?

fixture 'ID=gentoo'
[ "$(get_distro_family)" = "unknown" ]; check "family: gentoo -> unknown" $?

OS_RELEASE_FILE="$TESTDIR/missing"; export OS_RELEASE_FILE
[ "$(get_distro_family)" = "unknown" ]; check "family: missing os-release -> unknown" $?
[ "$(get_distro_id)" = "unknown" ]; check "id: missing os-release -> unknown" $?

echo ""

# ============================================================================
# Summary
# ============================================================================
echo "=========================================="
if [ "$failures" -eq 0 ]; then
    echo "  ALL PASS"
    echo "=========================================="
    exit 0
fi
echo "  $failures CHECK(S) FAILED"
echo "=========================================="
exit 1
