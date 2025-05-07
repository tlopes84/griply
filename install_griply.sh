#!/bin/sh
# install_griply.sh — Provisiona, configura e valida todo o Griply SaaS em Ubuntu Server

# Versão 1.3 — atualização: repósito e caminhos claros; parametrização de URL do repositório
# Data: 2025-05-07

# VARIÁVEIS CONFIGURÁVEIS
DB_PASS=${DB_PASS:-'SUA_SENHA'}         # Senha MySQL do usuário 'griply'
DOMAIN=${DOMAIN:-'seu-dominio.com.br'}   # Domínio do servidor
EMAIL=${EMAIL:-'seu-email@dominio.com'}  # E-mail para Certbot
API_HEALTH_ROUTE=${API_HEALTH_ROUTE:-'/health'} # Endpoint healthcheck
REPO_URL=${REPO_URL:-'https://github.com/tlopes84/griply.git'} # URL do repositório Git

# 1. Verifica permissão root
if [ "$(id -u)" -ne 0 ]; then
  echo "Execute este script como root (sudo)."
  exit 1
fi

# 2. Cria usuário de sistema 'griply'
id griply >/dev/null 2>&1 || adduser --system --no-create-home --shell /usr/sbin/nologin griply

# 3. Atualiza sistema e instala dependências
apt update && apt upgrade -y
apt install -y git curl build-essential lsb-release gnupg snapd ufw nginx mysql-server

# 4. Firewall
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow http
ufw allow https
echo "y" | ufw enable

# 5. Node.js LTS
echo "Instalando Node.js LTS..."
curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
apt install -y nodejs

# 6. MySQL
systemctl enable --now mysql
echo "Configurando MySQL..."
mysql -e "CREATE DATABASE IF NOT EXISTS griply; CREATE USER IF NOT EXISTS 'griply'@'localhost' IDENTIFIED BY '$DB_PASS'; GRANT ALL ON griply.* TO 'griply'@'localhost'; FLUSH PRIVILEGES;"

# 7. Certbot
echo "Instalando Certbot..."
snap install --classic certbot
ln -sf /snap/bin/certbot /usr/bin/certbot

# 8. Nginx
echo "Configurando Nginx..."
cat << EOF > /etc/nginx/sites-available/griply
server {
    listen 80;
    server_name $DOMAIN;

    root /opt/griply/frontend-web/build;
    index index.html;

    location / {
        try_files \$uri /index.html;
    }
    location /api/ {
        proxy_pass http://localhost:3000/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF
ln -sf /etc/nginx/sites-available/griply /etc/nginx/sites-enabled/
nginx -t && systemctl reload nginx

# 9. Clone e build condicional
if [ ! -d /opt/griply ]; then
  echo "Clonando repositório Griply ($REPO_URL)..."
  git clone "$REPO_URL" /opt/griply || { echo "Erro no clone. Verifique a URL."; }
  chown -R griply:griply /opt/griply
else
  echo "/opt/griply já existe, pulando clone."
fi

# 10. Frontend build se existir
if [ -f /opt/griply/frontend-web/package.json ]; then
  echo "Construindo Frontend Web..."
  cd /opt/griply/frontend-web
  npm install && npm run build || echo "Erro no build do frontend."
else
  echo "frontend-web não encontrado ou sem package.json. Pulando."
fi

# 11. Backend setup e migração se houver
if [ -f /opt/griply/backend/package.json ]; then
  echo "Configurando Backend..."
  cd /opt/griply/backend
  cp -n .env.example .env
  sed -i "s/DB_PASS=.*/DB_PASS=$DB_PASS/" .env
  npm install || echo "Erro na instalação do backend."
  if grep -q migrate package.json; then
    npm run migrate || echo "Erro na migração do DB."
  else
    echo "Sem scripts de migração configurados."
  fi
else
  echo "backend não encontrado ou sem package.json. Pulando."
fi

# 12. Serviço systemd
echo "Criando serviço systemd..."
cat << EOF > /etc/systemd/system/griply.service
[Unit]
Description=Griply SaaS Service
After=network.target

[Service]
User=griply
EnvironmentFile=/opt/griply/backend/.env
WorkingDirectory=/opt/griply/backend
ExecStart=/usr/bin/node /opt/griply/backend/index.js
Restart=always

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now griply

# 13. Validações pós-instalação
echo "Realizando testes de funcionalidade..."
# MySQL
echo "Testando MySQL..."
mysql -u griply -p"$DB_PASS" -e "SHOW DATABASES LIKE 'griply';" || echo "MySQL falhou."
# API healthcheck
echo "Testando API (localhost:3000$API_HEALTH_ROUTE)..."
sleep 5
STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000$API_HEALTH_ROUTE)
[ "$STATUS" -eq 200 ] && echo "API OK" || { echo "API retornou $STATUS"; journalctl -u griply --no-pager | tail -n 20; }
# Nginx
echo "Testando Nginx..."
STATUS_NGINX=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/)
[ "$STATUS_NGINX" -eq 200 ] && echo "Nginx OK" || { echo "Nginx retornou $STATUS_NGINX"; tail -n 20 /var/log/nginx/error.log; }

echo "Instalação e validações completas. Acesse http://$DOMAIN para confirmar."
