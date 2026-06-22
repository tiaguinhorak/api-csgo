# Skins Bridge — Site ↔ Servidor CS:GO

Fluxo (v3 — **sem arquivo**): o jogador equipa no site → Postgres → **API JSON** → SQLite do `!ws` (kgns weapons) → plugin lê o DB no spawn.

```
Site (equip/unequip) → POST /api/csgo/skins/player-sync (api-csgo na VPS)
     ↓
local.sq3 (weapons table, mesmo DB do !ws)
     ↓
RCON sm_clutch_applyskins
     ↓
z_clutch_skins_bridge.smx v3 (lê DB no spawn)
```

O menu `!ws` / `!knife` continua disponível como override manual até o próximo spawn/reload.

**Legado:** `POST /api/csgo/skins/push` e `clutch_skins.txt` ainda existem mas não são usados pelo site.

---

## 1. Variáveis de ambiente

### Site (`site/.env`)

```env
CSGO_API_URL=http://188.220.168.233:3000
CSGO_SKINS_SYNC_KEY=uma-chave-longa-aleatoria-compartilhada-com-a-vps
```

### api-csgo na VPS (`api-csgo/.env`)

```env
CSGO_SKINS_SYNC_KEY=mesma-chave-do-site
WEAPONS_DB_PATH=/home/csgo/server/csgo/addons/sourcemod/data/sqlite/local.sq3
WEAPONS_TABLE_PREFIX=
CSGO_SERVER_HOST=127.0.0.1
CSGO_RCON_PORT=27015
CSGO_RCON_PASSWORD=...
```

### VPS (cron — **opcional / legado**)

```env
CLUTCH_SITE_URL=https://clutchclube.com
CSGO_SKINS_SYNC_KEY=mesma-chave-do-site
```

### Desenvolvimento (site local, CS na VPS)

Não precisa SCP de `clutch_skins.txt`. O site local faz POST em `CSGO_API_URL` após equip.

---

## 2. API player-sync (api-csgo)

| Endpoint | Auth | Body |
|----------|------|------|
| `POST /api/csgo/skins/player-sync` | `x-skins-sync-key` | JSON `{ steamId, weapons[] }` |

Exemplo:

```json
{
  "steamId": "STEAM_1:0:203852188",
  "weapons": [
    {
      "weaponId": "weapon_ak47",
      "paintkit": 1207,
      "wear": 0.15,
      "seed": 0,
      "stattrak": false
    }
  ]
}
```

Resposta: `{ ok, mode: "db", steamId, weapons, updated, rconReload }`

Teste:

```bash
curl -X POST "http://127.0.0.1:3000/api/csgo/skins/player-sync" \
  -H "x-skins-sync-key: $CSGO_SKINS_SYNC_KEY" \
  -H "Content-Type: application/json" \
  -d '{"steamId":"STEAM_1:0:12345","weapons":[{"weaponId":"weapon_ak47","paintkit":1207,"wear":0.15,"seed":0}]}'
```

---

## 2b. API de export (site — legado / debug)

| Endpoint | Auth | Resposta |
|----------|------|----------|
| `GET /api/csgo/skins/export` | Header `x-skins-sync-key` ou `Authorization: Bearer <key>` | `text/plain` KeyValues |

Formato (root `ClutchSkins`):

```kv
"ClutchSkins"
{
    "STEAM_1:0:12345"
    {
        "weapon_ak47"
        {
            "paintkit"    "1207"
            "wear"        "0.15"
            "seed"        "0"
        }
        "weapon_knife"
        {
            "paintkit"    "568"
            "wear"        "0.07"
            "seed"        "42"
            "stattrak"    "0"
        }
    }
}
```

Teste local:

```bash
curl -fsS -H "x-skins-sync-key: $CSGO_SKINS_SYNC_KEY" \
  "https://clutchclube.com/api/csgo/skins/export"
```

---

## 3. Equipar no site

| Endpoint | Auth | Body |
|----------|------|------|
| `POST /api/inventory/equip` | Sessão + CSRF (`x-clutchclube-request: 1`) | `{ "inventoryItemId": "<id>" }` |

Requisitos:

- Steam vinculada no perfil (`User.steamId`)
- Item no inventário com `catalogSkinId` ligado ao `CsgoSkinCatalog`

Atualiza `UserInventoryItem.equipped` (por categoria) e `CsgoPlayerSkin.equipped` (por `weaponId`).

---

## 4. Sync na VPS (produção)

Script: `api-csgo/scripts/sync-clutch-skins.sh`

```bash
chmod +x /home/csgo/server/api-csgo/scripts/sync-clutch-skins.sh

export CLUTCH_SITE_URL="https://clutchclube.com"
export CSGO_SKINS_SYNC_KEY="..."
/home/csgo/server/api-csgo/scripts/sync-clutch-skins.sh
```

Destino padrão:

```
/home/csgo/server/csgo/addons/sourcemod/data/clutch_skins.txt
```

Cron (exemplo — a cada minuto, quando o site estiver público):

```cron
* * * * * CLUTCH_SITE_URL=https://clutchclube.com CSGO_SKINS_SYNC_KEY=... /home/csgo/server/api-csgo/scripts/sync-clutch-skins.sh
```

---

## 4b. Sync em desenvolvimento (site local)

Cenário: `npm run dev` no PC, Postgres + CS:GO na VPS.

