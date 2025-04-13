from datetime import datetime
from database import execute_query


def log_message(message: str):
    """
    Записывает сообщение в таблицу logs базы данных, если логирование включено в настройках.

    :param message: Текст сообщения для логирования
    """
    try:
        # Проверяем, включено ли логирование в настройках
        query = "SELECT logging_enabled FROM settings WHERE id = 1"
        result = execute_query(query, fetchone=True)

        if result and result[0]:  # Если логирование включено
            # Вставляем сообщение в таблицу logs
            insert_query = "INSERT INTO logs (timestamp, message) VALUES (?, ?)"
            timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
            execute_query(insert_query, (timestamp, message))
    except Exception as e:
        print(f"Ошибка при записи лога: {e}")