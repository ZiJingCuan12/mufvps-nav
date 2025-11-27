#!/usr/bin/env bash
set -euo pipefail

COMPOSE_BIN=()

log() {
  printf "\033[32m[信息]\033[0m %s\n" "$*"
}

warn() {
  printf "\033[33m[警告]\033[0m %s\n" "$*" >&2
}

die() {
  printf "\033[31m[错误]\033[0m %s\n" "$*" >&2
  exit 1
}

need_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    die "请使用 root 或 sudo 运行本脚本"
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-root)
        PROJECT_ROOT="$2"
        shift
        ;;
      --project-root=*)
        PROJECT_ROOT="${1#*=}"
        ;;
      --nav-image)
        NAV_IMAGE="$2"
        shift
        ;;
      --nav-image=*)
        NAV_IMAGE="${1#*=}"
        ;;
      --admin-image)
        ADMIN_IMAGE="$2"
        shift
        ;;
      --admin-image=*)
        ADMIN_IMAGE="${1#*=}"
        ;;
      --mysql-root-password)
        MYSQL_ROOT_PASSWORD="$2"
        shift
        ;;
      --mysql-root-password=*)
        MYSQL_ROOT_PASSWORD="${1#*=}"
        ;;
      --mysql-user)
        MYSQL_USER="$2"
        shift
        ;;
      --mysql-user=*)
        MYSQL_USER="${1#*=}"
        ;;
      --mysql-password)
        MYSQL_PASSWORD="$2"
        shift
        ;;
      --mysql-password=*)
        MYSQL_PASSWORD="${1#*=}"
        ;;
      --mysql-database)
        MYSQL_DATABASE="$2"
        shift
        ;;
      --mysql-database=*)
        MYSQL_DATABASE="${1#*=}"
        ;;
      --nav-domain)
        NAV_DOMAIN="$2"
        shift
        ;;
      --nav-domain=*)
        NAV_DOMAIN="${1#*=}"
        ;;
      --admin-domain)
        ADMIN_DOMAIN="$2"
        shift
        ;;
      --admin-domain=*)
        ADMIN_DOMAIN="${1#*=}"
        ;;
      --nav-port)
        NAV_PORT="$2"
        shift
        ;;
      --nav-port=*)
        NAV_PORT="${1#*=}"
        ;;
      --admin-port)
        ADMIN_PORT="$2"
        shift
        ;;
      --admin-port=*)
        ADMIN_PORT="${1#*=}"
        ;;
      --non-interactive)
        NON_INTERACTIVE=1
        ;;
      -h|--help)
        show_help
        exit 0
        ;;
      *)
        die "未知参数: $1"
        ;;
    esac
    shift
  done
}

show_help() {
  cat <<'EOF'
用法: curl -fsSL <脚本地址> | bash -s -- [参数]

可选参数：
  --project-root <路径>              默认 /opt/mufvps
  --nav-image <镜像>                 必填，例如 registry.example.com/nav:latest
  --admin-image <镜像>               必填，例如 registry.example.com/admin:latest
  --mysql-root-password <密码>       默认随机生成
  --mysql-user <用户名>              默认 mufvps_user
  --mysql-password <密码>            默认随机生成
  --mysql-database <数据库名>        默认 mufvps_nav
  --nav-domain <域名>                默认 nav.example.com
  --admin-domain <域名>              默认 admin.example.com
  --nav-port <端口>                  默认 3000
  --admin-port <端口>                默认 3001
  --non-interactive                  非交互模式，缺失参数会直接报错
EOF
}

ensure_binary() {
  local name="$1"
  command -v "$name" >/dev/null 2>&1
}

install_docker() {
  if ensure_binary docker; then
    log "Docker 已存在，跳过安装"
    return
  fi
  log "开始安装 Docker..."
  curl -fsSL https://get.docker.com | sh
  if command -v systemctl >/dev/null 2>&1; then
    systemctl enable docker
    systemctl start docker
  fi
}

