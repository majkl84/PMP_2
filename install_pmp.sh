#!/bin/bash
#---------------------------------------------------------------------
# Script to Install PMP on Linux
# Developed by Majkl84 in 2025
#---------------------------------------------------------------------
# https://github.com/majkl84/PMP_2

set -e
PMP_VERSION="PMP_2-PMP_R.1.0.0"
PROJECT_DIR="/usr/bin/pmp"
UV_BIN="/usr/local/bin/uv"

# Скачивание и распаковка
cd /tmp
wget "https://github.com/majkl84/PMP_2/archive/refs/tags/PMP_R.1.0.0.tar.gz" -O pmp.tar.gz
tar xfz pmp.tar.gz
cd "$PMP_VERSION"

# Глобальная установка uv
if ! command -v uv &>/dev/null; then
    curl -LsS https://astral.sh/uv/install.sh | sh
    # Переносим uv в системную директорию
    mkdir -p /usr/local/bin
    mv "$HOME/.cargo/bin/uv" "$UV_BIN"
    chmod +x "$UV_BIN"
fi

# Копирование файлов
mkdir -p "$PROJECT_DIR"
cp -r . "$PROJECT_DIR/"

# Создание системного пользователя
if ! id pmp &>/dev/null; then
    useradd -rs /bin/false pmp
fi
chown -R pmp:pmp "$PROJECT_DIR"

# Проверка доступности uv для пользователя pmp
if ! sudo -u pmp test -x "$UV_BIN"; then
    echo "Ошибка: uv не доступен для пользователя pmp"
    exit 1
fi

# Systemd сервис
cat > /etc/systemd/system/pmp.service <<EOF
[Unit]
Description=PMP Service
After=network.target

[Service]
User=pmp
Group=pmp
WorkingDirectory=$PROJECT_DIR
ExecStart=$UV_BIN run $PROJECT_DIR/app.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Запуск сервиса
systemctl daemon-reload
systemctl enable pmp.service
systemctl start pmp.service

echo "Установка завершена"
systemctl status pmp.service --no-pager || {
    echo "Ошибка: сервис не запущен. Проверьте журналы: journalctl -u pmp.service -b"
    exit 1
}

# Очистка
rm -rf "/tmp/${PMP_VERSION}" "/tmp/pmp.tar.gz"