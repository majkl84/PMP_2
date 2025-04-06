#!/bin/bash
#--------------------------------------------------------------------
# Скрипт для установки PMP в Linux
# Разработан Majkl84 в 2025-04
#--------------------------------------------------------------------
# https://github.com/majkl84/PMP_2

set -euo pipefail

# Конфигурация
PMP_VERSION="PMP_2-PMP_R.1.0.0"
PROJECT_DIR="/usr/bin/pmp"
VENV_DIR="$PROJECT_DIR/.venv"

# Автоматический поиск Python
find_python() {
    # Ищем python3 в стандартных путях
    local python_paths=(
        "/usr/bin/python3"
        "/usr/local/bin/python3"
        "$(command -v python3 2>/dev/null)"
        "$(command -v python 2>/dev/null)"
    )

    for path in "${python_paths[@]}"; do
        if [ -x "$path" ]; then
            echo "$path"
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
cd "$PMP_VERSION"

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

# Установка зависимостей с обработкой ошибок
if [ -f "$PROJECT_DIR/requirements.txt" ]; then
    echo "Установка зависимостей..."
    if ! pip install -r "$PROJECT_DIR/requirements.txt"; then
        echo "Попытка исправить зависимости..."
        pip install --upgrade pip
        # Пропускаем проблемные зависимости
        grep -vE 'pywin32==|docopt==' "$PROJECT_DIR/requirements.txt" > /tmp/filtered_reqs.txt
        pip install -r /tmp/filtered_reqs.txt || {
            echo "ОШИБКА: Не удалось установить основные зависимости" >&2
            exit 1
        }
    fi
else
    echo "Файл requirements.txt не найден! Пытаемся использовать pyproject.toml..."
    pip install -e "$PROJECT_DIR" || {
        echo "ОШИБКА: Не удалось установить зависимости из pyproject.toml" >&2
        exit 1
    }
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
    echo "Попробуйте запустить вручную:" >&2
    echo "sudo -u pmp $VENV_DIR/bin/python $PROJECT_DIR/app.py" >&2
    exit 1
fi