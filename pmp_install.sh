#!/bin/bash
#--------------------------------------------------------------------
# Script to Install PMP on Linux
# Developed by Majkl84 in 2025
#--------------------------------------------------------------------
# https://github.com/majkl84/PMP

set -e  # Прерывать при ошибках
PMP_VERSION="PMP_2-PMP_R.1.0.0"
PROJECT_DIR="/usr/bin/pmp"
VENV_DIR="$PROJECT_DIR/venv"

# Установка зависимостей ОС
apt update
apt install -y curl wget

# Скачивание и распаковка
cd /tmp
wget "https://github.com/majkl84/PMP_2/archive/refs/tags/PMP_R.1.0.0.tar.gz" -O pmp.tar.gz
tar xvfz pmp.tar.gz
cd "PMP-$PMP_VERSION"

# Копирование файлов (сохранение прав)
mkdir -p "$PROJECT_DIR"
cp -r . "$PROJECT_DIR/"

# Создание системного пользователя
if ! id pmp &>/dev/null; then
    useradd -rs /bin/false pmp
fi
chown -R pmp:pmp "$PROJECT_DIR"

# Установка uv
if ! command -v uv &> /dev/null; then
    curl -LsS https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.cargo/bin:$PATH"
fi

# Создание venv
uv venv -p "$(uv pip python --version 3.11)" "$VENV_DIR"
source "$VENV_DIR/bin/activate"

# Установка зависимостей
uv pip install -r "$PROJECT_DIR/requirements.txt"

# Systemd сервис
cat > /etc/systemd/system/pmp.service <<EOF
[Unit]
Description=PMP Service
After=network.target

[Service]
User=pmp
Group=pmp
WorkingDirectory=$PROJECT_DIR
ExecStart=$VENV_DIR/bin/python $PROJECT_DIR/app.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Запуск сервиса
systemctl daemon-reload
systemctl enable pmp.service
systemctl start pmp.service

# Проверка
echo "Установка завершена. Проверка:"
systemctl status pmp.service --no-pager
$VENV_DIR/bin/python --version

# После успешного запуска сервиса
if systemctl is-active --quiet pmp.service; then
    echo "Удаление временных файлов..."
    rm -rf "/tmp/PMP-$PMP_VERSION" "/tmp/pmp.tar.gz"
else
    echo "Ошибка: сервис не запущен. Файлы сохранены в /tmp для диагностики"
    exit 1
fi
