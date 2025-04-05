import time
import json
from flask import Flask, render_template, request, jsonify
from config import (MQTT_TOPICS, MODBUS_HOSTS, SQLITE_DB, LOGGING_ENABLED, PREVIOUS_ENERGY)
from database import initialize_database, execute_query, get_logging_state, set_logging_state
from mqtt_handler import connect_mqtt, publish_mqtt, log_message
from modbus_handler import *
from datetime import datetime, timezone, timedelta  # Импортируем необходимые классы
from cleanup import cleanup_logs, cleanup_historical_data

# Инициализация Flask
app = Flask(__name__)

# Функция для корректного вычитания с учетом переполнения
def calculate_difference(new_value, old_value):
    if new_value >= old_value:
        return new_value - old_value
    else:
        if old_value < 65536:
            return (65536 - old_value) + new_value
        else:
            return (old_value - 65536) + new_value

# Функция для получения текущего времени в формате UTC+3
def get_current_time_utc_plus_3():
    return (datetime.now(timezone.utc) + timedelta(hours=3)).isoformat()

# Сохранение сырых данных в SQLite
def save_raw_data(data):
    if any(data.get(key, 0) < 0 or data.get(key, 0) > 65535 for key in ["L1raw", "L2raw", "L3raw"]):
        return  # Если данные невалидны, выходим

    execute_query("""
        INSERT INTO raw_data (id, L1raw, L2raw, L3raw, timestamp)
        VALUES (1, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET 
            L1raw = excluded.L1raw,
            L2raw = excluded.L2raw,
            L3raw = excluded.L3raw,
            timestamp = excluded.timestamp
    """, (data.get("L1raw", 0), data.get("L2raw", 0), data.get("L3raw", 0), get_current_time_utc_plus_3()))

# Сохранение исторических данных
def save_historical_data(raw_data):
    execute_query("""
        INSERT INTO historical_data (L1history, L2history, L3history, timestamp)
        VALUES (?, ?, ?, ?)
    """, (raw_data["L1raw"], raw_data["L2raw"], raw_data["L3raw"], get_current_time_utc_plus_3()))

# Обновление общих данных в SQLite
def update_total_data(raw_data):
    existing_raw_data = execute_query("SELECT * FROM raw_data WHERE id = 1", fetchone=True)
    if not existing_raw_data:
        return

    old_L1raw, old_L2raw, old_L3raw = existing_raw_data[1:4]
    if old_L1raw == old_L2raw == old_L3raw == 0:
        save_raw_data(raw_data)
        return

    existing_total_data = execute_query("SELECT * FROM total_data WHERE id = 1", fetchone=True)
    # log_message(f"Existing raw data - L1raw: {old_L1raw}, L2raw: {old_L2raw}, L3raw: {old_L3raw}")
    # log_message(f"Existing total data - L1total: {existing_total_data[1]}, L2total: {existing_total_data[2]}, L3total: {existing_total_data[3]}")

    L1Difference = calculate_difference(raw_data["L1raw"], old_L1raw)
    L2Difference = calculate_difference(raw_data["L2raw"], old_L2raw)
    L3Difference = calculate_difference(raw_data["L3raw"], old_L3raw)

    # log_message(f"Calculated differences - L1: {L1Difference}, L2: {L2Difference}, L3: {L3Difference}")
    L1Total = existing_total_data[1] + L1Difference
    L2Total = existing_total_data[2] + L2Difference
    L3Total = existing_total_data[3] + L3Difference

    total_kWh = round((L1Total + L2Total + L3Total) / 1000, 2)
    publish_mqtt(MQTT_TOPICS["total_kWh"], str(total_kWh))

    # log_message(f"Updating totals - L1Total: {L1Total}, L2Total: {L2Total}, L3Total: {L3Total}, total_kWh: {total_kWh:.1f}")

    execute_query("""
        UPDATE total_data
        SET L1total = ?, L2total = ?, L3total = ?, timestamp = ?
        WHERE id = 1
    """, (L1Total, L2Total, L3Total, get_current_time_utc_plus_3()))