```
[PC] localhost:3000  ──DATABASE_URL──►  Postgres (VPS)
[PC] sync-dev script  ──SCP──────────►  clutch_skins.txt (VPS)
[VPS] clutch_skins_bridge.smx lê o arquivo no spawn
```

### Passo a passo

1. **Site `.env`** (já apontando ao Postgres da VPS):

```env
DATABASE_URL=postgresql://...
CSGO_SKINS_SYNC_KEY=dev-sync-key-troque-por-algo-seguro
```

2. **Subir o site local:**

```bash
cd site
npm run dev
```

3. **Testar export no PC:**

```bash
curl -fsS -H "x-skins-sync-key: dev-sync-key-troque-por-algo-seguro" \
  "http://127.0.0.1:3000/api/csgo/skins/export"
```

Deve retornar KeyValues (mesmo vazio `"ClutchSkins" { }` se ninguém equipou).

4. **No site:** login → vincular Steam → inventário → equipar skin.

5. **Sync + upload (Git Bash no Windows):**

```bash
cd api-csgo/scripts
export CSGO_SKINS_SYNC_KEY="dev-sync-key-troque-por-algo-seguro"
export CLUTCH_SITE_URL="http://127.0.0.1:3000"
export CLUTCH_SSH_TARGET="csgo@188.220.168.233"
./sync-clutch-skins-dev.sh
```

PowerShell:

```powershell
$env:CSGO_SKINS_SYNC_KEY = "dev-sync-key-troque-por-algo-seguro"
cd C:\Users\keillon\Desktop\CsgoPage\api-csgo\scripts
.\sync-clutch-skins-dev.ps1
```

6. **No servidor CS** (screen / RCON):

```text
sm_reloadclutchskins
```

Ou aguardar o plugin recarregar (~30s) e **respawn** no mapa.

### Loop automático enquanto desenvolve

Git Bash:

```bash
while true; do ./sync-clutch-skins-dev.sh; sleep 30; done
```

### Alternativa: túnel (ngrok / cloudflared)

Se preferir rodar `sync-clutch-skins.sh` **na VPS** apontando ao dev:

```bash
# no PC: cloudflared tunnel --url http://127.0.0.1:3000
export CLUTCH_SITE_URL="https://xxxx.trycloudflare.com"
```

---

## 5. Plugin SourceMod

Arquivos no repo:

- `api-csgo/sourcemod/clutch_skins_bridge.sp`
- `api-csgo/sourcemod/clutch_skins_bridge.cfg`

### Instalação na VPS

```bash
# Copiar source
cp api-csgo/sourcemod/clutch_skins_bridge.sp \
  /home/csgo/server/csgo/addons/sourcemod/scripting/

# Compilar (no servidor, com spcomp do SourceMod)
cd /home/csgo/server/csgo/addons/sourcemod/scripting
./spcomp clutch_skins_bridge.sp -o../plugins/clutch_skins_bridge.smx

# Config
cp api-csgo/sourcemod/clutch_skins_bridge.cfg \
  /home/csgo/server/csgo/cfg/sourcemod/
```

Adicionar em `addons/sourcemod/configs/plugins/clutch_skins_bridge.cfg` (ou `plugins.cfg`):

```
clutch_skins_bridge
```

### Requisitos

- SourceMod
- `core.cfg`: `"FollowCSGOServerGuidelines" "no"` + restart completo do `srcds`
- PTaH é necessário apenas para o plugin Weapons `!ws` (este bridge usa netprops diretos)

### ConVars

| ConVar | Default | Descrição |
|--------|---------|-----------|
| `clutch_skins_file` | `data/clutch_skins.txt` | Relativo a `addons/sourcemod/` |
| `clutch_skins_refresh` | `30.0` | Intervalo de reload (segundos) |

### Comandos admin

| Comando | Descrição |
|---------|-----------|
| `sm_reloadclutchskins` | Recarrega o arquivo e reaplica |

---

## 6. Catálogo e inventário (dev)

Migration: `20260622050000_inventory_catalog_skin_bridge`

- `InventoryItem.catalogSkinId` → `CsgoSkinCatalog.id`
- `InventoryItem.imageUrl`, `CsgoSkinCatalog.imageUrl` (opcional)

Seed liga itens demo (AK, AWP, facas, etc.) ao catálogo. Luvas e agentes ficam sem `catalogSkinId` no v1.

```bash
cd site
npx prisma migrate deploy
npm run db:seed
```

---

## 7. Troubleshooting

| Problema | Causa provável | Fix |
|----------|----------------|-----|
| Equipar falha no site | Steam não vinculada | Vincular Steam no perfil |
| Botão "Sem skin CS:GO" | Item sem `catalogSkinId` | Ligar item ao catálogo (admin/seed) |
| Export 401 | `CSGO_SKINS_SYNC_KEY` errada | Alinhar site + VPS |
| Arquivo vazio | Ninguém com skin equipada | Equipar no site e re-sync |
| Skin não muda no jogo | PTaH / Guidelines | Ver `WEAPONS-PLUGIN.md` |
| Steam ID não bate | Formato `STEAM_X:Y:Z` | Site usa Steam2; plugin lê AuthId_Steam2 |
| `!ws` funciona, bridge não | Plugin não carregado | `sm plugins list`, compilar `.smx` |

---

## 8. v1 — fora do escopo

- Luvas (`GLOVES`) e agentes (`AGENT`) no bridge automático
- Modelo de faca (só paintkit na faca atual)
- Sync em tempo real (usa cron + reload periódico)
