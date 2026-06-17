import { Client as SSHClient, ConnectConfig } from 'ssh2';
import { exec } from 'child_process';

interface ServerConnection {
  host: string;
  port: number;
  username?: string;
  privateKey?: string;
  password?: string;
}

export class SshService {
  async execCommand(conn: ServerConnection, command: string): Promise<{ stdout: string; stderr: string }> {
    // Local execution (same machine, no SSH needed)
    if (conn.host === '127.0.0.1' || conn.host === 'localhost' || !conn.username) {
      const user = conn.username || 'root';
      const fullCmd = user === 'root'
        ? command
        : `su - ${user} -c '${command.replace(/'/g, "'\\''")}'`;
      return new Promise((resolve, reject) => {
        exec(fullCmd, (error, stdout, stderr) => {
          if (error && stderr) reject(new Error(stderr));
          else resolve({ stdout: stdout || '', stderr: stderr || '' });
        });
      });
    }

    // Remote execution via SSH
    return new Promise((resolve, reject) => {
      const client = new SSHClient();
      const config: ConnectConfig = {
        host: conn.host,
        port: conn.port,
        username: conn.username || 'root',
        readyTimeout: 10000,
      };

      if (conn.privateKey) {
        config.privateKey = conn.privateKey;
      } else if (conn.password) {
        config.password = conn.password;
      }

      let stdout = '';
      let stderr = '';

      client.on('ready', () => {
        client.exec(command, (err, stream) => {
          if (err) {
            client.end();
            reject(err);
            return;
          }

          stream.on('close', () => {
            client.end();
            resolve({ stdout, stderr });
          });

          stream.on('data', (data: Buffer) => {
            stdout += data.toString();
          });

          stream.stderr.on('data', (data: Buffer) => {
            stderr += data.toString();
          });
        });
      });

      client.on('error', reject);
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
    let cmd = `cd ${csgoDir} && screen -dmS ${screenSession} ./srcds_run`;
    cmd += ` -tickrate ${tickrate}`;
    cmd += ` -game csgo -console -usercon`;
    cmd += ` -port ${port}`;
    cmd += ` +game_type ${gameType} +game_mode ${gameMode}`;
    cmd += ` +map ${map}`;
    cmd += ` +rcon_password "${rconPassword}"`;
    cmd += ` -maxplayers 10`;
    if (serverPassword) {
      cmd += ` +sv_password "${serverPassword}"`;
    }

    const { stdout, stderr } = await this.execCommand(conn, cmd);
    return stderr || stdout || 'Server started';
  }

  async stopServer(conn: ServerConnection, screenSession: string): Promise<string> {
    const killCmd = `screen -S ${screenSession} -X quit`;
    const { stdout, stderr } = await this.execCommand(conn, killCmd);
    return stderr || stdout || 'Server stopped';
  }

  async serverStatus(conn: ServerConnection, screenSession: string): Promise<'running' | 'stopped'> {
    const checkCmd = `screen -list | grep ${screenSession}`;
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
