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

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

error_exit() {
    echo -e "${RED}ОШИБКА: $1${NC}" >&2
    exit 1
}

info_msg() {
    echo -e "${GREEN}$1${NC}"
}

# Поиск любого доступного Python (3.6+)
find_any_python() {
    # Проверяем стандартные имена python
    for py in python3 python; do
        if command -v "$py" >/dev/null; then
            # Проверяем что это Python 3.x
            if "$py" -c "import sys; sys.exit(0) if sys.version_info[0] == 3 else sys.exit(1)"; then
                echo "$py"
                return 0
            fi
        fi
    done
    error_exit "Не найден интерпретатор Python 3.x"
}

# Устанавливаем пакет, игнорируя требования Python
install_ignore_python_requires() {
    local pkg_dir="$1"
    cd "$pkg_dir" || error_exit "Не удалось перейти в $pkg_dir"

    # Создаем временный setup.py для принудительной установки
    cat > setup.py <<EOF
from setuptools import setup

setup(
    name="pmp-forced-install",
    version="1.0.0",
    install_requires=open('requirements.txt').read().splitlines(),
)
EOF

    pip install --no-deps -e . || {
        warn_msg "Не удалось установить в режиме разработки, пробуем обычную установку"
        pip install .
    }
}

main() {
    # Проверка прав
    [[ $(id -u) -eq 0 ]] || error_exit "Требуются права root"

    # Поиск Python
    PYTHON_CMD=$(find_any_python)
    PYTHON_VERSION=$("$PYTHON_CMD" --version 2>&1)
    info_msg "Используем Python: $PYTHON_VERSION"

    # Скачивание и распаковка
    info_msg "Загрузка PMP..."
    cd "$TMP_DIR" || error_exit "Не удалось перейти в $TMP_DIR"
    curl -fsSL "https://github.com/majkl84/PMP_2/archive/refs/tags/PMP_R.1.0.0.tar.gz" -o pmp.tar.gz
    tar xfz pmp.tar.gz

    # Копирование файлов
    info_msg "Установка в $PROJECT_DIR..."
    mkdir -p "$PROJECT_DIR"
    find . -mindepth 1 \( -name 'install_pmp.sh' -o -name '.gitignore' -o -name 'LICENSE' \) -prune -o \
        -exec cp -r --parents '{}' "$PROJECT_DIR/" \;
    cd "$PROJECT_DIR" || error_exit "Не удалось перейти в $PROJECT_DIR"

    # Создание virtualenv
    info_msg "Создание virtualenv..."
    "$PYTHON_CMD" -m venv "$VENV_DIR" || error_exit "Ошибка создания virtualenv"

    # Установка зависимостей (игнорируя требования Python)
    info_msg "Установка зависимостей..."
    source "$VENV_DIR/bin/activate"
    pip install --upgrade pip
    pip install wheel

    if [ -f "$PROJECT_DIR/requirements.txt" ]; then
        pip install -r "$PROJECT_DIR/requirements.txt"
    fi

    # Принудительная установка самого пакета
    install_ignore_python_requires "$PROJECT_DIR"

    # Настройка пользователя
    if ! id pmp &>/dev/null; then
        useradd -rs /bin/false pmp || error_exit "Ошибка создания пользователя pmp"
    fi
    chown -R pmp:pmp "$PROJECT_DIR"

    # Настройка systemd
    info_msg "Настройка systemd сервиса..."
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
        info_msg "Установка успешно завершена!"
        rm -rf "$TMP_DIR"
    else
        error_exit "Сервис не запущен. Проверьте логи: journalctl -u pmp.service -b"
    fi
}

main