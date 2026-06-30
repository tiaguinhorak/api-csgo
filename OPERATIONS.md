# Clutch Clube — Runbook de Operações (VPS + Site + CS:GO)

Documento de referência para **humanos e IAs** que operam o stack Clutch: site (Hostinger), `api-csgo` (VPS do jogo) e servidor dedicado CS:GO (SourceMod).

**Copia local:** também em `CsgoPage/OPERATIONS.md` no workspace de desenvolvimento.

**Leia também:**

| Doc | Conteúdo |
|-----|----------|
| `api-csgo/ADMIN-COMANDOS.md` | Comandos admin SourceMod detalhados |
| `api-csgo/SKINS-BRIDGE.md` | Arquitetura skins site ↔ SQLite ↔ plugin |
| `api-csgo/WEAPONS-PLUGIN.md` | `weapons.smx`, PTaH, `weapons_english.cfg` |
| `site/GLOBAL.md` | UI, i18n, tema do site |
| `site/api REST CSGO.md` | API partidas/veto (espelho do README api-csgo) |

---

## 1. Visão geral

```
Jogador equipa skin no site (Hostinger)
    → Postgres (CsgoPlayerSkin, equippedT / equippedCT)
    → POST api-csgo /api/csgo/skins/player-sync (VPS)
    → SQLite sourcemod-local.sq3 (tabelas weapons, gloves, clutch_team_loadout)
    → RCON sm_clutch_applyskins
    → Plugins: z_clutch_gloves.smx → z_clutch_skins_bridge.smx → weapons.smx
```

| Componente | Onde roda | Repo GitHub |
|------------|-----------|-------------|
| Site Next.js | Hostinger | `tiaguinhorak/site` |
| api-csgo | VPS `188.220.168.233` (usuário `csgo`) | `tiaguinhorak/api-csgo` |
| srcds CS:GO | Mesma VPS, screen `csgo-clutch-#1` | — |

**Usuário VPS:** `csgo`  
**Porta do jogo:** `27015` (UDP)  
**Porta api-csgo:** `3001` (não 3000 — ver `PORT` no `.env`)  
**Site público:** `https://clutchclube.com.br`

---

## 2. Paths importantes na VPS

```text
/home/csgo/api-csgo/                          # repo api-csgo (git pull aqui)
/home/csgo/server/                            # CSGO_SERVER_DIR
/home/csgo/server/csgo/                     # CSGO_ROOT padrão dos scripts
/home/csgo/server/csgo/motd.txt             # URL do botão "SITE DO SERVIDOR" no scoreboard
/home/csgo/server/csgo/cfg/server.cfg
/home/csgo/server/csgo/cfg/clutch_server_branding.cfg
/home/csgo/server/csgo/addons/sourcemod/plugins/
  z_clutch_gloves.smx
  z_clutch_skins_bridge.smx
  weapons.smx
/home/csgo/server/csgo/addons/sourcemod/configs/
  admins_simple.ini
  core.cfg
  admin_overrides.cfg          # inclui overrides Clutch (!ws só admin)
/home/csgo/server/csgo/addons/sourcemod/data/sqlite/
  sourcemod-local.sq3          # WEAPONS_DB_PATH — loadouts + !ws
/home/csgo/server/csgo/addons/sourcemod/logs/
/home/csgo/server/csgo/cfg/sourcemod/
  weapons_english.cfg          # paintkits reconhecidos por weapons.smx
```

Scripts detectam o diretório **live** do `srcds` via `/proc` quando o servidor está rodando — se instalou no path errado, use `CSGO_ROOT=... bash scripts/install-clutch-skins-bridge.sh`.

---

## 3. Variáveis de ambiente (alinhar site ↔ VPS)

### Site (`site/.env` na Hostinger)

```env
APP_URL=https://clutchclube.com.br
CSGO_API_URL=http://188.220.168.233:3001
CSGO_SKINS_SYNC_KEY=<mesma-chave-na-vps>
INVENTORY_ALL_SKINS=true
CATALOG_ALLOWLIST_SOURCE=site-db
```

### api-csgo (`~/api-csgo/.env` na VPS)

```env
PORT=3001
SITE_ORIGIN=https://clutchclube.com.br
CSGO_SKINS_SYNC_KEY=<mesma-chave-do-site>
CLUTCH_SITE_URL=https://clutchclube.com.br
WS_ALLOWLIST_SOURCE=site-db
WEAPONS_DB_PATH=/home/csgo/server/csgo/addons/sourcemod/data/sqlite/sourcemod-local.sq3
CSGO_SERVER_HOST=127.0.0.1
CSGO_RCON_PORT=27015
CSGO_RCON_PASSWORD=<senha>
CLUTCH_CS_SCREEN=csgo-clutch-#1
```

