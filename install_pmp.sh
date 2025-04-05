#!/bin/bash
#---------------------------------------------------------------------
# Script to Install PMP on Linux
# Developed by Majkl84 in 2025
#---------------------------------------------------------------------
# https://github.com/majkl84/PMP_2

set -e  # Прерывать при ошибках
set -x  # Включить отладочный режим (вывод всех команд)

PMP_VERSION="PMP_2-PMP_R.1.0.0"
PROJECT_DIR="/opt/pmp"  # Изменено на /opt/pmp для избежания проблем с правами
VENV_DIR="$PROJECT_DIR/venv"

# Скачивание и распаковка
echo "Скачивание архива..."
cd /tmp
wget "https://github.com/majkl84/PMP_2/archive/refs/tags/PMP_R.1.0.0.tar.gz" -O pmp.tar.gz
tar xfz pmp.tar.gz
cd "$PMP_VERSION"

# Определение версии Python из pyproject.toml
echo "Определение версии Python из pyproject.toml..."
PYTHON_VERSION=$(grep -oP 'requires-python\s*=\s*">=\K[0-9]+\.[0-9]+' pyproject.toml || {
    echo "Ошибка: Не удалось определить requires-python из pyproject.toml";
    exit 1;
})
echo "Требуемая версия Python: >=${PYTHON_VERSION}"

# Установка uv
if ! command -v uv &> /dev/null; then
    echo "Установка uv..."
    curl -LsS https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.cargo/bin:$PATH"
fi

# Проверка и установка нужной версии Python
if ! uv python find "${PYTHON_VERSION}" &>/dev/null; then
    echo "Установка Python ${PYTHON_VERSION} через uv..."
    uv python install "${PYTHON_VERSION}"
fi

# Копирование файлов (сохранение прав)
echo "Копирование файлов проекта..."
mkdir -p "$PROJECT_DIR"
cp -r . "$PROJECT_DIR/"
chown -R root:root "$PROJECT_DIR"  # Изменено на root:root для совместимости с системной директорией

# Создание системного пользователя
if ! id pmp &>/dev/null; then
    echo "Создание системного пользователя pmp..."
    useradd -rs /bin/false pmp
fi
chown -R pmp:pmp "$PROJECT_DIR"

# Создание venv с нужной версией Python
echo "Создание виртуального окружения с помощью uv..."
if ! uv venv -p "$(uv python find ${PYTHON_VERSION})" "$VENV_DIR"; then
    echo "Ошибка: Не удалось создать venv";
    exit 1;
fi

# Проверка наличия pip
if [ ! -f "$VENV_DIR/bin/pip" ]; then
    echo "Файл pip не найден. Установка pip вручную..."
    curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py
    "$VENV_DIR/bin/python" get-pip.py
    rm get-pip.py
fi

# Установка зависимостей из pyproject.toml
echo "Установка зависимостей с помощью uv..."
if ! uv pip install -e "$PROJECT_DIR"; then
    echo "Ошибка: Не удалось установить зависимости";
    exit 1;
fi

# Systemd сервис
echo "Создание systemd-сервиса..."
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

# Запуск сервиса
echo "Запуск сервиса..."
systemctl daemon-reload
systemctl enable pmp.service
systemctl start pmp.service

# Проверка
echo "Установка завершена. Проверка:"
echo "Версия Python: $("$VENV_DIR/bin/python" --version 2>&1)"
echo "Требуемая версия: >=${PYTHON_VERSION}"
systemctl status pmp.service --no-pager

# После успешного запуска сервиса
if systemctl is-active --quiet pmp.service; then
    echo "Удаление временных файлов..."
    rm -rf "/tmp/${PMP_VERSION}" "/tmp/pmp.tar.gz"
else
    echo "Ошибка: сервис не запущен. Файлы сохранены в /tmp для диагностики"
    exit 1
fi