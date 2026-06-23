# Comandos de Admin — CS:GO + SourceMod (VPS Clutch)

> **Runbook completo (deploy, site URL, skins, paths):** `OPERATIONS.md`

Guia para administrar o servidor dedicado (`screen`, RCON, SourceMod).

---

## Flags de admin (SourceMod)

| Flag | Permissão |
|------|-----------|
| `z` | **Root** — acesso total |
| `b` | Admin genérico (slot reservado, básico) |
| `c` | Kick |
| `d` | Ban / unban |
| `e` | Slay / slap |
| `f` | Mudar mapa |
| `g` | Alterar cvars sensíveis |
| `h` | Editar configs SM |
| `i` | Chat admin (`csay`, `hsay`) |
| `j` | Votações admin |
| `k` | Senha do servidor |
| `l` | RCON |
| `m` | Cheats (`noclip`, etc.) |
| `n`–`s` | Custom (depende do plugin) |

Combinações comuns em `admins_simple.ini`:

```text
"z"          → root (tudo)
"99:z"       → root + imunidade 99 (só IP; ver formato abaixo)
"bce"        → generic + kick + unban
"bef"        → generic + kick + mapa
```

---

## Dar admin a alguém

Arquivo: `/home/csgo/server/csgo/addons/sourcemod/configs/admins_simple.ini`

### Por Steam ID (recomendado)

**Só 2 campos** — sem nome/senha extra:

```text
"STEAM_1:0:12345678" "z"
```

Steam ID: comando `status` no console do servidor com o jogador conectado.

### Por IP (teste rápido)

```text
"!201.15.45.68" "z"
```

O `!` antes do IP é obrigatório.

### Formato completo (opcional)

```text
"STEAM_1:0:12345678" "" "99" "z" "NomeAdmin"
```

| Campo | Descrição |
|-------|-----------|
| 1 | Steam ID |
| 2 | Senha (vazio = sem senha) |
| 3 | Imunidade |
| 4 | Flags |
| 5 | Nome (opcional) |

**Não use** 3 campos com Steam ID (`"id" "99:z" "nome"`) — o 2º vira senha e o admin não funciona.

### Aplicar

No console do servidor (`screen -r csgo-clutch-#1`):

```text
sm_reloadadmins
```

Jogador: **sair e entrar** no servidor. Teste: `sm_who` e `sm_admin`.

---

## `core.cfg` (skins + admin com Steam instável)

Arquivo: `/home/csgo/server/csgo/addons/sourcemod/configs/core.cfg`

```text
"SteamAuthstringValidation" "no"
"FollowCSGOServerGuidelines" "no"
```

Reinício **completo** do `srcds` após alterar.

---

## Onde rodar cada comando

| Lugar | Exemplos |
|-------|----------|
| **Console do servidor** (`screen -r`) | `status`, `sm_reloadadmins`, `mp_restartgame 1` |
| **Console do jogo** (admin) | `sm_admin`, `sm_kick`, `sm_map` |
| **Chat** (admin) | `!admin` (se plugin mapeia), `!kick` |
| **SSH** | `nano`, reiniciar screen, `df`, logs |

`meta list` e `sm plugins list` → só no **console do servidor** ou jogo com permissão.

---

## Menu principal

| Comando | Onde | Função |
|---------|------|--------|
| `sm_admin` | Jogo / console | Menu admin SourceMod |
| `sm_who` | Jogo / servidor | Lista jogadores e flags |
| `sm_reloadadmins` | **Servidor** | Recarrega `admins_simple.ini` |

---

## Jogadores

| Comando | Flag típica | Função |
|---------|-------------|--------|
| `sm_kick <nome\|#id> [motivo]` | `c` | Kick |
| `sm_ban <nome\|#id> <minutos\|0> [motivo]` | `d` | Ban temporário (`0` = permanente) |
| `sm_unban <steamid\|ip>` | `d` | Remover ban |
| `sm_addban <steamid\|ip> <minutos> [motivo]` | `d` | Ban sem jogador online |
| `sm_banlist` | `d` | Lista bans |

