#!/bin/bash
#--------------------------------------------------------------------
# Скрипт для установки PMP в Linux
# Разработан Majkl84 в 2025-04
#---------------------------------------------------------------------
# https://github.com/majkl84/PMP_2

set -euo pipefail

# Конфигурация
PMP_VERSION="PMP_2-PMP_R.1.0.0"
PROJECT_DIR="/opt/pmp"
VENV_DIR="$PROJECT_DIR/.venv"
TMP_DIR=$(mktemp -d)

# Функция поиска доступного Python
find_python() {
    # Проверяем возможные варианты Python в порядке предпочтения
    for py in python3.12 python3.11 python3.10 python3.9 python3 python; do
        if command -v "$py" >/dev/null; then
            echo "$py"
            return 0
        fi
    done
    error_exit "Не найден ни один интерпретатор Python"
}

# Функция для выхода с ошибкой
error_exit() {
    echo "ОШИБКА: $1" >&2
    exit 1
}

# Основной процесс установки
main() {
    # Проверка прав
    [[ $(id -u) -eq 0 ]] || error_exit "Требуются права root"

    # Поиск Python
    PYTHON_CMD=$(find_python)
    echo "Используем Python: $($PYTHON_CMD --version 2>&1)"

    # Скачивание и распаковка
    echo "Загрузка PMP..."
    cd "$TMP_DIR" || error_exit "Не удалось перейти в $TMP_DIR"
    wget -q "https://github.com/majkl84/PMP_2/archive/refs/tags/PMP_R.1.0.0.tar.gz" -O pmp.tar.gz
    tar xfz pmp.tar.gz
    cd "$PMP_VERSION" || error_exit "Не найдена директория $PMP_VERSION"

    # Копирование файлов
    echo "Установка в $PROJECT_DIR..."
    mkdir -p "$PROJECT_DIR"
    find . -mindepth 1 \( -name 'install_pmp.sh' -o -name '.gitignore' -o -name 'LICENSE' \) -prune -o \
        -exec cp -r --parents '{}' "$PROJECT_DIR/" \;
    cd "$PROJECT_DIR" || error_exit "Не удалось перейти в $PROJECT_DIR"

    # Создание virtualenv
    echo "Создание virtualenv..."
    "$PYTHON_CMD" -m venv "$VENV_DIR" || error_exit "Ошибка создания virtualenv"

    # Установка зависимостей
    echo "Установка зависимостей..."
    source "$VENV_DIR/bin/activate"
    pip install --upgrade pip

    [ -f "pyproject.toml" ] && pip install -e .

    # Настройка пользователя
    if ! id pmp &>/dev/null; then
        useradd -rs /bin/false pmp || error_exit "Ошибка создания пользователя pmp"
    fi
    chown -R pmp:pmp "$PROJECT_DIR"

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
Environment="PATH=$VENV_DIR/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
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
        echo "Установка успешно завершена!"
        rm -rf "$TMP_DIR"
    else
        error_exit "Сервис не запущен. Проверьте логи: journalctl -u pmp.service -b"
    fi
}

main