ensure_compose_plugin() {
  if docker compose version >/dev/null 2>&1; then
    COMPOSE_BIN=(docker compose)
    return
  fi
  if ensure_binary docker-compose; then
    COMPOSE_BIN=(docker-compose)
    return
  fi

  log "安装 Docker Compose v2 插件..."
  local plugin_dir="/usr/local/lib/docker/cli-plugins"
  mkdir -p "$plugin_dir"
  local uname_s uname_m
  uname_s="$(uname -s)"
  uname_m="$(uname -m)"
  local compose_url="https://github.com/docker/compose/releases/download/v2.24.7/docker-compose-${uname_s}-${uname_m}"
  curl -fsSL "$compose_url" -o "${plugin_dir}/docker-compose"
  chmod +x "${plugin_dir}/docker-compose"

  if docker compose version >/dev/null 2>&1; then
    COMPOSE_BIN=(docker compose)
  else
    die "Docker Compose 安装失败，请手动检查"
  fi
}

prompt_if_missing() {
  local var_name="$1"
  local hint="$2"
  local default_value="${3:-}"
  local allow_empty="${4:-0}"
  local current="${!var_name-}"
  local input=""

  if [[ -n "$current" ]]; then
    return
  fi

  if [[ "$NON_INTERACTIVE" -eq 1 ]]; then
    if [[ "$allow_empty" -eq 1 ]]; then
      return
    fi
    die "缺少必填参数: $var_name"
  fi

  while true; do
    if [[ -n "$default_value" ]]; then
      read -rp "$hint [$default_value]: " input
    else
      read -rp "$hint: " input
    fi
    input="${input:-$default_value}"
    if [[ -n "$input" || "$allow_empty" -eq 1 ]]; then
      printf -v "$var_name" '%s' "$input"
      return
    fi
    echo "该项不能为空，请重新输入。"
  done
}

generate_secret() {
  if ensure_binary openssl; then
    openssl rand -base64 32 | tr -d '\n'
  else
    head -c 32 /dev/urandom | base64 | tr -d '\n'
  fi
}

write_sql_file() {
  local path="$1"
  cat >"$path" <<'EOF'
/*
Navicat Premium Data Transfer

Source Server         : mufvps_nav
Source Server Type    : MySQL
Source Server Version : 80043
Source Host           : localhost:3306
Source Schema         : mufvps_nav

Target Server Type    : MySQL
Target Server Version : 80043
File Encoding         : 65001

Date: 26/11/2025 04:13:20
*/

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

-- ----------------------------
-- Table structure for admin_users
-- ----------------------------
DROP TABLE IF EXISTS `admin_users`;
CREATE TABLE `admin_users`  (
  `id` int UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id` int UNSIGNED NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`) USING BTREE,
  UNIQUE INDEX `user_id`(`user_id` ASC) USING BTREE,
  INDEX `fk_admin_users_user`(`user_id` ASC) USING BTREE
) ENGINE = InnoDB CHARACTER SET = utf8mb4 COLLATE = utf8mb4_unicode_ci ROW_FORMAT = Dynamic;

-- ----------------------------
-- Table structure for audit_logs
-- ----------------------------
DROP TABLE IF EXISTS `audit_logs`;
CREATE TABLE `audit_logs`  (
  `id` bigint UNSIGNED NOT NULL AUTO_INCREMENT,
  `actor_user_id` int UNSIGNED NULL DEFAULT NULL,
  `action` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `entity_type` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT NULL,
  `entity_id` int UNSIGNED NULL DEFAULT NULL,
  `metadata` json NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`) USING BTREE,
  INDEX `fk_audit_logs_user`(`actor_user_id` ASC) USING BTREE
) ENGINE = InnoDB CHARACTER SET = utf8mb4 COLLATE = utf8mb4_unicode_ci ROW_FORMAT = Dynamic;

-- ----------------------------
-- Table structure for categories
-- ----------------------------
DROP TABLE IF EXISTS `categories`;
CREATE TABLE `categories`  (
  `id` int UNSIGNED NOT NULL AUTO_INCREMENT,
  `name` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `slug` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `description` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
  `icon` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT NULL,
  `display_order` int NULL DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`) USING BTREE,
  UNIQUE INDEX `name`(`name` ASC) USING BTREE,
  UNIQUE INDEX `slug`(`slug` ASC) USING BTREE
) ENGINE = InnoDB AUTO_INCREMENT = 8 CHARACTER SET = utf8mb4 COLLATE = utf8mb4_unicode_ci ROW_FORMAT = Dynamic;

