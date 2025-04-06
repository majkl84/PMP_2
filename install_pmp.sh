#!/bin/bash
#---------------------------------------------------------------------
# Script to Install PMP on Linux
# Developed by Majkl84 in 2025-04
#---------------------------------------------------------------------
# https://github.com/majkl84/PMP_2

set -e  # Прерывать при ошибках
PMP_VERSION="PMP_2-PMP_R.1.0.0"
PROJECT_DIR="/usr/bin/pmp"

# Скачивание и распаковка
cd /tmp
wget "https://github.com/majkl84/PMP_2/archive/refs/tags/PMP_R.1.0.0.tar.gz" -O pmp.tar.gz
tar xfz pmp.tar.gz
cd "$PMP_VERSION"

# Установка uv в системную директорию
if ! command -v uv &> /dev/null; then
    curl -LsS https://astral.sh/uv/install.sh | sh
    # Переносим uv в /usr/local/bin чтобы был доступен всем пользователям
    mv "$HOME/.cargo/bin/uv" /usr/local/bin/
    export PATH="/usr/local/bin:$PATH"
fi

# Копирование файлов (сохранение прав)
mkdir -p "$PROJECT_DIR"
find . -mindepth 1 \( -name '.gitignore' -o -name 'LICENSE' \) -prune -o -exec cp -r --parents '{}' "$PROJECT_DIR/" \;
#cp -r . "$PROJECT_DIR/"

# Создание системного пользователя
if ! id pmp &>/dev/null; then
    useradd -rs /bin/false pmp
fi
chown -R pmp:pmp "$PROJECT_DIR"

# Systemd сервис
cat > /etc/systemd/system/pmp.service <<EOF
[Unit]
Description=PMP Service
After=network.target

[Service]
User=pmp
Group=pmp
WorkingDirectory=$PROJECT_DIR
ExecStart=/usr/local/bin/uv run $PROJECT_DIR/app.py
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
echo "Установка завершена"
systemctl status pmp.service --no-pager

# После успешного запуска сервиса
if systemctl is-active --quiet pmp.service; then
    echo "Удаление временных файлов..."
    rm -rf "/tmp/${PMP_VERSION}" "/tmp/pmp.tar.gz"
else
    echo "Ошибка: сервис не запущен. Проверьте журналы: journalctl -u pmp.service -b"
    exit 1
fi