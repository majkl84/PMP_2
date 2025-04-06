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

# Установка uv (минимальная версия)
if ! command -v uv &> /dev/null; then
    echo "Установка uv..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$PATH"
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

# Права (минимально необходимые)
chown -R pmp:pmp "$PROJECT_DIR"
chmod 755 "$PROJECT_DIR/app.py"

# Systemd сервис (чистая версия)
cat > /etc/systemd/system/pmp.service <<EOF
[Unit]
Description=PMP Service
After=network.target

[Service]
User=pmp
Group=pmp
WorkingDirectory=$PROJECT_DIR
ExecStart=uv run $PROJECT_DIR/app.py
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