Exemplos:

```text
sm_kick ichi lag
sm_ban #1 60 toxic
sm_ban STEAM_1:0:12345678 0 cheat
sm_unban STEAM_1:0:12345678
```

---

## Mapas

| Comando | Flag | Função |
|---------|------|--------|
| `sm_map <mapa>` | `f` | Troca mapa |
| `sm_changemap <mapa>` | `f` | Igual `sm_map` |
| `sm_voteban`, `sm_votemap` | `j` | Votações (Fun Votes) |

Exemplos:

```text
sm_map de_mirage
sm_map de_dust2
```

No servidor (sem SourceMod):

```text
changelevel de_mirage
mp_restartgame 1
```

---

## Chat / anúncios

| Comando | Flag | Função |
|---------|------|--------|
| `sm_csay <texto>` | `i` | Mensagem central na tela |
| `sm_hsay <texto>` | `i` | Mensagem no HUD |
| `sm_psay <jogador> <texto>` | `i` | Mensagem privada para um jogador |
| `sm_msay <texto>` | `i` | Menu com texto |

---

## Punição / diversão (Fun Commands)

Requer plugin **Fun Commands** (`funcommands.smx`).

| Comando | Flag | Função |
|---------|------|--------|
| `sm_slay <jogador>` | `e` | Matar |
| `sm_slap <jogador> [dano]` | `e` | Slap |
| `sm_beacon <jogador> [0\|1]` | `e` | Beacon |
| `sm_burn <jogador> [segundos]` | `e` | Queimar |
| `sm_freeze <jogador> [segundos]` | `e` | Congelar |
| `sm_noclip <jogador>` | `e` + cheats | Noclip |
| `sm_gravity <jogador> [valor]` | `e` | Gravidade (`1.0` normal) |
| `sm_blind <jogador> [0-255]` | `e` | Escurecer visão |
| `sm_drug <jogador> [0\|1]` | `e` | Efeito “drug” |

---

## Servidor / cvars

| Comando | Flag | Função |
|---------|------|--------|
| `sm_cvar <cvar> [valor]` | `g` | Ler/alterar cvar |
| `sm_rcon <comando>` | `l` | Enviar comando RCON |
| `sm_password <senha\|off>` | `k` | Senha do servidor |
| `sm_execcfg <arquivo>` | `h` | Executar cfg |

Exemplos:

```text
sm_cvar sv_password
sm_password clutch123
sm_password off
sm_rcon status
```

Cvars úteis no servidor:

```text
sv_cheats 1
sv_pure 0
mp_restartgame 1
mp_warmup_end
```

---

## SourceMod / plugins

| Comando | Quem | Função |
|---------|------|--------|
| `sm plugins list` | Admin | Lista plugins |
| `sm plugins reload <nome>` | Root | Recarrega plugin |
| `sm plugins unload/load <nome>` | Root | Carrega/descarrega |
| `meta list` | Admin | Extensões (PTaH, etc.) |
| `meta reload <id>` | Root | Recarrega extensão |
| `sm version` | Todos | Versão SourceMod |

Exemplos:

```text
sm plugins list
sm plugins reload weapons
meta list
```

---

## Skins (!ws) — admin

| Comando | Função |
|---------|--------|
| `!ws` / `sm_ws` | Menu skins de armas |
| `!knife` / `sm_knife` | Menu faca |
| `sm plugins reload weapons` | Recarrega Weapons & Knives |

Ver também: `WEAPONS-PLUGIN.md`

---

## Gerenciar servidor (VPS / screen)

### Entrar no console do servidor

```bash
screen -r csgo-clutch-#1
```

Sair **sem matar** o servidor: `Ctrl+A`, depois `D`.

### Reiniciar CS:GO (limpo)

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

### Ver processo e porta

```bash
screen -ls
ss -ulnp | grep 27015
ps aux | grep srcds_linux | grep -v grep
```

### Logs

```bash
tail -50 /home/csgo/server/csgo/addons/sourcemod/logs/errors_*.log
```

