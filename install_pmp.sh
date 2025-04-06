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

# Функция для выхода с ошибкой
error_exit() {
    echo "ОШИБКА: $1" >&2
    exit 1
}

# Функция точного определения требуемой версии Python
get_required_python() {
    local toml_file="$1"
    [ -f "$toml_file" ] || error_exit "Файл $toml_file не найден"

    # Извлекаем строку requires-python
    local requirement
    requirement=$(grep -E '^requires-python' "$toml_file" | cut -d'"' -f2 | cut -d"'" -f2)

    # Если не указано, возвращаем пустую строку
    [ -z "$requirement" ] && return 0

    # Возвращаем полное условие (например ">=3.12")
    echo "$requirement"
}

# Проверка соответствия версии Python
check_python_version() {
    local requirement="$1"
    local python_cmd="${2:-python3}"

    echo "Проверка Python (требуется $requirement)..."

    # Запускаем Python-код для проверки версии
    "$python_cmd" -c "
import sys
import re

requirement = '$requirement'
if not requirement:
    sys.exit(0)

# Парсим условие
op = re.match(r'^([>=<~!]+)', requirement)
op = op.group(1) if op else '=='
ver = requirement.replace(op, '')

# Преобразуем версию в кортеж
try:
    required_ver = tuple(map(int, ver.split('.')))
except:
    sys.exit(1)

current_ver = (sys.version_info.major, sys.version_info.minor)

# Сравниваем в зависимости от оператора
if op == '>=':
    sys.exit(0) if current_ver >= required_ver else sys.exit(1)
elif op == '>':
    sys.exit(0) if current_ver > required_ver else sys.exit(1)
elif op == '<=':
    sys.exit(0) if current_ver <= required_ver else sys.exit(1)
elif op == '<':
    sys.exit(0) if current_ver < required_ver else sys.exit(1)
elif op == '~=':
    sys.exit(0) if current_ver >= required_ver and current_ver[0] == required_ver[0] else sys.exit(1)
else:  # == или нет оператора
    sys.exit(0) if current_ver == required_ver else sys.exit(1)
    " || {
        local current_ver=$("$python_cmd" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
        error_exit "Версия Python $current_ver не соответствует требованию $requirement"
    }
}

# Установка Python (если нужно)
install_python() {
    local version="$1"
    echo "Попытка установки Python $version..."

    if grep -q 'Debian' /etc/os-release || grep -q 'Ubuntu' /etc/os-release; then
        apt-get install -y software-properties-common
        add-apt-repository -y ppa:deadsnakes/ppa
        apt-get update
        apt-get install -y "python$version" "python$version-venv" || {
            error_exit "Не удалось установить Python $version"
        }
    else
        error_exit "Автоматическая установка поддерживается только для Debian/Ubuntu"
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

    # Определяем требуемую версию Python
    PYTHON_REQUIREMENT=$(get_required_python "pyproject.toml")
    MIN_PYTHON=$(echo "$PYTHON_REQUIREMENT" | sed -E 's/^[>=<~!]+//')
    MIN_PYTHON=${MIN_PYTHON:-"3.8"}  # Значение по умолчанию

    # Пытаемся использовать системный Python
    PYTHON_CMD="python3"
    if [ -n "$PYTHON_REQUIREMENT" ]; then
        if ! check_python_version "$PYTHON_REQUIREMENT" "$PYTHON_CMD"; then
            install_python "$MIN_PYTHON"
            PYTHON_CMD="python${MIN_PYTHON}"
            check_python_version "$PYTHON_REQUIREMENT" "$PYTHON_CMD"
        fi
    fi

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