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
    echo "Установка uv..."
    curl -LsSf https://astral.sh/uv/install.sh | sh

    # Проверяем, куда установился uv
    UV_PATH=$(command -v uv || echo "")
    if [ -z "$UV_PATH" ]; then
        # Проверяем стандартные пути установки
        if [ -f "$HOME/.local/bin/uv" ]; then
            UV_PATH="$HOME/.local/bin/uv"
        else
            echo "Ошибка: uv не был установлен корректно"
            exit 1
        fi
    fi

    # Если uv установился не в /usr/local/bin, копируем его туда
    if [ "$UV_PATH" != "/usr/local/bin/uv" ]; then
        echo "Копирование uv в /usr/local/bin..."

        # Проверяем права на запись
        if [ ! -w "/usr/local/bin" ]; then
            echo "Требуются права sudo для копирования в /usr/local/bin"
            sudo cp "$UV_PATH" /usr/local/bin/uv || {
                echo "Ошибка: не удалось скопировать uv в /usr/local/bin"
                exit 1
            }
        else
            cp "$UV_PATH" /usr/local/bin/uv || {
                echo "Ошибка: не удалось скопировать uv"
                exit 1
            }
        fi

        # Проверяем, что копирование прошло успешно
        if [ ! -f "/usr/local/bin/uv" ]; then
            echo "Ошибка: uv не был скопирован в /usr/local/bin"
            exit 1
        fi

        # Устанавливаем права на исполнение
        sudo chmod +x /usr/local/bin/uv
    fi

    # Проверяем, что uv теперь доступен
    if ! command -v uv &> /dev/null; then
        echo "Ошибка: uv не доступен после установки"
        exit 1
    fi

    echo "uv успешно установлен в /usr/local/bin/"
fi

# Копирование файлов (сохранение прав)
mkdir -p "$PROJECT_DIR"
find . -mindepth 1 \(  -name 'install_pmp.sh' -o -name '.gitignore' -o -name 'LICENSE' \) -prune -o -exec cp -r --parents '{}' "$PROJECT_DIR/" \;

# Установка зависимостей проекта
echo "Установка зависимостей Python..."
cd "$PROJECT_DIR"
if [ -f "pyproject.toml" ]; then
    # Создаем виртуальное окружение
    uv venv

    uv pip install -e .

else
    echo "Ошибка: файл pyproject.toml не найден в $PROJECT_DIR"
    exit 1
fi

# Создание системного пользователя
if ! id pmp &>/dev/null; then
    useradd -rs /bin/false pmp
fi

# Установка прав доступа
chown -R pmp:pmp "$PROJECT_DIR"
chmod -R 755 "$PROJECT_DIR"

# Если app.py требует права на выполнение
chmod 755 "$PROJECT_DIR/app.py"

# Если есть конфигурационные файлы, которые должны быть доступны только для чтения
find "$PROJECT_DIR" -type f -name "*.conf" -exec chmod 644 {} \;

# Systemd сервис
cat > /etc/systemd/system/pmp.service <<EOF
[Unit]
Description=PMP Service
After=network.target

[Service]
User=pmp
Group=pmp
WorkingDirectory=$PROJECT_DIR
ExecStart=$PROJECT_DIR/.venv/bin/python $PROJECT_DIR/app.py
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