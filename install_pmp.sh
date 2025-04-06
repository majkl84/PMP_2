#!/bin/bash
#--------------------------------------------------------------------
# Скрипт для установки PMP в Linux
# Разработан Majkl84 в 2025-04
#---------------------------------------------------------------------
# https://github.com/majkl84/PMP_2

set -euo pipefail

# Конфигурация
PMP_VERSION="PMP_2-PMP_R.1.0.0"
PROJECT_DIR="/opt/pmp"  # Изменено на стандартную директорию
VENV_DIR="$PROJECT_DIR/.venv"
TMP_DIR=$(mktemp -d)

# Функция для выхода с ошибкой
error_exit() {
    echo "ОШИБКА: $1" >&2
    exit 1
}

# Определяем требуемую версию Python из pyproject.toml
get_python_version() {
    local toml_file="$1"
    if [ ! -f "$toml_file" ]; then
        error_exit "Файл $toml_file не найден"
    fi

    local version
    version=$(grep -E '^requires-python' "$toml_file" | cut -d'"' -f2 | sed 's/>=//')

    if [ -z "$version" ]; then
        echo "3.12"  # Версия по умолчанию
    else
        echo "$version"
    fi
}

# Установка нужной версии Python
install_python() {
    local required_version=$1
    if ! command -v "python$required_version" >/dev/null; then
        echo "Установка Python $required_version..."
        apt-get update && apt-get install -y "python$required_version" || {
            error_exit "Не удалось установить Python $required_version"
        }
    fi
}

# Основной процесс установки
main() {
    # Проверка прав
    [[ $(id -u) -eq 0 ]] || error_exit "Требуются права root"

    # Скачивание и распаковка
    echo "Загрузка PMP..."
    cd "$TMP_DIR" || error_exit "Не удалось перейти в $TMP_DIR"
    wget -q "https://github.com/majkl84/PMP_2/archive/refs/tags/PMP_R.1.0.0.tar.gz" -O pmp.tar.gz
    tar xfz pmp.tar.gz
    cd "$PMP_VERSION" || error_exit "Не найдена директория $PMP_VERSION"

    # Определение версии Python
    PYTHON_VERSION=$(get_python_version "pyproject.toml")
    echo "Требуется Python $PYTHON_VERSION"
    install_python "$PYTHON_VERSION"

    # Копирование файлов
    echo "Установка в $PROJECT_DIR..."
    mkdir -p "$PROJECT_DIR"
    find . -mindepth 1 \( -name 'install_pmp.sh' -o -name '.gitignore' -o -name 'LICENSE' \) -prune -o \
        -exec cp -r --parents '{}' "$PROJECT_DIR/" \;
    cd "$PROJECT_DIR" || error_exit "Не удалось перейти в $PROJECT_DIR"

    # Создание virtualenv
    echo "Создание virtualenv..."
    "python$PYTHON_VERSION" -m venv "$VENV_DIR" || error_exit "Ошибка создания virtualenv"

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

