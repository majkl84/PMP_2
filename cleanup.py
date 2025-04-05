# Очистка исторических данных
import sqlite3
from config import SQLITE_DB

def cleanup_historical_data():
    conn = sqlite3.connect(SQLITE_DB)
    cursor = conn.cursor()

    cursor.execute("""
        DELETE FROM historical_data 
        WHERE timestamp < datetime('now', '-72 hours')
    """)
    conn.commit()
    conn.close()

# Очистка логов
def cleanup_logs():
    conn = sqlite3.connect(SQLITE_DB)
    cursor = conn.cursor()
    cursor.execute("""
        DELETE FROM logs 
        WHERE timestamp < datetime('now', '-24 hours')
    """)
    conn.commit()
    conn.close()
