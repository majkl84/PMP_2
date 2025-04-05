import sqlite3
from config import SQLITE_DB

def execute_query(query, params=(), fetchone=False):
    try:
        conn = sqlite3.connect(SQLITE_DB)
        cursor = conn.cursor()
        cursor.execute(query, params)
        result = cursor.fetchone() if fetchone else cursor.fetchall()
        conn.commit()
        return result
    except sqlite3.Error as e:
        print(f"Ошибка при работе с БД: {e}")
        return None
    finally:
        conn.close()

def initialize_database():
    conn = sqlite3.connect(SQLITE_DB)
    cursor = conn.cursor()

    tables = {
        "raw_data": """
            CREATE TABLE IF NOT EXISTS raw_data (
                id INTEGER PRIMARY KEY,
                L1raw INTEGER DEFAULT 0,
                L2raw INTEGER DEFAULT 0,
                L3raw INTEGER DEFAULT 0,
                timestamp TEXT DEFAULT CURRENT_TIMESTAMP
            );
        """,
        "total_data": """
            CREATE TABLE IF NOT EXISTS total_data (
                id INTEGER PRIMARY KEY,
                L1total REAL DEFAULT 0,
                L2total REAL DEFAULT 0,
                L3total REAL DEFAULT 0,
                timestamp TEXT DEFAULT CURRENT_TIMESTAMP
            );
        """,
        "historical_data": """
            CREATE TABLE IF NOT EXISTS historical_data (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                L1history REAL,
                L2history REAL,
                L3history REAL,
                timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
            );
        """,
        "logs": """
            CREATE TABLE IF NOT EXISTS logs (
                timestamp TEXT DEFAULT CURRENT_TIMESTAMP,
                message TEXT
            );
        """,
        "settings": """
            CREATE TABLE IF NOT EXISTS settings (
                id INTEGER PRIMARY KEY,
                logging_enabled BOOLEAN NOT NULL DEFAULT 0
            );
        """
    }

    for table, query in tables.items():
        cursor.execute(query)
        if table in ["raw_data", "total_data"]:
            cursor.execute(f"INSERT OR IGNORE INTO {table} (id, {', '.join(['L1' + ('raw' if table == 'raw_data' else 'total'), 'L2' + ('raw' if table == 'raw_data' else 'total'), 'L3' + ('raw' if table == 'raw_data' else 'total')])}) VALUES (1, 0, 0, 0)")

        # Инициализация таблицы settings
        if table == "settings":
            cursor.execute("INSERT OR IGNORE INTO settings (id, logging_enabled) VALUES (1, 0)")

    conn.commit()
    conn.close()

def get_logging_state():
    query = "SELECT logging_enabled FROM settings WHERE id = 1"
    result = execute_query(query, fetchone=True)
    return result[0] if result else None

def set_logging_state(enabled):
    query = "UPDATE settings SET logging_enabled = ? WHERE id = 1"
    execute_query(query, (enabled,))