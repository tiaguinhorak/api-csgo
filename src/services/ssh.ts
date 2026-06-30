import { Client as SSHClient, ConnectConfig } from 'ssh2';
import { exec } from 'child_process';
import os from 'os';

interface ServerConnection {
  host: string;
  port: number;
  username?: string;
  privateKey?: string;
  password?: string;
}

/** Hard cap so a stuck shell/SSH never pendura a requisição (era a causa do start/stop travar). */
const EXEC_TIMEOUT_MS = 25_000;
const SSH_READY_TIMEOUT_MS = 10_000;

function shellSingleQuote(value: string): string {
  return `'${value.replace(/'/g, `'\\''`)}'`;
}

function isLocalConn(conn: ServerConnection): boolean {
  return conn.host === '127.0.0.1' || conn.host === 'localhost' || !conn.username;
}

/**
 * Monta o comando local rodando como o usuário dono do srcds, SEM `su` interativo
 * (o `su - user -c` bloqueava esperando senha quando api-csgo não roda como root).
 */
function buildLocalCommand(conn: ServerConnection, command: string): string {
  const targetUser = (conn.username || process.env.CSGO_SERVER_USER || 'csgo').trim();
  const currentUser = os.userInfo().username;
  const quoted = shellSingleQuote(command);

  // Já somos o usuário dono do srcds → roda direto.
  if (currentUser === targetUser) {
    return `bash -lc ${quoted} < /dev/null`;
  }

  // root pode trocar de usuário sem senha via runuser (não interativo).
  if (currentUser === 'root') {
    return `runuser -l ${targetUser} -c ${quoted} < /dev/null`;
  }

  // Caso contrário: tenta sudo não interativo; se não houver permissão, roda direto.
  return (
    `sudo -n -u ${targetUser} bash -lc ${quoted} < /dev/null 2>/dev/null ` +
    `|| bash -lc ${quoted} < /dev/null`
  );
}

export class SshService {
  async execCommand(conn: ServerConnection, command: string): Promise<{ stdout: string; stderr: string }> {
    // Local execution (same machine, no SSH needed)
    if (isLocalConn(conn)) {
      const fullCmd = buildLocalCommand(conn, command);
      return new Promise((resolve, reject) => {
        exec(
          fullCmd,
          { maxBuffer: 1024 * 1024, timeout: EXEC_TIMEOUT_MS, killSignal: 'SIGKILL' },
          (error, stdout, stderr) => {
            // timeout do exec mata o processo e seta error.killed
            if (error && (error as NodeJS.ErrnoException & { killed?: boolean }).killed) {
              reject(new Error(`Comando local excedeu ${EXEC_TIMEOUT_MS / 1000}s e foi abortado.`));
              return;
            }
            if (error && stderr) {
              reject(new Error(stderr));
              return;
            }
            resolve({ stdout: stdout || '', stderr: stderr || '' });
          },
        );
      });
    }

    // Remote execution via SSH
    return new Promise((resolve, reject) => {
      const client = new SSHClient();
      const config: ConnectConfig = {
        host: conn.host,
        port: conn.port,
        username: conn.username || 'root',
        readyTimeout: SSH_READY_TIMEOUT_MS,
      };

      if (conn.privateKey) {
        config.privateKey = conn.privateKey;
      } else if (conn.password) {
        config.password = conn.password;
      }

      let stdout = '';
      let stderr = '';
      let settled = false;

      const finish = (fn: () => void) => {
        if (settled) return;
        settled = true;
        clearTimeout(guard);
        try {
          client.end();
        } catch {
          /* ignore */
        }
        fn();
      };

      const guard = setTimeout(() => {
        finish(() => reject(new Error(`SSH excedeu ${EXEC_TIMEOUT_MS / 1000}s e foi abortado.`)));
      }, EXEC_TIMEOUT_MS);

      client.on('ready', () => {
        client.exec(command, (err, stream) => {
          if (err) {
            finish(() => reject(err));
            return;
          }

          stream.on('close', () => {
            finish(() => resolve({ stdout, stderr }));
          });

          stream.on('data', (data: Buffer) => {
            stdout += data.toString();
          });

          stream.stderr.on('data', (data: Buffer) => {
            stderr += data.toString();
          });
        });
      });

      client.on('error', (err) => finish(() => reject(err)));
      client.connect(config);
    });
  }

  async startServer(
    conn: ServerConnection,
    csgoDir: string,
    screenSession: string,
    port: number,
    tickrate: number,
    gameType: number,
    gameMode: number,
    map: string,
    rconPassword: string,
    serverPassword?: string
  ): Promise<string> {
    const logPath = `${csgoDir}/clutch-srcds-${port}.log`;
    const bindIp = process.env.CSGO_BIND_IP?.trim() || '0.0.0.0';
    const gslt = process.env.CSGO_GSLT_TOKEN?.trim();

    // Libera só esta porta (não mata outros srcds em portas diferentes).
    const freePort =
      `fuser -k ${port}/udp 2>/dev/null || true; ` +
      `fuser -k ${port}/tcp 2>/dev/null || true; `;

    let launch = `./srcds_run`;
    launch += ` -tickrate ${tickrate}`;
    launch += ` -game csgo -console -usercon`;
    launch += ` -ip ${bindIp}`;
    launch += ` -port ${port}`;
    launch += ` +game_type ${gameType} +game_mode ${gameMode}`;
    launch += ` +map ${map}`;
    launch += ` +rcon_password "${rconPassword}"`;
    launch += ` -maxplayers 10`;
    if (gslt) launch += ` +sv_setsteamaccount ${gslt}`;
    if (serverPassword) {
      launch += ` +sv_password "${serverPassword}"`;
    }

    // Roda dentro do screen redirecionando saída para um log que conseguimos inspecionar.
    const inner = `cd ${csgoDir} && ${launch} > ${logPath} 2>&1`;
    const cmd =
      `cd ${csgoDir} && ${freePort} ` +
      `screen -L -dmS ${screenSession} bash -c ${shellSingleQuote(inner)}`;

    const { stdout, stderr } = await this.execCommand(conn, cmd);
    return stderr || stdout || 'Server started';
  }

  /** Lê o fim do log do srcds para diagnosticar falha de start. */
  async readServerLog(conn: ServerConnection, csgoDir: string, port?: number, lines = 25): Promise<string> {
    const suffix = port != null ? `-${port}` : '';
    const logPath = `${csgoDir}/clutch-srcds${suffix}.log`;
    try {
      const { stdout } = await this.execCommand(
        conn,
        `tail -n ${lines} ${logPath} 2>/dev/null || tail -n ${lines} ${csgoDir}/clutch-srcds.log 2>/dev/null || true`,
      );
      return stdout.trim();
    } catch {
      return '';
    }
  }

  async stopServer(conn: ServerConnection, screenSession: string): Promise<string> {
    const killCmd =
      `for s in $(screen -ls 2>/dev/null | grep -F ".${screenSession}" | awk '{print $1}'); do ` +
      `screen -S "$s" -X quit || true; done`;
    const { stdout, stderr } = await this.execCommand(conn, killCmd);
    return stderr || stdout || 'Server stopped';
  }

  async serverStatus(conn: ServerConnection, screenSession: string): Promise<'running' | 'stopped'> {
    const checkCmd = `screen -ls 2>/dev/null | grep -F ".${screenSession}" || true`;
    const { stdout } = await this.execCommand(conn, checkCmd);
    return stdout.includes(screenSession) ? 'running' : 'stopped';
  }

  async getServerProcessId(conn: ServerConnection, screenSession: string): Promise<string | null> {
    const cmd = `screen -list | grep ${screenSession} | awk '{print $1}'`;
    const { stdout } = await this.execCommand(conn, cmd);
    const pid = stdout.trim();
    return pid || null;
  }

  async sendServerCommand(conn: ServerConnection, screenSession: string, command: string): Promise<string> {
    const cmd = `screen -S ${screenSession} -X stuff "${command}^M"`;
    const { stdout, stderr } = await this.execCommand(conn, cmd);
    return stderr || stdout || 'Command sent';
  }

  async testConnection(conn: ServerConnection): Promise<boolean> {
    try {
      const { stdout } = await this.execCommand(conn, 'echo "pong"');
      return stdout.trim() === 'pong';
    } catch {
      return false;
    }
  }
}

export const sshService = new SshService();
