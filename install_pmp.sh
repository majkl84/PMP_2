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
    UV_PATH=$(which uv)
    if [ -z "$UV_PATH" ]; then
        echo "Ошибка: uv не был установлен корректно"
        exit 1
    fi

    # Если uv установился не в /usr/local/bin, копируем его туда
    if [ "$UV_PATH" != "/usr/local/bin/uv" ]; then
        echo "Копирование uv в /usr/local/bin..."
        cp "$UV_PATH" /usr/local/bin/uv
    fi

    # Проверяем, что uv теперь доступен
    if ! command -v uv &> /dev/null; then
        echo "Ошибка: uv не доступен после установки"
        exit 1
    fi

    echo "uv успешно установлен"
fi

# Убедимся, что /usr/local/bin/uv существует и имеет правильные разрешения
if [ -f "/usr/local/bin/uv" ]; then
    chmod 755 /usr/local/bin/uv
else
    echo "Ошибка: /usr/local/bin/uv не существует после установки"
    exit 1
fi

# Копирование файлов (сохранение прав)
mkdir -p "$PROJECT_DIR"
find . -mindepth 1 \(  -name 'install_pmp.sh' -o -name '.gitignore' -o -name 'LICENSE' \) -prune -o -exec cp -r --parents '{}' "$PROJECT_DIR/" \;
#cp -r . "$PROJECT_DIR/"

# Создание системного пользователя
if ! id pmp &>/dev/null; then
    useradd -rs /bin/false pmp
fi
# Установка прав доступа
chown -R pmp:pmp "$PROJECT_DIR"
chmod -R 755 "$PROJECT_DIR"

# Убедимся, что pmp имеет доступ к директории с uv
chmod 755 /usr/local/bin
chmod 755 /usr/local/bin/uv

# Если app.py требует права на выполнение
chmod 755 "$PROJECT_DIR/app.py"

# Если есть конфигурационные файлы, которые должны быть доступны только для чтения
find "$PROJECT_DIR" -type f -name "*.conf" -exec chmod 644 {} \;

# Если есть директории, куда pmp должен иметь возможность записи
mkdir -p "$PROJECT_DIR/logs"
chown pmp:pmp "$PROJECT_DIR/logs"
chmod 755 "$PROJECT_DIR/logs"

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