-- ----------------------------
-- Table structure for category
-- ----------------------------
DROP TABLE IF EXISTS `category`;
CREATE TABLE `category`  (
  `id` int NOT NULL AUTO_INCREMENT,
  `name` varchar(191) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `description` varchar(191) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  PRIMARY KEY (`id`) USING BTREE
) ENGINE = InnoDB CHARACTER SET = utf8mb4 COLLATE = utf8mb4_unicode_ci ROW_FORMAT = Dynamic;

-- ----------------------------
-- Table structure for favorites
-- ----------------------------
DROP TABLE IF EXISTS `favorites`;
CREATE TABLE `favorites`  (
  `id` int UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id` int UNSIGNED NOT NULL,
  `tool_id` int UNSIGNED NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`) USING BTREE,
  UNIQUE INDEX `uk_favorites_user_tool`(`user_id` ASC, `tool_id` ASC) USING BTREE,
  INDEX `fk_favorites_tool`(`tool_id` ASC) USING BTREE
) ENGINE = InnoDB CHARACTER SET = utf8mb4 COLLATE = utf8mb4_unicode_ci ROW_FORMAT = Dynamic;

-- ----------------------------
-- Table structure for product
-- ----------------------------
DROP TABLE IF EXISTS `product`;
CREATE TABLE `product`  (
  `id` int NOT NULL AUTO_INCREMENT,
  `name` varchar(191) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `description` varchar(191) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `price` decimal(65, 30) NOT NULL,
  `image` varchar(191) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `category_id` int NULL DEFAULT NULL,
  PRIMARY KEY (`id`) USING BTREE,
  INDEX `Product_category_id_idx`(`category_id` ASC) USING BTREE
) ENGINE = InnoDB CHARACTER SET = utf8mb4 COLLATE = utf8mb4_unicode_ci ROW_FORMAT = Dynamic;

-- ----------------------------
-- Table structure for reviews
-- ----------------------------
DROP TABLE IF EXISTS `reviews`;
CREATE TABLE `reviews`  (
  `id` int UNSIGNED NOT NULL AUTO_INCREMENT,
  `tool_id` int UNSIGNED NOT NULL,
  `user_id` int UNSIGNED NOT NULL,
  `rating` tinyint NOT NULL,
  `content` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
  `is_public` tinyint(1) NOT NULL DEFAULT 1,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`) USING BTREE,
  UNIQUE INDEX `uk_reviews_tool_user`(`tool_id` ASC, `user_id` ASC) USING BTREE,
  INDEX `fk_reviews_user`(`user_id` ASC) USING BTREE,
  CONSTRAINT `reviews_chk_1` CHECK (`rating` between 1 and 5)
) ENGINE = InnoDB CHARACTER SET = utf8mb4 COLLATE = utf8mb4_unicode_ci ROW_FORMAT = Dynamic;

-- ----------------------------
-- Table structure for tool_submissions
-- ----------------------------
DROP TABLE IF EXISTS `tool_submissions`;
CREATE TABLE `tool_submissions`  (
  `id` int UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id` int UNSIGNED NOT NULL,
  `tool_id` int UNSIGNED NULL DEFAULT NULL,
  `name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `url` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `description` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
  `details` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
  `categories` json NULL,
  `status` enum('pending','approved','rejected') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'pending',
  `submitted_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `reviewed_at` timestamp NULL DEFAULT NULL,
  `reviewed_by_user_id` int UNSIGNED NULL DEFAULT NULL,
  `rejection_reason` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
  PRIMARY KEY (`id`) USING BTREE,
  INDEX `fk_tool_submissions_user`(`user_id` ASC) USING BTREE,
  INDEX `fk_tool_submissions_tool`(`tool_id` ASC) USING BTREE,
  INDEX `fk_tool_submissions_reviewer`(`reviewed_by_user_id` ASC) USING BTREE
) ENGINE = InnoDB CHARACTER SET = utf8mb4 COLLATE = utf8mb4_unicode_ci ROW_FORMAT = Dynamic;

