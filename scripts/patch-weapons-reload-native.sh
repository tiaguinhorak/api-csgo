#!/usr/bin/env bash
set -euo pipefail

# Adds Weapons_ReloadClientData native to kgns weapons.smx so clutch bridge can
# refresh in-memory g_iSkins after the site updates SQLite externally.
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
  echo "Patching weapons.sp (CreateNative)..."
  sed -i '/CreateNative("Weapons_SetClientKnife"/a\
\tCreateNative("Weapons_ReloadClientData", Weapons_ReloadClientData_Native);' "${WEAPONS_SP}"
fi

if ! grep -q 'Weapons_ReloadClientData_Native' "${NATIVES_SP}"; then
  echo "Patching weapons/natives.sp..."
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

echo "Compiling weapons.smx..."
cd "${SCRIPTING}"
"${SPCOMP}" weapons.sp -o"${SM}/plugins/weapons.smx"

echo "Done. weapons.smx updated with Weapons_ReloadClientData native."
echo "Restart map or: sm plugins reload weapons"
