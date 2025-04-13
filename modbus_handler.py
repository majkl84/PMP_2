from pymodbus.client import ModbusTcpClient
from log import log_message
from config import MODBUS_REGISTER_MAP


# # Описание регистров
# MODBUS_REGISTER_MAP = {
#     "Voltage": (0, "uint16be", 0.1),  # Напряжение (V)
#     "CurrentLow": (1, "uint16be", 0.001),  # Ток (A) - младшие 16 бит
#     "PowerLow": (3, "uint16be", 1),  # Мощность (W) - младшие 16 бит
#     "EnergyLow": (5, "uint16be", 1),  # Энергия (Wh) - младшие 16 бит
#     "EnergyHigh": (6, "uint16be", 1),  # Энергия (Wh) - старшие 16 бит
#     "Frequency": (7, "uint16be", 0.1),  # Частота (Hz)
#     "PowerFactor": (8, "uint16be", 0.001),  # Коэффициент мощности
#     "AlarmStatus": (9, "int16be", 1)  # Статус тревоги
# }

# Чтение данных из Modbus
def read_modbus_data(host, unit_id):
    client = ModbusTcpClient(host)
    if not client.connect():
        log_message(f"Failed to connect to Modbus host: {host}")
        return None

    try:
        result = client.read_input_registers(address=0, count=10, slave=unit_id)
        if result.isError():
            log_message(f"Modbus error: {result}")
            return None

        registers = result.registers
        raw_data = {}

        for key, (offset, dtype, scale) in MODBUS_REGISTER_MAP.items():
            value = registers[offset]
            if dtype == "uint16be":
                raw_data[key] = value
            elif dtype == "int16be":
                value = value if value < 32768 else value - 65536
                raw_data[key] = value

        # Обработка данных
        data = {
            "Voltage": round(raw_data["Voltage"] * 0.1, 1),
            "Current": round(raw_data["CurrentLow"] * 0.001, 1),
            "Power": round(raw_data["PowerLow"] * 0.0001, 2),
            "Energy": raw_data["EnergyLow"],
            "Energy_F": round(((raw_data["EnergyHigh"] << 16) + raw_data["EnergyLow"]) * 0.001, 1),
            "Frequency": round(raw_data["Frequency"] * 0.1, 1),
            "PowerFactor": round(raw_data["PowerFactor"] * 0.001, 2),
            "AlarmStatus": raw_data["AlarmStatus"]
        }

        log_message(f"Обработанные данные из Modbus {host} (Адрес устройства: {unit_id}): {data}")
        return data
    except Exception as e:
        log_message(f"Exception while reading Modbus registers: {e}")
        return None
    finally:
        client.close()