---

## RCON (fora do jogo)

Com ferramenta RCON ou `rcon` no cliente (se configurado):

```text
rcon_password SUA_RCON
rcon status
rcon mp_restartgame 1
rcon sm_reloadadmins
```

RCON **não** substitui flags SourceMod para `sm_admin` — use `admins_simple.ini` para isso.

---

## Checklist admin não funciona

1. `admins_simple.ini` — Steam ID certo, **2 campos** para Steam
2. `sm_reloadadmins` no servidor
3. Reconectar ao servidor
4. `sm_who` — deve mostrar flags
5. `core.cfg` — `SteamAuthstringValidation` `"no"` se Steam falha
6. Reiniciar `srcds` após mudar `core.cfg`

---

---

## Skins (100% API + banco — sem arquivos na VPS)

### Fluxo normal (automático)

1. Jogador equipa no site → Postgres (`CsgoPlayerSkin`)
2. Site chama `POST http://VPS:3000/api/csgo/skins/player-sync` (JSON)
3. api-csgo grava no SQLite do `!ws` e envia `sm_clutch_applyskins`
4. Plugin lê o DB e aplica paint no jogo

Não precisa de `clutch_skins.txt`, SCP, nem editar configs de skin na VPS.

### Re-sync em massa (opcional, cron)

Se o servidor reiniciou ou algo ficou desincronizado:

```bash
cd ~/api-csgo
./scripts/sync-loadouts-from-site.sh
```

Isso chama `POST /api/csgo/skins/sync-from-site` — site API lê Postgres → api-csgo → SQLite.

Requer no `api-csgo/.env`:

```env
CLUTCH_SITE_URL=https://clutchclube.com
CSGO_SKINS_SYNC_KEY=mesma-chave-do-site
```

### Comandos in-game (admin)

```text
sm_clutch_applyskins     # reaplica skins do DB para todos online
sm_reloadclutchskins     # igual (lê weapons SQLite)
clutch_skins_debug 1     # logs de paintkit no SourceMod log
```

### Deploy completo (pull + api + plugin + reload)

Um único comando na VPS (usuário `csgo`):

```bash
cd ~/api-csgo && ./scripts/deploy-vps.sh
```

Isso faz: `git pull` → `npm install` → `npm run build` → `pm2 restart` → compila/instala `z_clutch_skins_bridge` → recarrega plugin no screen do CS.

Atalho equivalente: `./scripts/deploy-skins-v3.sh`

Opções:

```bash
./scripts/deploy-vps.sh --skip-pull      # sem git pull
./scripts/deploy-vps.sh --skip-ingame  # sem reload no screen (CS offline)
./scripts/deploy-vps.sh --skip-plugin    # só api (build + pm2)
```

### Instalar plugin bridge (primeira vez ou manual)

```bash
cd ~/api-csgo && git pull
CSGO_ROOT=/home/csgo/server/csgo bash scripts/install-clutch-skins-bridge.sh
CSGO_ROOT=/home/csgo/server/csgo bash scripts/patch-weapons-reload-native.sh
```

### O que NÃO usar (legado)

| Legado | Substituir por |
|--------|----------------|
| `sync-clutch-skins.sh` | `sync-loadouts-from-site.sh` |
| `clutch_skins.txt` | `player-sync` / `sync-from-site` |
| Editar `weapons_english.cfg` para catálogo | `WS_ALLOWLIST_SOURCE=github` |

---

## Paths úteis na VPS

```text
/home/csgo/server/csgo/addons/sourcemod/configs/admins_simple.ini
/home/csgo/server/csgo/addons/sourcemod/configs/core.cfg
/home/csgo/server/csgo/addons/sourcemod/logs/
/home/csgo/server/csgo/cfg/server.cfg
/home/csgo/server/csgo/cfg/sourcemod/
```

---

## Links

- SourceMod admin flags: https://wiki.alliedmods.net/Adding_Admins_(SourceMod)
- SourceMod commands: https://wiki.alliedmods.net/Admin_Commands_(SourceMod)