-- ----------------------------
-- Table structure for tools
-- ----------------------------
DROP TABLE IF EXISTS `tools`;
CREATE TABLE `tools`  (
  `id` int UNSIGNED NOT NULL AUTO_INCREMENT,
  `name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `slug` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `url` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `description` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
  `details` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
  `category_id` int UNSIGNED NULL DEFAULT NULL,
  `logo_url` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT NULL,
  `status` enum('pending','approved','rejected') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'pending',
  `submitted_by_user_id` int UNSIGNED NULL DEFAULT NULL,
  `feature_flags` json NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`) USING BTREE,
  UNIQUE INDEX `slug`(`slug` ASC) USING BTREE,
  INDEX `fk_tools_category`(`category_id` ASC) USING BTREE,
  INDEX `fk_tools_submitter`(`submitted_by_user_id` ASC) USING BTREE
) ENGINE = InnoDB CHARACTER SET = utf8mb4 COLLATE = utf8mb4_unicode_ci ROW_FORMAT = Dynamic;

-- ----------------------------
-- Table structure for users
-- ----------------------------
DROP TABLE IF EXISTS `users`;
CREATE TABLE `users`  (
  `id` int UNSIGNED NOT NULL AUTO_INCREMENT,
  `username` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `email` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `password_hash` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `avatar_url` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT NULL,
  `role` enum('user','admin','moderator') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'user',
  `last_login_at` datetime NULL DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`) USING BTREE,
  UNIQUE INDEX `username`(`username` ASC) USING BTREE,
  UNIQUE INDEX `email`(`email` ASC) USING BTREE
) ENGINE = InnoDB CHARACTER SET = utf8mb4 COLLATE = utf8mb4_unicode_ci ROW_FORMAT = Dynamic;

SET FOREIGN_KEY_CHECKS = 1;
EOF
}

prepare_dirs() {
  mkdir -p "$PROJECT_ROOT"/{deploy/env,deploy/logs/nginx,deploy/nginx/conf.d,deploy/mysql/data,doc}
}

render_files() {
  local compose_path="$PROJECT_ROOT/deploy/docker-compose.yml"
  cat >"$compose_path" <<EOF
services:
  mysql:
    image: mysql:8.0
    container_name: mufvps-mysql
    env_file: ./env/mysql.env
    volumes:
      - ./mysql/data:/var/lib/mysql
      - ../doc/mufvps_nav.sql:/docker-entrypoint-initdb.d/mufvps_nav.sql:ro
    restart: unless-stopped
    healthcheck:
      test:
        - CMD
        - mysqladmin
        - ping
        - -hmysql
        - -p${MYSQL_PASSWORD}
      interval: 10s
      timeout: 5s
      retries: 10

  nav:
    image: ${NAV_IMAGE}
    container_name: mufvps-nav
    env_file: ./env/nav.env
    ports:
      - "${NAV_PORT}:${NAV_PORT}"
    depends_on:
      mysql:
        condition: service_healthy
    restart: unless-stopped

  admin:
    image: ${ADMIN_IMAGE}
    container_name: mufvps-nav-admin
    env_file: ./env/admin.env
    ports:
      - "${ADMIN_PORT}:${ADMIN_PORT}"
    depends_on:
      mysql:
        condition: service_healthy
    restart: unless-stopped

  nginx:
    image: nginx:1.27
    container_name: mufvps-nginx
    depends_on:
      - nav
      - admin
    volumes:
      - ./nginx/conf.d:/etc/nginx/conf.d
      - ./logs/nginx:/var/log/nginx
    ports:
      - "80:80"
      - "443:443"
    restart: unless-stopped

networks:
  default:
    name: mufvps-net
EOF

  cat >"$PROJECT_ROOT/deploy/env/mysql.env" <<EOF
MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}
MYSQL_DATABASE=${MYSQL_DATABASE}
MYSQL_USER=${MYSQL_USER}
MYSQL_PASSWORD=${MYSQL_PASSWORD}
TZ=Asia/Shanghai
EOF

  cat >"$PROJECT_ROOT/deploy/env/nav.env" <<EOF
NODE_ENV=production
PORT=${NAV_PORT}
DATABASE_URL=mysql://${MYSQL_USER}:${MYSQL_PASSWORD}@mysql:3306/${MYSQL_DATABASE}
DATABASE_POOL_SIZE=20
NEXT_PUBLIC_APP_URL=https://${NAV_DOMAIN}
SESSION_SECRET=${NAV_SESSION_SECRET}
EOF

  cat >"$PROJECT_ROOT/deploy/env/admin.env" <<EOF
NODE_ENV=production
PORT=${ADMIN_PORT}
DATABASE_URL=mysql://${MYSQL_USER}:${MYSQL_PASSWORD}@mysql:3306/${MYSQL_DATABASE}
NEXT_PUBLIC_APP_URL=https://${ADMIN_DOMAIN}
SESSION_SECRET=${ADMIN_SESSION_SECRET}
EOF

  cat >"$PROJECT_ROOT/deploy/nginx/conf.d/mufvps.conf" <<EOF
server {
    listen 80;
    server_name ${NAV_DOMAIN};
    location / {
        proxy_pass http://nav:${NAV_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}

server {
    listen 80;
    server_name ${ADMIN_DOMAIN};
    location / {
        proxy_pass http://admin:${ADMIN_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

  cat >"$PROJECT_ROOT/deploy/deploy.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="/opt/mufvps"
COMPOSE_DIR="$PROJECT_ROOT/deploy"

echo "[1/4] 拉取最新镜像..."
cd "$COMPOSE_DIR"
docker compose pull

echo "[2/4] 启动服务..."
docker compose up -d

echo "[3/4] 查看状态..."
docker compose ps

echo "部署完成 ✅"
EOF
  chmod +x "$PROJECT_ROOT/deploy/deploy.sh"

  write_sql_file "$PROJECT_ROOT/doc/mufvps_nav.sql"
}

run_compose() {
  local compose_dir="$PROJECT_ROOT/deploy"
  pushd "$compose_dir" >/dev/null
  "${COMPOSE_BIN[@]}" pull
  "${COMPOSE_BIN[@]}" up -d
  "${COMPOSE_BIN[@]}" ps
  popd >/dev/null
}

need_root

PROJECT_ROOT=${PROJECT_ROOT:-/opt/mufvps}
NAV_IMAGE=${NAV_IMAGE:-zijingcuan/mufvps-nav:latest}
ADMIN_IMAGE=${ADMIN_IMAGE:-zijingcuan/mufvps-nav-admin:latest}
MYSQL_DATABASE=${MYSQL_DATABASE:-mufvps_nav}
MYSQL_USER=${MYSQL_USER:-mufvps_user}
MYSQL_PASSWORD=${MYSQL_PASSWORD:-}
MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD:-}
NAV_DOMAIN=${NAV_DOMAIN:-nav.example.com}
ADMIN_DOMAIN=${ADMIN_DOMAIN:-admin.example.com}
NAV_PORT=${NAV_PORT:-3000}
ADMIN_PORT=${ADMIN_PORT:-3001}
NON_INTERACTIVE=${NON_INTERACTIVE:-0}

parse_args "$@"

prompt_if_missing "NAV_IMAGE" "请输入 nav 镜像 (例如 registry.example.com/mufvps-nav:latest)"
prompt_if_missing "ADMIN_IMAGE" "请输入 admin 镜像 (例如 registry.example.com/mufvps-nav-admin:latest)"
prompt_if_missing "MYSQL_ROOT_PASSWORD" "请输入 MySQL Root 密码 (建议复杂)"
prompt_if_missing "MYSQL_PASSWORD" "请输入 MySQL 用户密码 (建议复杂)"

NAV_SESSION_SECRET=${NAV_SESSION_SECRET:-$(generate_secret)}
ADMIN_SESSION_SECRET=${ADMIN_SESSION_SECRET:-$(generate_secret)}

install_docker
ensure_compose_plugin

log "准备部署目录 ${PROJECT_ROOT}..."
prepare_dirs
render_files

log "MySQL 初始化脚本写入完成"

if ! getent group docker >/dev/null 2>&1; then
  warn "docker 组不存在，可按需手动执行 usermod -aG docker <username>"
fi

log "开始拉取镜像并启动..."
run_compose

cat <<EOF

====================================================
部署完成！
- 代码路径: ${PROJECT_ROOT}
- docker compose 文件: ${PROJECT_ROOT}/deploy/docker-compose.yml
- Nginx 配置: ${PROJECT_ROOT}/deploy/nginx/conf.d/mufvps.conf
- 数据库脚本: ${PROJECT_ROOT}/doc/mufvps_nav.sql

如需后续更新，可执行:
  cd ${PROJECT_ROOT}/deploy && docker compose pull && docker compose up -d
====================================================
EOF

