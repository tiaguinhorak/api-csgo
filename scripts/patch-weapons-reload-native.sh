#!/usr/bin/env bash
set -euo pipefail

# Adds Weapons_ReloadClientData + Weapons_RefreshWeapon natives to kgns weapons.smx
# so clutch bridge can refresh in-memory g_iSkins and re-give weapons like !ws.
#
# Usage (on VPS as csgo):
#   CSGO_ROOT=/home/csgo/server/csgo bash scripts/patch-weapons-reload-native.sh

CSGO_ROOT="${CSGO_ROOT:-/home/csgo/server/csgo}"
SM="${CSGO_ROOT}/addons/sourcemod"
SCRIPTING="${SM}/scripting"
WEAPONS_SP="${SCRIPTING}/weapons.sp"
NATIVES_SP="${SCRIPTING}/weapons/natives.sp"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPCOMP="${SCRIPTING}/spcomp"
if [[ ! -x "${SPCOMP}" ]]; then
  SPCOMP="${SCRIPTING}/spcomp64"
fi

if [[ ! -f "${WEAPONS_SP}" ]]; then
  echo "weapons.sp not found at ${WEAPONS_SP}" >&2
  echo "Install kgns weapons source first, then re-run this script." >&2
  exit 1
fi

if [[ ! -x "${SPCOMP}" ]]; then
  echo "spcomp not found under ${SCRIPTING}" >&2
  exit 1
fi

cp -f "${REPO_ROOT}/sourcemod/include/weapons.inc" "${SCRIPTING}/include/weapons.inc"

patch_weapons_admin_only_cmds() {
  if grep -q 'CLUTCH_WS_ADMIN_ONLY' "${WEAPONS_SP}"; then
    echo "weapons.sp already patched for Clutch admin-only !ws"
    return 0
  fi

  echo "Patching weapons.sp — !ws / !knife admin-only (flag b); players use web inventory..."
  awk '
    /RegConsoleCmd\("buyammo1", CommandWeaponSkins\)/ {
      print "\t// CLUTCH_WS_ADMIN_ONLY"
      print "\tRegAdminCmd(\"buyammo1\", CommandWeaponSkins, ADMFLAG_GENERIC, \"Admin only — players equip via web\");"
      next
    }
    /RegConsoleCmd\("sm_ws", CommandWeaponSkins\)/ {
      print "\tRegAdminCmd(\"sm_ws\", CommandWeaponSkins, ADMFLAG_GENERIC, \"Admin only — players equip via web\");"
      next
    }
    /RegConsoleCmd\("buyammo2", CommandKnife\)/ {
      print "\tRegAdminCmd(\"buyammo2\", CommandKnife, ADMFLAG_GENERIC, \"Admin only — players equip via web\");"
      next
    }
    /RegConsoleCmd\("sm_knife", CommandKnife\)/ {
      print "\tRegAdminCmd(\"sm_knife\", CommandKnife, ADMFLAG_GENERIC, \"Admin only — players equip via web\");"
      next
    }
    /RegConsoleCmd\("sm_kf", CommandKnife\)/ {
      print "\tRegAdminCmd(\"sm_kf\", CommandKnife, ADMFLAG_GENERIC, \"Admin only — players equip via web\");"
      next
    }
    /RegConsoleCmd\("sm_nametag", CommandNameTag\)/ {
      print "\tRegAdminCmd(\"sm_nametag\", CommandNameTag, ADMFLAG_GENERIC, \"Admin only — players equip via web\");"
      next
    }
    /RegConsoleCmd\("sm_wslang", CommandWSLang\)/ {
      print "\tRegAdminCmd(\"sm_wslang\", CommandWSLang, ADMFLAG_GENERIC, \"Admin only — players equip via web\");"
      next
    }
    /RegConsoleCmd\("sm_seed", CommandSeedMenu\)/ {
      print "\tRegAdminCmd(\"sm_seed\", CommandSeedMenu, ADMFLAG_GENERIC, \"Admin only — players equip via web\");"
      next
    }
    /RegConsoleCmd\("sm_skin", CommandWeaponSkins\)/ {
      print "\tRegAdminCmd(\"sm_skin\", CommandWeaponSkins, ADMFLAG_GENERIC, \"Admin only — players equip via web\");"
      next
    }
    /RegConsoleCmd\("sm_skins", CommandWeaponSkins\)/ {
      print "\tRegAdminCmd(\"sm_skins\", CommandWeaponSkins, ADMFLAG_GENERIC, \"Admin only — players equip via web\");"
      next
    }
    { print }
  ' "${WEAPONS_SP}" > "${WEAPONS_SP}.patched"
  mv -f "${WEAPONS_SP}.patched" "${WEAPONS_SP}"
}

