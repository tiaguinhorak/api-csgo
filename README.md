# API CS:GO

> **Runbook VPS (deploy, motd, plugins, unban, env):** `OPERATIONS.md`

API REST para gerenciamento de servidores CS:GO, partidas competitivas com sistema de veto e skins. Desenvolvida para integrar com plataformas web competitivas.

## Stack

- Node.js + TypeScript
- Express
- RCON (`srcds-rcon`) para comunicação com servidor CS:GO
- SSH2 para gerenciamento remoto de servidores Linux
- PM2 para deploy em produção

## Autenticação

Todas as rotas (exceto `/health`) exigem o header:

```
x-api-key: suachaveapi
```

---

## Sumário

1. [Health Check](#1-health-check)
2. [Servidores](#2-servidores)
3. [Partidas](#3-partidas)
4. [Sistema de Veto](#4-sistema-de-veto)
5. [Skins](#5-skins)
6. [Deploy](#6-deploy)

---

## 1. Health Check

```
GET /health
```

Verifica se a API está rodando.

**Resposta:**
```json
{
  "status": "ok",
  "timestamp": "2026-06-17T23:00:00.000Z"
}
```

---

## 2. Servidores

### 2.1 Listar servidores

```
GET /api/servers?status=online
```

Query opcional: `status` = `online` | `offline` | `busy`

**Resposta:**
```json
[
  {
    "id": "dcceeb05-5e8f-450c-a9aa-c7444a019c92",
    "name": "Servidor CS 1",
    "host": "127.0.0.1",
    "sshPort": 22,
    "rconPort": 27015,
    "csgoDir": "/home/csgo/server",
    "screenSession": "csgo-servidor-cs-1",
    "status": "online",
    "port": 27015,
    "tickrate": 128
  }
]
```

### 2.2 Detalhes do servidor

```
GET /api/servers/:id
```

### 2.3 Registrar servidor

```
POST /api/servers
```

**Body:**
```json
{
  "name": "Servidor CS 1",
  "host": "127.0.0.1",
  "sshUser": "csgo",
  "sshPassword": "senha",
  "rconPort": 27015,
  "rconPassword": "suasenha",
  "csgoDir": "/home/csgo/server",
  "port": 27015,
  "tickrate": 128
}
```

> Para servidor na mesma máquina, **não** enviar `sshUser`/`sshPassword` — a API executa os comandos localmente.

### 2.4 Iniciar servidor

```
POST /api/servers/:id/start
```

**Body (opcional):**
```json
{
  "map": "de_dust2",
  "password": "senha_do_servidor"
}
```

A API cria um screen com o CS:GO rodando e retorna o servidor com `status: "online"`.

### 2.5 Parar servidor

```
POST /api/servers/:id/stop
```

Mata o screen do servidor.

### 2.6 Reiniciar servidor

```
POST /api/servers/:id/restart
```

**Body (opcional):**
```json
{
  "map": "de_mirage"
}
```

### 2.7 Status do servidor

```
GET /api/servers/:id/status
```

Verifica se o processo está rodando e testa a conexão RCON.

### 2.8 Enviar comando RCON

```
POST /api/servers/:id/rcon
```

**Body:**
```json
{
  "command": "status"
}
```

**Resposta:**
```json
{
  "result": "hostname: ...\nversion : ...\nos      :  Linux\n..."
}
```

### 2.9 Remover servidor

```
DELETE /api/servers/:id
```

---

## 3. Partidas

### 3.1 Criar partida

```
POST /api/matches
```

**Body:**
```json
{
  "roomId": "sala-123",
  "teamA": {
    "name": "Team Liquid",
    "players": [
      { "steamId": "STEAM_1:0:12345", "name": "player1" },
      { "steamId": "STEAM_1:0:67890", "name": "player2" }
    ]
  },
  "teamB": {
    "name": "FURIA",
    "players": [
      { "steamId": "STEAM_1:1:11111", "name": "player3" },
      { "steamId": "STEAM_1:1:22222", "name": "player4" }
    ]
  },
  "mapPool": ["de_mirage", "de_inferno", "de_dust2", "de_nuke", "de_overpass", "de_ancient", "de_anubis"],
  "config": {
    "gameType": 0,
    "gameMode": 1,
    "tickrate": 128,
    "maxRounds": 30,
    "overtimeRounds": 6
  }
}
```

### 3.2 Listar partidas

```
GET /api/matches?status=veto
```

Query opcional: `status` = `waiting_players` | `veto` | `ready` | `live` | `finished` | `cancelled`

### 3.3 Detalhes da partida

```
GET /api/matches/:id
```

### 3.4 Iniciar veto

```
POST /api/matches/:id/start-veto
```

Muda o status para `veto` e inicia o fluxo de 8 passos:

| Passo | Time | Ação |
|-------|------|------|
| 1 | B | Ban |
| 2 | A | Ban |
| 3 | B | Ban |
| 4 | A | Ban |
| 5 | A | Pick |
| 6 | B | Pick |
| 7 | A | Ban |
| 8 | B | Ban |
| - | - | Decider (random) |

### 3.5 Processar veto

```
POST /api/matches/:id/veto
```

**Body:**
```json
{
  "team": "A",
  "action": "ban",
  "map": "de_mirage"
}
```

Retorna a partida atualizada com o histórico do veto.

### 3.6 Estado do veto

```
GET /api/matches/:id/veto-state
```

**Resposta:**
```json
{
  "history": [
    { "team": "B", "action": "ban", "map": "de_mirage", "timestamp": "..." }
  ],
  "currentStep": {
    "phase": "ban_b",
    "team": "A",
    "action": "ban",
    "availableMaps": ["de_inferno", "de_dust2", "..."]
  },
  "availableMaps": ["de_inferno", "de_dust2", "..."],
  "isComplete": false
}
```

### 3.7 Iniciar partida (no servidor)

```
POST /api/matches/:id/start
```

**Body:**
```json
{
  "serverId": "dcceeb05-..."
}
```

Se `serverId` não for informado, a API pega o primeiro servidor disponível.

A API:
1. Aplica config de partida via RCON (`mp_autoteambalance 0`, `mp_roundtime 1.75`, etc.)
2. Configura nomes dos times
3. Adiciona jogadores aos times
4. Dá `changelevel` para o mapa selecionado
5. Inicia o warmup
6. Após 15s, encerra o warmup automaticamente

### 3.8 Pausar/Despausar

```
POST /api/matches/:id/pause
POST /api/matches/:id/unpause
```

### 3.9 Finalizar partida

```
POST /api/matches/:id/end
```

### 3.10 Cancelar partida

```
POST /api/matches/:id/cancel
```

---

## 4. Sistema de Veto

O veto segue o formato **BO1** (Melhor de 1) com 8 passos alternados:

1. **Team B** ban → **Team A** ban → **Team B** ban → **Team A** ban
2. **Team A** pick → **Team B** pick
3. **Team A** ban → **Team B** ban
4. Mapa **decider** (sorteio automático)

O mapa escolhido no `pick` é o mapa da partida (primeiro pick vai para o mapa 1, segundo pick vai para o mapa 2). Se sobrar só 1 mapa, ele é o decider sorteado automaticamente.

**Integração com frontend (React/Vue/etc):**

```javascript
// 1. Criar partida
const match = await fetch('/api/matches', { method: 'POST', body: ... });

// 2. Iniciar veto
await fetch(`/api/matches/${match.id}/start-veto`, { method: 'POST' });

// 3. Polling do estado do veto (a cada 1s)
const state = await fetch(`/api/matches/${match.id}/veto-state`);
// state.currentStep.team → qual time deve agir
// state.currentStep.action → "ban" ou "pick"
// state.availableMaps → mapas disponíveis

// 4. Processar ação
await fetch(`/api/matches/${match.id}/veto`, {
  method: 'POST',
  body: { team: 'A', action: 'ban', map: 'de_inferno' }
});

// 5. Quando state.isComplete === true, inicia a partida
await fetch(`/api/matches/${match.id}/start`, {
  method: 'POST',
  body: { serverId: '...' }
});
```

---

## 5. Skins

**Bridge site → servidor (loadout automático):** ver [SKINS-BRIDGE.md](./SKINS-BRIDGE.md).

### 5.1 Catálogo de skins

```
GET /api/skins/catalog?weaponId=weapon_ak47
```

Lista skins disponíveis no catálogo.

**Resposta:**
```json
[
  {
    "id": "ak47_redline",
    "weaponId": "weapon_ak47",
    "weaponName": "AK-47",
    "paintkit": 282,
    "paintkitName": "Redline",
    "rarity": "classified",
    "category": "rifle"
  }
]
```

### 5.2 Detalhes da skin do catálogo

```
GET /api/skins/catalog/:id
```

### 5.3 Cadastrar skin no catálogo

```
POST /api/skins/catalog
```

```json
{
  "id": "awp_dragon_lore",
  "weaponId": "weapon_awp",
  "weaponName": "AWP",
  "paintkit": 344,
  "paintkitName": "Dragon Lore",
  "rarity": "rare",
  "category": "sniper"
}
```

### 5.4 Listar skins de um jogador

```
GET /api/skins/player/:steamId
```

### 5.5 Dar skin para jogador

```
POST /api/skins/player/:steamId/give
```

```json
{
  "skinId": "awp_asiimov",
  "wear": "factory_new",
  "seed": 0,
  "stattrak": true,
  "nametag": "Bala Mágica"
}
```

### 5.6 Remover skin do jogador

```
DELETE /api/skins/player/:steamId/:playerSkinId
```

### 5.7 Loadout do jogador

```
GET /api/skins/loadout/:steamId?full=true
```

`?full=true` retorna dados completos (paintkit, wear, seed) prontos para o plugin do servidor.

### 5.8 Equipar skin

```
POST /api/skins/loadout/:steamId/equip
```

```json
{
  "playerSkinId": "id-da-skin-que-ganhou"
}
```

### 5.9 Remover skin do loadout

```
POST /api/skins/loadout/:steamId/unequip
```

```json
{
  "weaponId": "weapon_ak47"
}
```

### 5.10 Exportar para plugin do servidor

```
GET /api/skins/export/:steamId
```

Retorna o loadout no formato KeyValues que o SourceMod plugin lê:

```
"STEAM_1:0:12345"
{
    "weapon_ak47"
    {
        "paintkit"    "524"
        "wear"        "0.001"
        "seed"        "0"
        "stattrak"    "999"
    }
}
```

```
GET /api/skins/export
```

Exporta **todos** os jogadores.

### Fluxo completo de skins

```
PLATAFORMA (Web)              API                  SERVIDOR CS:GO
     │                         │                       │
     │── POST /give ──────────►│                       │
     │── POST /equip ─────────►│                       │
     │                         │                       │
     │── Cron job (30s) ──────►│── GET /export ───────►│ (gera skins.txt)
     │                         │                       │
     │                         │                       │── Plugin lê skins.txt
     │                         │                       │── Aplica skins nos players
```

---

## 6. Deploy

### Produção (Ubuntu + PM2)

```bash
# Instalar Node 20
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs

# Instalar PM2
sudo npm install -g pm2

# Clonar
git clone https://github.com/tiaguinhorak/api-csgo.git
cd api-csgo

# Configurar
cp .env.example .env
# Editar .env com sua API_KEY

# Instalar e compilar
npm install
npm run build

# Rodar
pm2 start ecosystem.config.js
pm2 save
pm2 startup   # Copiar e colar o comando sudo que aparecer
```

### Variáveis de ambiente

| Variável | Default | Descrição |
|----------|---------|-----------|
| `PORT` | `3000` | Porta da API |
| `API_KEY` | `suachaveapi` | Chave de autenticação |

### Comandos úteis

| Comando | Descrição |
|---------|-----------|
| `npm run dev` | Desenvolvimento com hot-reload |
| `npm run build` | Compilar TypeScript |
| `npm start` | Rodar produção |
| `pm2 status` | Ver status da API |
| `pm2 logs api-csgo` | Ver logs |
| `pm2 restart api-csgo` | Reiniciar |

---

## Modelo de dados

### Match (Partida)

```typescript
interface Match {
  id: string;
  roomId: string;
  teamA: Team;
  teamB: Team;
  mapPool: string[];       // Mapas disponíveis para veto
  vetoHistory: VetoAction[];
  status: 'waiting_players' | 'veto' | 'ready' | 'live' | 'finished' | 'cancelled';
  serverId?: string;       // Servidor onde está rodando
  selectedMap?: string;    // Mapa escolhido no veto
  createdAt: string;
  config: MatchConfig;
}
```

### Server (Servidor CS:GO)

```typescript
interface GameServer {
  id: string;
  name: string;
  host: string;            // IP do servidor
  sshPort: number;
  rconPort: number;
  rconPassword: string;
  csgoDir: string;          // Diretório do CS:GO
  screenSession: string;
  status: 'online' | 'offline' | 'busy';
  port: number;
  tickrate: number;
}
```

### Skin

```typescript
interface PlayerSkin {
  id: string;
  steamId: string;
  skinId: string;           // ID do catálogo
  wear: 'factory_new' | 'minimal_wear' | 'field_tested' | 'well_worn' | 'battle_scarred';
  seed: number;
  stattrak: boolean;
  stattrakCount: number;
  nametag?: string;
  equipped: boolean;
}
```