**Regra:** `CSGO_SKINS_SYNC_KEY` deve ser **idêntica** no site e na VPS. `CLUTCH_SITE_URL` / `APP_URL` devem apontar ao domínio real do site (sem barra final).

---

## 4. Mudar URL do site (scoreboard, sync, CORS)

### 4.1 Botão "SITE DO SERVIDOR" no scoreboard (CS:GO)

**CS:GO NÃO tem** os convars `host_url` nem `sv_motd` — eles retornam `Unknown command`.

O link do scoreboard vem do arquivo **`motd.txt`** na pasta `csgo`:

```bash
cd ~/api-csgo
git pull
./scripts/ensure-clutch-server-branding.sh
```

Isso escreve `CLUTCH_SITE_URL` em `/home/csgo/server/csgo/motd.txt` e garante `exec clutch_server_branding.cfg` no `server.cfg`.

**Aplicar no jogo:** trocar de mapa ou reiniciar srcds:

```text
changelevel de_dust2
```

Verificar:

```bash
cat /home/csgo/server/csgo/motd.txt
```

### 4.2 Site + API (domínio, sync de skins, catálogo)

1. **Site Hostinger:** `APP_URL=https://novo-dominio.com.br`
2. **VPS api-csgo:** `SITE_ORIGIN` e `CLUTCH_SITE_URL` com o mesmo domínio
3. **Reiniciar API:** `pm2 restart api-csgo --update-env`
4. **Rodar branding:** `./scripts/ensure-clutch-server-branding.sh`
5. **Site Hostinger:** `CSGO_API_URL` continua IP público da VPS + porta (`http://IP:3001`)

---

## 5. Deploy na VPS (um comando)

```bash
cd ~/api-csgo
./deploy.sh
```

Equivalente: `npm run deploy` ou `./scripts/deploy-vps.sh`

O deploy faz: `git pull` → `npm build` → `pm2` → sync allowlist Steam → sync `weapons_english.cfg` → branding `motd.txt` → instala **todos** os plugins (bridge, gloves, gate, match tracker, stickers) → reload no screen.

**Opções:**

```bash
./deploy.sh --skip-pull
./deploy.sh --skip-ingame    # CS offline
./deploy.sh --skip-plugin    # só API + syncs
```

**Deploy manual (equivalente):**

```bash
cd ~/api-csgo && git pull
npm run build
pm2 restart api-csgo --update-env
chmod +x scripts/*.sh deploy.sh
./scripts/sync-steam-allowlist.sh
./scripts/ensure-clutch-server-branding.sh
./scripts/install-clutch-skins-bridge.sh
./scripts/install-clutch-platform-gate.sh
./scripts/install-clutch-match-tracker.sh
bash scripts/install-csgo-weaponstickers.sh
./scripts/reload-clutch-skins-ingame.sh
```

**Após mudar `.env`:** sempre `pm2 restart api-csgo --update-env`.

**Health check:**

```bash
curl -s http://127.0.0.1:3001/health
```

---

## 5b. Stickers no jogo (CSGO_WeaponStickers)