patch_weapons_admin_only_cmds

if ! grep -q 'CreateNative("Weapons_ReloadClientData"' "${WEAPONS_SP}"; then
  echo "Patching weapons.sp AskPluginLoad2 (ReloadClientData + RefreshWeapon natives)..."
  awk '
    /CreateNative\("Weapons_GetClientKnife"/ {
      print
      print "\tCreateNative(\"Weapons_ReloadClientData\", Weapons_ReloadClientData_Native);"
      print "\tCreateNative(\"Weapons_RefreshWeapon\", Weapons_RefreshWeapon_Native);"
      next
    }
    { print }
  ' "${WEAPONS_SP}" > "${WEAPONS_SP}.patched"
  mv -f "${WEAPONS_SP}.patched" "${WEAPONS_SP}"
fi

if ! grep -q 'Weapons_ReloadClientData_Native' "${NATIVES_SP}"; then
  echo "Patching weapons/natives.sp (ReloadClientData)..."
  cat >> "${NATIVES_SP}" <<'EOF'

public int Weapons_ReloadClientData_Native(Handle plugin, int numparams)
{
	int client = GetNativeCell(1);
	if (client < 1 || client > MaxClients)
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d).", client);
	}
	if (!IsClientInGame(client))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Client (%d) is not in game.", client);
	}
	GetPlayerData(client);
	return 0;
}
EOF
fi

if ! grep -q 'Weapons_RefreshWeapon_Native' "${NATIVES_SP}"; then
  echo "Patching weapons/natives.sp (RefreshWeapon)..."
  cat >> "${NATIVES_SP}" <<'EOF'

public int Weapons_RefreshWeapon_Native(Handle plugin, int numparams)
{
	int client = GetNativeCell(1);
	int index = GetNativeCell(2);
	if (client < 1 || client > MaxClients)
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d).", client);
	}
	if (!IsClientInGame(client))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Client (%d) is not in game.", client);
	}
	if (index < 0 || index >= sizeof(g_WeaponClasses))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid weapon index (%d).", index);
	}
	RefreshWeapon(client, index, false);
	return 0;
}
EOF
fi

echo "Compiling weapons.smx..."
cd "${SCRIPTING}"
if ! "${SPCOMP}" weapons.sp -o"${SM}/plugins/weapons.smx"; then
  echo "weapons.smx compile failed — fix errors above" >&2
  exit 1
fi

if ! grep -q 'CreateNative("Weapons_ReloadClientData"' "${WEAPONS_SP}"; then
  echo "ERROR: ReloadClientData CreateNative missing from weapons.sp" >&2
  exit 1
fi

if ! grep -q 'CreateNative("Weapons_RefreshWeapon"' "${WEAPONS_SP}"; then
  echo "ERROR: RefreshWeapon CreateNative missing from weapons.sp" >&2
  exit 1
fi

echo "AskPluginLoad2 natives in weapons.sp:"
grep 'CreateNative("Weapons_' "${WEAPONS_SP}" || true

echo "Done. weapons.smx updated with Weapons_ReloadClientData + Weapons_RefreshWeapon + admin-only !ws."
echo "In screen: sm plugins reload weapons"
echo "Then: sm plugins reload z_clutch_skins_bridge"
echo "Bridge should log no missing native warnings after reload."
