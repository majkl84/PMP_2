#!/bin/bash
#---------------------------------------------------------------------
# PMP Installer with Global uv Installation
#---------------------------------------------------------------------

set -e
PMP_VERSION="PMP_2-PMP_R.1.0.0"
PROJECT_DIR="/usr/bin/pmp"

# Глобальная установка uv (если не установлен)
if ! command -v uv >/dev/null 2>&1; then
    echo "Установка uv в глобальную систему..."
    curl -LsS https://astral.sh/uv/install.sh | sh
    echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> /etc/profile
    source /etc/profile
fi

# Скачивание и распаковка проекта
cd /tmp
wget "https://github.com/majkl84/PMP_2/archive/refs/tags/PMP_R.1.0.0.tar.gz" -O pmp.tar.gz
tar xfz pmp.tar.gz
cd "$PMP_VERSION"

# Развертывание проекта
mkdir -p "$PROJECT_DIR"
cp -r . "$PROJECT_DIR"

# Настройка системного пользователя
if ! id pmp >/dev/null 2>&1; then
    useradd -rs /bin/false pmp
fi
chown -R pmp:pmp "$PROJECT_DIR"

# Systemd сервис
cat > /etc/systemd/system/pmp.service <<EOF
[Unit]
Description=PMP Service
After=network.target

[Service]
User=root
Group=root
WorkingDirectory=$PROJECT_DIR
Environment="PATH=/root/.cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ExecStart=/root/.cargo/bin/uv run $PROJECT_DIR/app.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Запуск сервиса
systemctl daemon-reload
systemctl enable --now pmp.service

# Проверка и очистка
if systemctl is-active --quiet pmp.service; then
    echo "Установка успешно завершена!"
    systemctl status pmp.service --no-pager
    rm -rf "/tmp/${PMP_VERSION}" "/tmp/pmp.tar.gz"
else
    echo "Ошибка запуска сервиса. Диагностика:"
    echo "1. Проверьте логи: journalctl -u pmp.service -b"
    echo "2. Попробуйте запустить вручную:"
    echo "   sudo -u pmp /root/.cargo/bin/uv run $PROJECT_DIR/app.py"
    exit 1
fi