# Обработка данных и публикация в MQTT
def process_and_publish_data():
    global PREVIOUS_ENERGY

    while True:
        full_data = {}
        raw_data = {"L1raw": 0, "L2raw": 0, "L3raw": 0}

        total_power = 0.0  # Инициализация переменной для общей мощности

        for phase, config in MODBUS_HOSTS.items():
            data = read_modbus_data(config["host"], config["unit_id"])
            if data is None:
                continue

            # Сохраняем сырые данные о мощности и энергии
            raw_data[f"{phase}raw"] = data["Energy"]  # Сохраняем данные о энергии
            total_power += round((data["Power"]), 2)  # Суммируем мощность

            publish_mqtt(MQTT_TOPICS[f"Full_data_{phase}"], json.dumps({
                f"{phase}U": data["Voltage"],
                f"{phase}A": data["Current"],
                f"{phase}W": data["Power"],
                f"{phase}Wh": data["Energy"],
                f"{phase}F_Wh": data["Energy_F"],
                f"{phase}Hz": data["Frequency"],
                f"{phase}Pf": data["PowerFactor"],
                f"{phase}Alarm": data["AlarmStatus"]
            }))

            diff_energy = calculate_difference(data["Energy"], PREVIOUS_ENERGY[phase])
            full_data.update({f"{phase}_diff_Energy": diff_energy})
            # log_message(f"Energy difference for {phase}: {diff_energy} (new: {data['Energy']}, previous: {PREVIOUS_ENERGY[phase]})")
            PREVIOUS_ENERGY[phase] = data["Energy"]

        update_total_data(raw_data)
        save_raw_data(raw_data)
        save_historical_data(raw_data)

        # Получение существующих сырых данных для проверки переполнения
        existing_raw_data = {"L1raw": raw_data["L1raw"], "L2raw": raw_data["L2raw"], "L3raw": raw_data["L3raw"]}
        overflow_results = {
            "L1_overflow_error": int(calculate_difference(raw_data["L1raw"], existing_raw_data["L1raw"])),
            "L2_overflow_error": int(calculate_difference(raw_data["L2raw"], existing_raw_data["L2raw"])),
            "L3_overflow_error": int(calculate_difference(raw_data["L3raw"], existing_raw_data["L3raw"])),
            "timestamp": get_current_time_utc_plus_3()
        }
        publish_mqtt(MQTT_TOPICS["overflow_error"], json.dumps(overflow_results))

        cleanup_historical_data()
        cleanup_logs()
        # Публикация общей мощности в MQTT
        publish_mqtt(MQTT_TOPICS["General-W"], str(round(total_power, 2)))

        time.sleep(10)

# Получение сырых данных из БД
@app.route("/raw_data")
def get_raw_data():
    row = execute_query("SELECT * FROM raw_data ORDER BY timestamp DESC LIMIT 1", fetchone=True)
    if row:
        labels = ['id', 'L1raw', 'L2raw', 'L3raw', 'timestamp']
        return jsonify(dict(zip(labels, row)))
    return jsonify({})

# Получение общих данных из БД
@app.route("/total_data")
def get_total_data():
    row = execute_query("SELECT * FROM total_data ORDER BY timestamp DESC LIMIT 1", fetchone=True)
    if row:
        labels = ['id', 'L1total', 'L2total', 'L3total', 'timestamp']
        return jsonify(dict(zip(labels, row)))
    return jsonify({})
# Получение данных для каждой фазы
@app.route("/data")
def get_data():
    full_data = {}
    for phase, config in MODBUS_HOSTS.items():
        data = read_modbus_data(config["host"], config["unit_id"])
        if data:
            full_data[phase] = data
    return jsonify(full_data)

# Получение логов из БД
@app.route("/logs")
def get_logs():
    if not get_logging_state():  # Проверяем состояние логирования
        return jsonify([])  # Если логирование отключено, возвращаем пустой массив

    limit = request.args.get('limit', default=10, type=int)  # Получаем параметр limit
    rows = execute_query(f"SELECT * FROM logs ORDER BY timestamp DESC LIMIT {limit}")
    return jsonify([{"timestamp": row[0], "message": row[1]} for row in rows])

