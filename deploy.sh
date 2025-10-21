#!/bin/bash
set -e

# ===== CONFIGURATION =====
TIMESTAMP=$(date +%y%m%d)  # e.g., 211025
LOGFILE="deploy_${TIMESTAMP}.log"
DEFAULT_BRANCH="main"
DEFAULT_PORT=3000

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOGFILE"; }
trap 'log "❌ Script failed at line $LINENO"; exit 1' ERR

# ===== CLEANUP FUNCTION =====
cleanup() {
    log "🧹 Cleaning up deployed resources..."
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$USERNAME@$SERVER_IP" <<EOF
sudo docker ps -aq | xargs -r sudo docker rm -f
sudo docker images -q | xargs -r sudo docker rmi -f
sudo rm -rf ~/deploy_app
sudo rm -f /etc/nginx/sites-available/deploy_app
sudo rm -f /etc/nginx/sites-enabled/deploy_app
sudo nginx -t && sudo systemctl reload nginx
EOF
    log "✅ Cleanup completed"
    exit 0
}

if [[ "${1:-}" == "--cleanup" ]]; then cleanup; fi

log "🚀 Starting Static HTML Deployment"

# ===== COLLECT PARAMETERS =====
read -p "Enter GitHub Repository URL: " REPO_URL
read -s -p "Enter GitHub Personal Access Token (PAT) [can be empty for public repo]: " PAT
echo
read -p "Enter Branch name [default: $DEFAULT_BRANCH]: " BRANCH
BRANCH=${BRANCH:-$DEFAULT_BRANCH}
read -p "Enter Remote Server Username: " USERNAME
read -p "Enter Remote Server IP: " SERVER_IP
read -p "Enter SSH Key Path: " SSH_KEY
read -p "Enter Application Host Port [default: $DEFAULT_PORT]: " APP_PORT
APP_PORT=${APP_PORT:-$DEFAULT_PORT}

# ===== VERIFY INPUTS =====
if [ -z "$REPO_URL" ] || [ -z "$USERNAME" ] || [ -z "$SERVER_IP" ] || [ -z "$SSH_KEY" ]; then
    log "❌ Missing required parameters"
    exit 1
fi

# ===== SSH CONNECTION CHECK =====
log "🔌 Testing SSH connection..."
ssh -i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$USERNAME@$SERVER_IP" "echo '✅ SSH connection successful'" || {
    log "❌ SSH connection failed"
    exit 1
}

# ===== PREPARE REMOTE ENVIRONMENT =====
log "⚙️ Preparing remote server..."
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$USERNAME@$SERVER_IP" <<EOF
set -e

sudo apt remove -y docker docker.io containerd containerd.io || true
sudo apt update -y
sudo apt install -y curl nginx lsb-release apt-transport-https ca-certificates gnupg

curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

sudo systemctl enable --now docker
sudo systemctl enable --now nginx

sudo usermod -aG docker "\$USER" || true

docker --version
docker-compose version || true
nginx -v
EOF
log "✅ Remote environment ready"

# ===== CLONE REPO LOCALLY =====
REPO_NAME=$(basename "$REPO_URL" .git)
log "📥 Cloning repository: $REPO_NAME"

if [ -d "$REPO_NAME" ]; then
    log "🔄 Repository exists - pulling updates"
    cd "$REPO_NAME"
    git fetch origin "$BRANCH"
    git checkout "$BRANCH"
    git reset --hard "origin/$BRANCH"
    git pull origin "$BRANCH"
else
    if [ -n "$PAT" ]; then
        AUTH_URL="https://${PAT}@${REPO_URL#https://}"
    else
        AUTH_URL="$REPO_URL"
    fi
    git clone -b "$BRANCH" "$AUTH_URL" "$REPO_NAME"
    cd "$REPO_NAME"
fi

log "✅ Repository ready on branch: $BRANCH"

# ===== TRANSFER FILES =====
log "📤 Transferring static files to remote server..."
rsync -avz -e "ssh -i $SSH_KEY -o StrictHostKeyChecking=no" \
    ./ "$USERNAME@$SERVER_IP:~/deploy_app/" --exclude '.git'

# ===== DEPLOY DOCKERIZED NGINX =====
log "🐳 Deploying Nginx container..."
ssh -i "$SSH_KEY" "$USERNAME@$SERVER_IP" APP_NAME="deploy_app" APP_PORT=3000 IMAGE_NAME="deploy_app:latest" bash -s <<'ENDSSH'
set -e
cd ~/deploy_app

APP_NAME="deploy_app"
IMAGE_NAME="deploy_app:latest"
HOST_PORT=$APP_PORT

# Create Dockerfile if missing
if [ ! -f Dockerfile ]; then
cat > Dockerfile <<DOCKER
FROM nginx:alpine
COPY . /usr/share/nginx/html
EXPOSE 80
DOCKER
fi

# Stop & remove existing container if exists
if docker ps -a --format '{{.Names}}' | grep -q "^$APP_NAME\$"; then
    docker rm -f "$APP_NAME"
fi

# Build image
docker build -t "$IMAGE_NAME" .

# Run container mapping host port 3000 to container 80
docker run -d \
    --name "$APP_NAME" \
    --restart unless-stopped \
    -p 3000:80 \
    "$IMAGE_NAME"

# Wait for container to start
sleep 5
ENDSSH
log "✅ Container deployed"

# ===== CONFIGURE NGINX REVERSE PROXY =====
log "🌐 Configuring Nginx reverse proxy..."
ssh -i "$SSH_KEY" "$USERNAME@$SERVER_IP" <<'EOF'
sudo bash -c 'cat > /etc/nginx/sites-available/deploy_app <<NGINXCFG
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
NGINXCFG'
sudo ln -sf /etc/nginx/sites-available/deploy_app /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx
EOF
log "✅ Nginx configured"

# ===== VALIDATE DEPLOYMENT =====
log "🔎 Validating deployment..."
sleep 3
if curl -s -f --max-time 10 "http://$SERVER_IP:$APP_PORT/" > /dev/null; then
    log "🎉 SUCCESS: Application accessible at http://$SERVER_IP:$APP_PORT"
else
    log "❌ Deployment failed - app not responding externally"
    exit 1
fi

log "🏁 Deployment completed successfully"
log "📋 Log file: $LOGFILE"
log "🔧 Cleanup command: ./deploy.sh --cleanup"
