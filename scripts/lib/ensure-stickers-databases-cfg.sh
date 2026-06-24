#!/usr/bin/env bash
# Ensures csgo_weaponstickers SQLite block exists in SourceMod databases.cfg.
# Used by install-clutch-skins-bridge.sh and install-csgo-weaponstickers.sh.

ensure_stickers_databases_cfg() {
  local sm_root="${1:?SM root required}"
  local db_cfg="${sm_root}/configs/databases.cfg"

  if [[ ! -f "${db_cfg}" ]]; then
    echo "WARN: ${db_cfg} not found — add csgo_weaponstickers SQLite block manually" >&2
    return 1
  fi

  if grep -q '"csgo_weaponstickers"' "${db_cfg}"; then
    echo "csgo_weaponstickers entry already in databases.cfg"
    return 0
  fi

  cat >> "${db_cfg}" <<'EOF'

"csgo_weaponstickers"
{
	"driver"		"sqlite"
	"database"		"csgo_weaponstickers"
}
EOF
  echo "Added csgo_weaponstickers block to databases.cfg"
  return 0
}
