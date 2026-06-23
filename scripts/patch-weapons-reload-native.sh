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

if ! grep -q 'Weapons_ReloadClientData' "${WEAPONS_SP}"; then
  echo "Patching weapons.sp AskPluginLoad2 (ReloadClientData + RefreshWeapon natives)..."
  sed -i '/CreateNative("Weapons_GetClientKnife"/a\
\tCreateNative("Weapons_ReloadClientData", Weapons_ReloadClientData_Native);\
\tCreateNative("Weapons_RefreshWeapon", Weapons_RefreshWeapon_Native);' "${WEAPONS_SP}"
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

if ! grep -q 'Weapons_ReloadClientData' "${WEAPONS_SP}"; then
  echo "ERROR: ReloadClientData patch did not apply to weapons.sp" >&2
  exit 1
fi

if ! grep -q 'Weapons_RefreshWeapon' "${WEAPONS_SP}"; then
  echo "ERROR: RefreshWeapon patch did not apply to weapons.sp" >&2
  exit 1
fi

echo "Done. weapons.smx updated with Weapons_ReloadClientData + Weapons_RefreshWeapon."
echo "In screen: sm plugins reload weapons"
echo "Bridge should log z_clutch_gloves natives ready (no missing native warnings)."
