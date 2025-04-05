import sqlite3
import time
from config import (LOGGING_ENABLED, PREVIOUS_ENERGY)
import paho.mqtt.client as mqtt
from config import MQTT_BROKER, MQTT_PORT, MQTT_USERNAME, MQTT_PASSWORD, SQLITE_DB


# Логирование сообщений
def log_message(message):
    if LOGGING_ENABLED:
        print(f"[LOG] {time.strftime('%Y-%m-%d %H:%M:%S')} - {message}")
        save_log_to_db(message)

# Сохранение логов в SQLite
def save_log_to_db(message):
    conn = sqlite3.connect(SQLITE_DB)
    cursor = conn.cursor()
    cursor.execute("INSERT INTO logs (message) VALUES (?)", (message,))
    conn.commit()
    conn.close()

# Инициализация MQTT клиента
mqtt_client = mqtt.Client()
mqtt_client.username_pw_set(MQTT_USERNAME, MQTT_PASSWORD)

# Подключение к MQTT брокеру
def connect_mqtt():
    def on_connect(client, userdata, flags, rc):
        if rc == 0:
            log_message("Connected to MQTT Broker!")
        else:
            log_message(f"Failed to connect, return code {rc}")

    mqtt_client.on_connect = on_connect
    try:
        mqtt_client.connect(MQTT_BROKER, MQTT_PORT)
    except Exception as e:
        log_message(f"MQTT connection error: {e}")
    mqtt_client.loop_start()

# Публикация данных в MQTT
def publish_mqtt(topic, payload):
    mqtt_client.publish(topic, payload)
