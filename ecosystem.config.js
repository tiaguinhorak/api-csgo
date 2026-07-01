const path = require('path');
const fs = require('fs');
const dotenv = require('dotenv');

const envFile = path.join(__dirname, '.env');
const fileEnv = fs.existsSync(envFile)
  ? dotenv.parse(fs.readFileSync(envFile))
  : {};

module.exports = {
  apps: [{
    name: 'api-csgo',
    script: 'dist/index.js',
    cwd: __dirname,
    instances: 1,
    exec_mode: 'fork',
    watch: false,
    autorestart: true,
    max_restarts: 15,
    min_uptime: '10s',
    restart_delay: 8000,
    env: {
      NODE_ENV: 'production',
      ...fileEnv,
    },
    error_file: 'logs/err.log',
    out_file: 'logs/out.log',
    log_date_format: 'YYYY-MM-DD HH:mm:ss',
  }],
};