Plugin AlliedMods: [CSGO Weapon Stickers](https://forums.alliedmods.net/showthread.php?t=327078). O repo já instala o fork **z1ntex v1.3.6** + **eItems** + **sm-ripext** + **PTaH**.

**Na VPS (como `csgo`):**

```bash
cd ~/api-csgo && git pull
sudo apt install -y p7zip-full   # extrair .rar do release z1ntex
bash scripts/install-csgo-weaponstickers.sh
# se .smx quebrado: WEAPONSTICKERS_FORCE=1 bash scripts/install-csgo-weaponstickers.sh
```

**Reiniciar srcds** (extensions `rip.ext` só carregam no boot):

```bash
screen -r csgo-clutch-#1
# Ctrl+C no srcds, subir de novo — ou changelevel
```

**Console do servidor:**

```text
sm exts list
sm plugins load eItems
sm plugins load csgo_weaponstickers
sm plugins list | grep -iE 'eitems|weaponstickers'
```

**Sync site → SQLite do plugin** (api-csgo `.env`):

- `CLUTCH_SITE_URL` = URL pública do Next (dev: ngrok em `TUNNEL_URL`)
- `CSGO_SKINS_SYNC_KEY` = **igual** ao `site/.env`

```bash
cd ~/api-csgo
bash scripts/ensure-clutch-site-env.sh
curl -s -X POST http://127.0.0.1:3001/api/csgo/stickers/sync-from-site \
  -H "x-skins-sync-key: $CSGO_SKINS_SYNC_KEY"
pm2 restart api-csgo --update-env
```

DB lido pelo plugin: `/home/csgo/server/csgo/addons/sourcemod/data/sqlite/csgo_weaponstickers.sq3`

Stickers aplicam no **spawn** (cfg `sm_weaponstickers_updateviewmodel 1`).

**Com `z_clutch_skins_bridge` (v3.8.8+):** o bridge reaplica stickers depois da skin custom (paintkit), porque o plugin de stickers roda no `GiveNamedItem` e a skin do bridge sobrescreve os atributos. Após `git pull`, reinstale o bridge:

```bash
bash scripts/install-clutch-skins-bridge.sh
sm plugins reload z_clutch_skins_bridge
```

O instalador do bridge adiciona `csgo_weaponstickers` em `addons/sourcemod/configs/databases.cfg` se faltar. Se ainda falhar, v3.8.9+ abre `data/sqlite/csgo_weaponstickers.sq3` direto.

**Teste in-game:** stickers só em **armas de fogo** (não faca). Equipe AK com stickers, pegue a AK, inspecione com **F**. Com `clutch_skins_debug 1` no console: log `[Clutch] Applied stickers on weapon_ak47`.

Verificar DB (AK = `weaponindex` 7):

```bash
sqlite3 /home/csgo/server/csgo/addons/sourcemod/data/sqlite/csgo_weaponstickers.sq3 \
  "SELECT steamid, weaponindex, slot0, slot1, slot2 FROM weaponstickers1 WHERE weaponindex=7;"
```

## 6. Console do servidor CS (screen)

```bash
screen -r csgo-clutch-#1
```

Sair **sem matar** o servidor: `Ctrl+A`, depois `D`.

Listar sessões:

```bash
screen -ls
ss -ulnp | grep 27015
```

### Reiniciar srcds (limpo)

```bash
screen -ls | grep csgo-clutch | awk '{print $1}' | while read s; do screen -S "$s" -X quit; done
fuser -k 27015/udp 2>/dev/null
pkill -u csgo -f srcds_linux 2>/dev/null
sleep 3

cd /home/csgo/server
screen -dmS csgo-clutch-#1 ./srcds_run -tickrate 128 -game csgo -console -usercon \
  -port 27015 +game_type 0 +game_mode 1 +map de_dust2 \
  +sv_setsteamaccount "GSLT_TOKEN" \
  +rcon_password "RCON_SENHA" -maxplayers 10
```

(Preferir `scripts/start-csgo-screen.sh` se configurado no repo.)

---

## 7. Plugins — recarregar e ordem

### Plugins Clutch (obrigatórios)

| Plugin | Função |
|--------|--------|
| `weapons.smx` | Modelos de faca, paintkit base (!ws kgns) |
| `z_clutch_gloves.smx` | Luvas do SQLite |
| `z_clutch_skins_bridge.smx` | Aplica loadout web (T/CT) no spawn |

**Não usar** `gloves.smx` (kgns) junto — o install script move para `plugins/disabled/`.

### Recarregar via script (SSH)

```bash
cd ~/api-csgo && ./scripts/reload-clutch-skins-ingame.sh
```

### Recarregar manual (console do servidor — uma linha por vez)

```text
sm plugins reload weapons
sm plugins unload z_clutch_skins_bridge
sm plugins load z_clutch_gloves
sm plugins load z_clutch_skins_bridge
clutch_skins_debug 1
sm_clutch_applyskins
```

### Comandos admin de skins

```text
sm_clutch_applyskins      # reaplica skins do DB para todos online
sm_reloadclutchskins      # alias relacionado ao bridge
sm_clutch_gloves_refresh  # refresh cache de luvas
```

### Verificar versão instalada

```text
sm plugins info z_clutch_skins_bridge
sm plugins info z_clutch_gloves
sm plugins info weapons
```

Versão esperada do bridge: ver `#define PLUGIN_VERSION` em `sourcemod/clutch_skins_bridge.sp` (ex.: `3.7.5`).

### Instalar / recompilar plugin

```bash
cd ~/api-csgo && git pull
./scripts/install-clutch-skins-bridge.sh
```

Output: `z_clutch_skins_bridge.smx` (não `clutch_skins_bridge.smx`).

### `!ws` / `!knife` — só admins

Jogadores normais são bloqueados no chat (`!ws`, `!knife`, etc.) — equipar só pelo site.

Admins com flag `b` em `admins_simple.ini` mantêm `!ws`. Overrides em `admin_overrides_clutch.cfg`.

---

## 8. Skins — sync e troubleshooting

### Fluxo automático (normal)

Equip no site → `POST /api/csgo/skins/player-sync` → SQLite → RCON `sm_clutch_applyskins`.

### Re-sync em massa (Postgres → SQLite)

```bash
cd ~/api-csgo
./scripts/sync-loadouts-from-site.sh
# ou sync por team loadout:
./scripts/sync-team-loadouts-from-site.sh
```

### Catálogo admin não aparece in-game

Skins adicionadas **só no painel admin** precisam de **3 passos** (adicionar ao catálogo ≠ equipar ≠ aplicar no jogo):

1. **Catálogo** — skin `enabled` no admin (dispara sync de `weapons_english.cfg` se o site alcança a VPS).
2. **Equipar no site** — inventário → aba T ou CT → equipar a skin (dispara `player-sync` → SQLite).
3. **VPS** — cfg + reload do plugin `weapons` (paintkits novos só existem para `weapons.smx` após reload).

```bash
cd ~/api-csgo
git pull
npm run build && pm2 restart api-csgo --update-env
bash scripts/sync-weapons-cfg-from-site.sh
```

No console CS (ou `./scripts/reload-clutch-skins-ingame.sh`):

```text
sm plugins reload weapons
sm_clutch_applyskins
```

Respawn ou `mp_restartgame 1`. Confira aba **T/CT** certa (AK só T, M4 só CT).

**Verificar** que a paintkit está no cfg:

```bash
grep "PAINTKIT_NUMERO" /home/csgo/server/csgo/addons/sourcemod/configs/weapons/weapons_english.cfg
```

**Verificar** allowlist do site (VPS → Hostinger):

```bash
curl -s -H "x-skins-sync-key: $CSGO_SKINS_SYNC_KEY" \
  "https://clutchclube.com.br/api/csgo/catalog/allowlist" | head
```

Requer `WS_ALLOWLIST_SOURCE=site-db`, `CLUTCH_SITE_URL` e `CSGO_SKINS_SYNC_KEY` na VPS.

### `core.cfg` (obrigatório para skins)

`/home/csgo/server/csgo/addons/sourcemod/configs/core.cfg`:

```text
"SteamAuthstringValidation" "no"
"FollowCSGOServerGuidelines" "no"
```

**Reinício completo do srcds** após alterar.

### Diagnóstico

```bash
cd ~/api-csgo
./scripts/verify-clutch-skins-bridge.sh
./scripts/diagnose-steam-and-skins.sh
./scripts/diagnose-site-loadouts.sh
./scripts/query-gloves-db.sh STEAM_1:0:XXXXX
```

---

## 9. Ban e unban

### 9.1 No servidor (SourceMod) — ban de jogo

Flag `d` em `admins_simple.ini`.

```text
sm_ban #1 60 toxic
sm_ban STEAM_1:0:12345678 0 cheat          # 0 = permanente
sm_addban STEAM_1:0:12345678 0 cheat        # jogador offline
sm_unban STEAM_1:0:12345678
sm_banlist
sm_kick nome motivo
```

Steam ID: comando `status` no console com o jogador conectado.

### 9.2 No site (conta Clutch)

Banimentos de **conta do site** (login Steam OpenID, ranked, etc.) são geridos no **painel admin** do site (`/admin` → usuários → punições). Isso é separado do ban SourceMod.

Um jogador banido no site não loga; ban SM impede conexão ao servidor de jogo.

### 9.3 Dar admin a alguém

Editar `/home/csgo/server/csgo/addons/sourcemod/configs/admins_simple.ini`:

```text
"STEAM_1:0:12345678" "z"
```

Aplicar:

```text
sm_reloadadmins
```

Jogador deve **sair e entrar** no servidor. Teste: `sm_who`.

**Formato correto Steam:** 2 campos (`"steamid" "flags"`). Não usar 3 campos com Steam ID.

---

## 10. PM2 (api-csgo)

```bash
pm2 list
pm2 restart api-csgo --update-env
pm2 logs api-csgo --lines 50
```

Se API responde build antigo:

```bash
cd ~/api-csgo && ./scripts/pm2-recover.sh
./scripts/verify-api-running-build.sh
```

Porta errada / processo zumbi:

```bash
./scripts/diagnose-port-3000.sh
./scripts/find-free-api-port.sh
```

---

## 11. Catálogo de scripts (`api-csgo/scripts/`)

| Script | Uso |
|--------|-----|
| `deploy.sh` | Deploy completo (um comando) |
| `install-clutch-skins-bridge.sh` | Compila e instala plugins Clutch |
| `reload-clutch-skins-ingame.sh` | Reload plugins via screen |
| `ensure-clutch-server-branding.sh` | `motd.txt` + site no scoreboard |
| `sync-weapons-cfg-from-site.sh` | `weapons_english.cfg` do catálogo site |
| `sync-loadouts-from-site.sh` | Re-sync loadouts Postgres → SQLite |
| `sync-team-loadouts-from-site.sh` | Re-sync loadouts T/CT |
| `verify-clutch-skins-bridge.sh` | Diagnóstico plugin |
| `patch-weapons-reload-native.sh` | Patch `Weapons_ReloadClientData` |
| `start-csgo-screen.sh` | Inicia srcds em screen |
| `start-csgo-instance.sh` | Segunda instância srcds (porta/screen próprios) |
| `install-netdata.sh` | Monitoramento VPS (CPU/RAM/disco) — painel `:19999` |
| `pm2-ensure-api-csgo.sh` | Garante processo PM2 correto |
| `test-gloves-sync.sh` | Testa sync de luvas por Steam ID |

Se `Permission denied` em script: `chmod +x scripts/*.sh` ou `bash scripts/nome.sh`.

---

## 12. Mapas e servidor (rápido)

```text
sm_map de_mirage
changelevel de_dust2
mp_restartgame 1
mp_warmup_end
sm_cvar sv_password
sm_password off
```

---

## 13. Logs

```bash
tail -50 /home/csgo/server/csgo/addons/sourcemod/logs/errors_*.log
pm2 logs api-csgo --lines 100
```

---

## 14. Checklist rápido para IAs

| Problema | Verificar |
|----------|-----------|
| Skin não muda in-game | `sm plugins info z_clutch_skins_bridge`, `sm_clutch_applyskins`, `core.cfg` Guidelines |
| Só luvas funcionam | Ordem load: gloves → bridge; team loadout STEAM format |
| AK no CT | Site `loadout-team.ts` + plugin `ClutchWeaponAllowedForTeam` |
| Admin skin não no jogo | `sync-weapons-cfg-from-site.sh` + reload `weapons` |
| Site não empurra loadout | `CSGO_API_URL` porta 3001, `CSGO_SKINS_SYNC_KEY` igual |
| Scoreboard link errado | `motd.txt` (não `host_url`); `changelevel` após editar |
| Plugin não compila | `git pull`, versão bridge, erro no `spcomp` |
| `!ws` para players | Esperado — usar site; admin mantém `!ws` |
| API 401 no sync | `CSGO_SKINS_SYNC_KEY` |
| Admin SM não funciona | `admins_simple.ini` 2 campos, `sm_reloadadmins`, reconnect |

---

## 16. Monitoramento (Netdata)

Na VPS (root):

```bash
cd ~/api-csgo && git pull
sudo bash scripts/install-netdata.sh
```

Painel: `http://IP_DA_VPS:19999` — restrinja no firewall ao seu IP admin.

Opcional — [Netdata Cloud](https://app.netdata.cloud) (alertas + várias VPS):

```bash
export NETDATA_CLAIM_TOKEN="seu_token"
export NETDATA_CLAIM_ROOMS="room_id"
sudo -E bash scripts/install-netdata.sh
```

---

## 15. O que NÃO usar (legado)

| Legado | Usar em vez de |
|--------|----------------|
| `clutch_skins.txt` | `player-sync` / SQLite |
| `sync-clutch-skins.sh` | `sync-loadouts-from-site.sh` |
| `POST /api/csgo/skins/push` | `player-sync` |
| `host_url` / `sv_motd` no CS:GO | `motd.txt` |
| `gloves.smx` (kgns) | `z_clutch_gloves.smx` |
| `clutch_skins_bridge.smx` | `z_clutch_skins_bridge.smx` |
| Porta 3000 na VPS | `3001` (ver `.env`) |

---

*Última revisão operacional: jun/2026 — plugin bridge ~3.7.5, loadouts T/CT, `motd.txt` para site no scoreboard.*
