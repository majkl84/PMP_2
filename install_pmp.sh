#!/bin/bash
#--------------------------------------------------------------------
# Скрипт для установки PMP в Linux
# Разработан Majkl84 в 2025-04
#---------------------------------------------------------------------
# https://github.com/majkl84/PMP_2

set -euo pipefail

# Конфигурация
PMP_VERSION="PMP_2-PMP_R.1.0.0"
PROJECT_DIR="/usr/bin/pmp"
VENV_DIR="$PROJECT_DIR/.venv"

# Определяем команду Python
find_python() {
    # Проверяем возможные варианты
    for cmd in python python3; do
        if command -v "$cmd" >/dev/null 2>&1; then
            echo "$cmd"
            return 0
        fi
    done
    echo "ОШИБКА: Python не найден. Установите Python 3 и повторите попытку." >&2
    exit 1
}

PYTHON_CMD=$(find_python)
echo "Используем Python: $($PYTHON_CMD --version 2>&1)"

# Загрузка и распаковка
echo "Загрузка PMP..."
cd /tmp || exit 1
wget -q "https://github.com/majkl84/PMP_2/archive/refs/tags/PMP_R.1.0.0.tar.gz" -O pmp.tar.gz
tar xfz pmp.tar.gz

# Копирование файлов
echo "Копирование файлов в $PROJECT_DIR..."
mkdir -p "$PROJECT_DIR"
find . -mindepth 1 \( -name 'install_pmp.sh' -o -name '.gitignore' -o -name 'LICENSE' \) -prune -o \
    -exec cp -r --parents '{}' "$PROJECT_DIR/" \;

# Создание venv
echo "Создание virtualenv..."
"$PYTHON_CMD" -m venv "$VENV_DIR" || {
    echo "ОШИБКА: Не удалось создать virtualenv" >&2
    exit 1
}
source "$VENV_DIR/bin/activate"

# Установка зависимостей
if [ -f "$PROJECT_DIR/requirements.txt" ]; then
    pip install -r "$PROJECT_DIR/requirements.txt" || {
        echo "ОШИБКА: Не удалось установить зависимости" >&2
        exit 1
    }
else
    echo "Файл requirements.txt не найден!" >&2
    exit 1
fi

# Настройка systemd
echo "Настройка systemd сервиса..."
cat > /etc/systemd/system/pmp.service <<EOF
[Unit]
Description=PMP Service
After=network.target

[Service]
User=pmp
Group=pmp
WorkingDirectory=$PROJECT_DIR
Environment="PATH=$VENV_DIR/bin:/usr/local/bin:/usr/bin:/bin"
ExecStart=$VENV_DIR/bin/python $PROJECT_DIR/app.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Запуск сервиса
systemctl daemon-reload
systemctl enable --now pmp.service

# Проверка
if systemctl is-active --quiet pmp.service; then
    echo "Установка успешно завершена"
    rm -rf "/tmp/${PMP_VERSION}" "/tmp/pmp.tar.gz"
else
    echo "ОШИБКА: Сервис не запущен. Проверьте логи:" >&2
    journalctl -u pmp.service -b --no-pager >&2
    exit 1
fi