# Переключение логирования
@app.route('/toggle_logging', methods=['POST'])
def toggle_logging():
    current_state = get_logging_state()
    new_state = not current_state

    set_logging_state(new_state)

    # Логируем событие
    message = 'Логирование включено' if new_state else 'Логирование отключено'
    execute_query("INSERT INTO logs (message) VALUES (?)", (message,))

    return jsonify({'logging_enabled': new_state})
@app.route('/get_logging_state', methods=['GET'])
def get_logging_state_route():
    state = get_logging_state()
    return jsonify({'logging_enabled': state})
# Очистка логов
@app.route("/clear_logs", methods=["POST"])
def clear_logs():
    execute_query("DELETE FROM logs")
    log_message("Logs cleared")  # Убедитесь, что функция log_message также записывает в базу данных
    execute_query("INSERT INTO logs (message) VALUES (?)", ("Журнал очищен",))
    return jsonify({"status": "success", "message": "Журнал очищен"})

# Главная страница
@app.route("/")
def index():
    return render_template("index.html")

@app.route("/data_page", methods=["GET", "POST"])
def data_page():
    if request.method == "POST":
        data = request.get_json()
        # Проверка на наличие данных для проверки ID
        if 'inputId1' in data and 'inputId2' in data:
            return check_data(data['inputId1'], data['inputId2'])
        # Проверка на наличие данных для запроса исторических данных
        elif 'dateStart' in data and 'dateStop' in data:
            return get_historical_data(data['dateStart'], data['dateStop'])
    return render_template("data_page.html")

def get_historical_data(date_start, date_stop):
    print(f"Запрос исторических данных с {date_start} по {date_stop}")  # Логирование входящих данных
    # Преобразование строк в объекты datetime
    start_datetime = datetime.fromisoformat(date_start.replace("Z", "+00:00"))
    stop_datetime = datetime.fromisoformat(date_stop.replace("Z", "+00:00"))

    rows = execute_query("""
        SELECT * FROM historical_data 
        WHERE timestamp BETWEEN ? AND ? 
        ORDER BY id ASC
    """, (start_datetime.isoformat(), stop_datetime.isoformat()))

    result = []
    for row in rows:
        result.append({
            "id": row[0],
            "L1history": row[1],
            "L2history": row[2],
            "L3history": row[3],
            "timestamp": row[4]
        })
    return jsonify(result) if result else jsonify({"error": "Нет данных для указанных временных рамок."})

def check_data(id1, id2):
    if not id1 or not id2:
        return jsonify({"error": "Оба ID должны быть заданы!"}), 400

    result1 = execute_query("SELECT * FROM historical_data WHERE id = ?", (id1,), fetchone=True)
    result2 = execute_query("SELECT * FROM historical_data WHERE id = ?", (id2,), fetchone=True)

    if not result1 or not result2:
        return jsonify({"error": "Данные не найдены"}), 404

    # Извлекаем старые и новые данные
    newData = {
        "L1history": result1[1],
        "L2history": result1[2],
        "L3history": result1[3]
    }
    oldData = {
        "L1history": result2[1],
        "L2history": result2[2],
        "L3history": result2[3]
    }

    L1Difference = calculate_difference(newData["L1history"], oldData["L1history"])
    L2Difference = calculate_difference(newData["L2history"], oldData["L2history"])
    L3Difference = calculate_difference(newData["L3history"], oldData["L3history"])

    # Возвращаем результаты
    return jsonify({
        "result1": {
            "id": result1[0],
            "L1history": oldData["L1history"],
            "L2history": oldData["L2history"],
            "L3history": oldData["L3history"],
            "timestamp": result1[4]
        },
        "result2": {
            "id": result2[0],
            "L1history": newData["L1history"],
            "L2history": newData["L2history"],
            "L3history": newData["L3history"],
            "timestamp": result2[4]
        },
        "differences": {
            "L1Difference": L1Difference,
            "L2Difference": L2Difference,
            "L3Difference": L3Difference
        }
    })

# Запуск Flask приложения
if __name__ == "__main__":
    initialize_database()  # Проверка и создание базы данных
    connect_mqtt()
    from threading import Thread

    data_thread = Thread(target=process_and_publish_data)
    data_thread.daemon = True
    data_thread.start()
    app.run(host="0.0.0.0", port=5000)