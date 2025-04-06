#!/bin/bash
#---------------------------------------------------------------------
# Script to Install PMP on Linux
# Developed by Majkl84 in 2025-04
#---------------------------------------------------------------------
# https://github.com/majkl84/PMP_2

set -e  # Прерывать при ошибках
PMP_VERSION="PMP_2-PMP_R.1.0.0"
PROJECT_DIR="/usr/bin/pmp"

# 1. Установка uv
echo "Установка uv..."
curl -LsSf https://astral.sh/uv/install.sh | sh
if [ $? -ne 0 ]; then
    echo "Ошибка при установке uv."
    exit 1
fi

# 2. Добавление uv в PATH
echo "Добавление uv в PATH..."
if ! grep -q 'export PATH="$HOME/.local/bin:$PATH"' ~/.bashrc; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
    source ~/.bashrc
    echo "PATH обновлен."
else
    echo "uv уже добавлен в PATH."
fi

# 3. Проверка установки
echo "Проверка установки uv..."
if command -v uv &>/dev/null; then
    echo "uv установлен успешно. Версия: $(uv --version)"
else
    echo "uv не найден. Убедитесь, что установка завершилась успешно."
    exit 1
fi

# Скачивание и распаковка
cd /tmp
wget "https://github.com/majkl84/PMP_2/archive/refs/tags/PMP_R.1.0.0.tar.gz" -O pmp.tar.gz
tar xfz pmp.tar.gz
cd "$PMP_VERSION"
# Копирование файлов (сохранение прав)
mkdir -p "$PROJECT_DIR"
find . -mindepth 1 \( -name 'READMI.MD' -o -name 'install_pmp.sh' -o -name '.gitignore' -o -name 'LICENSE' \) -prune -o -exec cp -r --parents '{}' "$PROJECT_DIR/" \;

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

# Systemd сервис
cat > /etc/systemd/system/pmp.service <<EOF
[Unit]
Description=PMP Service
After=network.target

[Service]
User=root
Group=root
WorkingDirectory=/usr/bin/pmp
Environment="PATH=/root/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
Environment="PYTHONPATH=/usr/bin/pmp"
Environment="HOME=/root"
ExecStart=/root/.local/bin/uv run /usr/bin/pmp/app.py
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