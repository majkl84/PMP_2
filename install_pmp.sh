#!/bin/bash
#--------------------------------------------------------------------
# Скрипт для установки PMP в Linux
# Разработан Majkl84 в 2025-04
#---------------------------------------------------------------------
# https://github.com/majkl84/PMP_2

set -e  # Сохранено без изменений
PMP_VERSION="PMP_2-PMP_R.1.0.0"
PROJECT_DIR="/usr/bin/pmp"
VENV_DIR="$PROJECT_DIR/.venv"

# Установка uv (оптимизированная проверка)
install_uv() {
    echo "Установка uv..."
    if ! curl -LsSf https://astral.sh/uv/install.sh | sh; then
        echo "Ошибка: uv не был установлен корректно" >&2
        exit 1
    fi

    # Оптимизированный поиск uv
    local UV_PATH
    UV_PATH=$(command -v uv || find ~/.local/bin /usr/local/bin -name uv 2>/dev/null | head -1)
    [ -z "$UV_PATH" ] && { echo "Ошибка: uv не найден" >&2; exit 1; }

    # Копирование с минимальным количеством проверок
    if [ "$UV_PATH" != "/usr/local/bin/uv" ]; then
        echo "Копирование uv в /usr/local/bin..."
        { cp "$UV_PATH" /usr/local/bin/uv || sudo cp "$UV_PATH" /usr/local/bin/uv; } &&
        sudo chmod +x /usr/local/bin/uv
    fi
}

# Основной процесс установки
{
    # Скачивание и распаковка (без изменений)
    cd /tmp || exit 1
    wget -q "https://github.com/majkl84/PMP_2/archive/refs/tags/PMP_R.1.0.0.tar.gz" -O pmp.tar.gz
    tar xfz pmp.tar.gz
    cd "$PMP_VERSION" || exit 1

    # Установка uv
    command -v uv >/dev/null || install_uv

    # Копирование файлов (оптимизированный find)
    echo "Копирование файлов..."
    mkdir -p "$PROJECT_DIR"
    find . -mindepth 1 \( -name 'install_pmp.sh' -o -name '.gitignore' -o -name 'LICENSE' \) -prune -o \
        -exec cp -r --parents '{}' "$PROJECT_DIR/" \;

    # Установка зависимостей (объединенные проверки)
    cd "$PROJECT_DIR" || exit 1
    [ -f "pyproject.toml" ] || { echo "Ошибка: pyproject.toml не найден" >&2; exit 1; }

    uv venv &&
    uv pip install -e . || { echo "Ошибка установки зависимостей" >&2; exit 1; }

    # Пользователь и права (без изменений)
    id pmp &>/dev/null || useradd -rs /bin/false pmp
    chown -R pmp:pmp "$PROJECT_DIR"

    # Systemd сервис (оптимизированный запуск)
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

    systemctl daemon-reload
    systemctl enable --now pmp.service

    # Проверка (оптимизированная)
    if systemctl is-active --quiet pmp.service; then
        echo "Установка завершена успешно"
        rm -rf "/tmp/${PMP_VERSION}" "/tmp/pmp.tar.gz"
    else
        echo "Ошибка: сервис не запущен" >&2
        journalctl -u pmp.service -b --no-pager >&2
        exit 1
    fi
}