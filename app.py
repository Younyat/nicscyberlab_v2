import json
import subprocess
from flask import Flask, request, jsonify, send_from_directory
from flask_cors import CORS
import logging
import os
from logging.handlers import RotatingFileHandler
import sys
import re
import threading

# ===== Configurar logging =====
log_file = 'app.log'
logger = logging.getLogger('app_logger')
logger.setLevel(logging.INFO)

handler = RotatingFileHandler(log_file, maxBytes=5*1024*1024, backupCount=3)
formatter = logging.Formatter('%(asctime)s - %(levelname)s - %(message)s')
handler.setFormatter(formatter)
logger.addHandler(handler)

console_handler = logging.StreamHandler()
console_handler.setFormatter(formatter)
logger.addHandler(console_handler)

class StreamToLogger(object):
    def __init__(self, logger, level):
        self.logger = logger
        self.level = level
    def write(self, message):
        if message.rstrip() != "":
            self.logger.log(self.level, message.rstrip())
    def flush(self):
        pass

logging.basicConfig(level=logging.INFO)
sys.stdout = StreamToLogger(logger, logging.INFO)
sys.stderr = StreamToLogger(logger, logging.ERROR)

app = Flask(__name__)
CORS(app)

# === Generar y cargar credenciales OpenStack ===
BASE_DIR = os.path.abspath(os.path.dirname(__file__))
GEN_SCRIPT = os.path.join(BASE_DIR, "generate_app_cred_openrc_from_clouds.sh")
OPENRC_PATH = os.path.join(BASE_DIR, "admin-openrc.sh")

try:
    if os.path.exists(GEN_SCRIPT):
        logger.info(f"⚙️ Ejecutando script de generación de credenciales: {GEN_SCRIPT}")

        # Asegurar permisos de ejecución
        if not os.access(GEN_SCRIPT, os.X_OK):
            os.chmod(GEN_SCRIPT, 0o755)
            logger.info(f"✅ Permisos de ejecución otorgados a {GEN_SCRIPT}")

        # Ejecutar el script
        proc = subprocess.run(
            ["bash", GEN_SCRIPT],
            cwd=BASE_DIR,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False
        )

        logger.info("📤 Salida del script:")
        logger.info(proc.stdout)
        if proc.stderr:
            logger.warning("📥 Errores durante la ejecución del script:")
            logger.warning(proc.stderr)

        # Validar resultado
        if proc.returncode == 0 and os.path.exists(OPENRC_PATH):
            logger.info(f"✅ Script ejecutado correctamente. Archivo generado: {OPENRC_PATH}")
        else:
            logger.warning(f"⚠️ No se generó correctamente {OPENRC_PATH}. Código de salida: {proc.returncode}")
    else:
        logger.warning(f"⚠️ Script {GEN_SCRIPT} no encontrado. Se omite la generación automática.")

except Exception as e:
    logger.error(f"❌ Error al ejecutar el script {GEN_SCRIPT}: {e}", exc_info=True)


# === Cargar credenciales OpenStack desde admin-openrc.sh ===
if os.path.exists(OPENRC_PATH):
    try:
        with open(OPENRC_PATH) as f:
            for line in f:
                line = line.strip()
                if line.startswith("export "):
                    key, value = line.replace("export ", "").split("=", 1)
                    os.environ[key] = value
        logger.info(f"✅ Credenciales OpenStack cargadas desde {OPENRC_PATH}")
    except Exception as e:
        logger.error(f"⚠️ Error al cargar {OPENRC_PATH}: {e}")
else:
    logger.warning(f"⚠️ Archivo {OPENRC_PATH} no encontrado. Los comandos OpenStack pueden fallar.")


MOCK_SCENARIO_DATA = {}
SCENARIO_FILE = "scenario/scenario_file.json"

DEFAULT_SCENARIO = {
    "scenario_name": "Default Empty Scenario",
    "description": "Escenario por defecto: no se encontró 'scenario_file.json'",
    "nodes": [{"data": {"id": "n1", "name": "Nodo Inicial"}, "position": {"x": 100, "y": 100}}],
    "edges": []
}

try:
    with open(SCENARIO_FILE, 'r') as f:
        MOCK_SCENARIO_DATA["file"] = json.load(f)
except Exception:
    MOCK_SCENARIO_DATA["file"] = DEFAULT_SCENARIO


## === Rutas API ===
@app.route('/api/console_url', methods=['POST'])
def get_console_url():
    try:
        data = request.get_json()
        instance_name = data.get('instance_name')
        logging.info(f"Consultar terminal del nodo {instance_name}")

        if not instance_name:
            return jsonify({'error': "Falta 'instance_name'"}), 400

        # 📁 Ruta absoluta al script
        script_path = os.path.join(os.path.dirname(__file__), "scenario/get_console_url.sh")

        # 🧩 Verificar existencia del script
        if not os.path.isfile(script_path):
            return jsonify({'error': f"❌ Script no encontrado: {script_path}"}), 500

        # 🔐 Verificar permisos de ejecución
        if not os.access(script_path, os.X_OK):
            logging.warning(f"⚠️ El script no es ejecutable: {script_path}. Corrigiendo permisos...")
            try:
                os.chmod(script_path, 0o755)
                logging.info(f"✅ Permisos corregidos para {script_path}")
            except Exception as chmod_error:
                return jsonify({'error': f"No se pudo otorgar permiso de ejecución: {chmod_error}"}), 500

        # 🚀 Ejecutar el script de forma controlada
        proc = subprocess.run(
            [script_path, instance_name],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False
        )

        stdout = proc.stdout.strip()
        stderr = proc.stderr.strip()

        app.logger.info(f"📤 script stdout:\n{stdout}")
        app.logger.info(f"📥 script stderr:\n{stderr}")

        # 🧭 Buscar URL en la salida
        text_to_search = stdout + "\n" + stderr
        m = re.search(r'https?://[^\s\'"<>]+', text_to_search)

        if not m:
            logging.warning(f"⚠️ No se encontró URL de consola en la salida del script '{instance_name}'")
            return jsonify({
                'error': 'No se encontró URL de la instancia',
                'stdout': stdout,
                'stderr': stderr
            }), 500

        url = m.group(0)
        logging.info(f"✅ URL de consola encontrada para '{instance_name}': {url}")

        # ✅ Respuesta al frontend
        return jsonify({
            'message': f'Consola solicitada para {instance_name}',
            'output': url,
            'stdout': stdout,
            'stderr': stderr
        }), 200

    except subprocess.SubprocessError as suberr:
        app.logger.exception(f"❌ Error al ejecutar el script para '{instance_name}': {suberr}")
        return jsonify({'error': 'Error al ejecutar el script', 'details': str(suberr)}), 500

    except Exception as e:
        app.logger.exception(f"⚠️ Error inesperado al procesar la solicitud de consola para '{instance_name}'")
        return jsonify({'error': 'Error interno', 'details': str(e)}), 500


@app.route('/api/get_scenario/<scenarioName>', methods=['GET'])
def get_scenario(scenarioName):
    try:
        scenario_dir = os.path.join(os.path.dirname(__file__), "scenario")
        file_path = os.path.join(scenario_dir, f"scenario_{scenarioName}.json")

        if not os.path.exists(file_path):
            return jsonify({
                "status": "error",
                "message": f"❌ Escenario '{scenarioName}' no encontrado en {scenario_dir}"
            }), 404

        with open(file_path, 'r') as f:
            scenario = json.load(f)
        return jsonify(scenario), 200

    except json.JSONDecodeError:
        return jsonify({
            "status": "error",
            "message": f"⚠️ El archivo 'scenario_{scenarioName}.json' contiene JSON inválido"
        }), 500

    except Exception as e:
        return jsonify({
            "status": "error",
            "message": f"⚠️ Error inesperado al leer el escenario: {str(e)}"
        }), 500

@app.route('/api/destroy_scenario', methods=['POST'])
def destroy_scenario():
    try:
        base_dir = os.path.abspath(os.path.dirname(__file__))
        script_path = os.path.join(base_dir, "scenario", "destroy_scenario.sh")

        # 🔍 Verificar existencia del script
        if not os.path.exists(script_path):
            logger.error(f"❌ Script no encontrado: {script_path}")
            return jsonify({
                "status": "error",
                "message": f"❌ Script no encontrado: {script_path}"
            }), 404

        # 🧩 Asegurar permisos de ejecución
        if not os.access(script_path, os.X_OK):
            os.chmod(script_path, 0o755)
            logger.info(f"✅ Permisos de ejecución corregidos para {script_path}")

        # 🚀 Ejecutar el script
        logger.info(f"🧨 Ejecutando script de destrucción: {script_path}")
        process = subprocess.run(
            ["bash", script_path],
            cwd=base_dir,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False
        )

        stdout = process.stdout.strip()
        stderr = process.stderr.strip()

        # 📋 Log de salida
        logger.info(f"📤 STDOUT:\n{stdout}")
        if stderr:
            logger.warning(f"📥 STDERR:\n{stderr}")

        if process.returncode == 0:
            return jsonify({
                "status": "success",
                "message": "✅ Escenario destruido correctamente.",
                "stdout": stdout,
                "stderr": stderr
            }), 200
        else:
            return jsonify({
                "status": "error",
                "message": "⚠️ Error al ejecutar terraform destroy.",
                "stdout": stdout,
                "stderr": stderr
            }), 500

    except Exception as e:
        logger.exception(f"❌ Error inesperado al ejecutar destroy_scenario.sh: {e}")
        return jsonify({
            "status": "error",
            "message": f"❌ Error interno: {str(e)}"
        }), 500



@app.route('/api/create_scenario', methods=['POST'])
def create_scenario():
    try:
        scenario_data = request.get_json()
        if not scenario_data:
            return jsonify({"status": "error", "message": "No se recibió JSON válido"}), 400

        scenario_name = scenario_data.get('scenario_name', 'Escenario_sin_nombre')
        safe_name = scenario_name.replace(' ', '_').replace(':', '').replace('/', '_').replace('\\', '_')

        # === 🔧 NUEVO BLOQUE: rutas absolutas y seguras ===
        BASE_DIR = os.path.abspath(os.path.dirname(__file__))
        SCENARIO_DIR = os.path.join(BASE_DIR, "scenario")
        TF_OUT_DIR = os.path.join(BASE_DIR, "tf_out")

        os.makedirs(SCENARIO_DIR, exist_ok=True)
        os.makedirs(TF_OUT_DIR, exist_ok=True)

        file_path = os.path.join(SCENARIO_DIR, f"scenario_{safe_name}.json")
        script_path = os.path.join(SCENARIO_DIR, "generate_terraform.sh")

        logging.info(f"🧭 Ruta base: {BASE_DIR}")
        logging.info(f"📁 Escenario: {file_path}")
        logging.info(f"⚙️  Script: {script_path}")

        # Guardar el escenario recibido
        with open(file_path, 'w') as f:
            json.dump(scenario_data, f, indent=4)
        logging.info(f"📄 Escenario guardado en {file_path}")

        if not os.path.exists(script_path):
            return jsonify({
                "status": "error",
                "message": f"❌ Script no encontrado: {script_path}"
            }), 500

        # --- Archivo de estado ---
        status_file = os.path.join(SCENARIO_DIR, "deployment_status.json")
        with open(status_file, "w") as sfile:
            json.dump({
                "status": "running",
                "message": f"⏳ Despliegue en curso para '{scenario_name}'...",
                "pid": None
            }, sfile, indent=4)

        # --- Ejecutar script ---
        process = subprocess.Popen(
            ["bash", script_path, file_path, TF_OUT_DIR],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )

        logging.info(f"🚀 Despliegue iniciado (PID={process.pid}) para {scenario_name}")

        with open("last_deployment.pid", "w") as pidfile:
            pidfile.write(str(process.pid))

        def monitor_process():
            stdout, stderr = process.communicate()
            if process.returncode == 0:
                logging.info(f"✅ Despliegue completado correctamente para '{scenario_name}'")
                with open(status_file, "w") as sfile:
                    json.dump({
                        "status": "success",
                        "message": f"✅ Despliegue completado correctamente para '{scenario_name}'.",
                        "stdout": stdout,
                        "stderr": stderr
                    }, sfile, indent=4)
            else:
                logging.error(f"❌ Error en el despliegue de '{scenario_name}': {stderr}")
                with open(status_file, "w") as sfile:
                    json.dump({
                        "status": "error",
                        "message": f"❌ Error al desplegar '{scenario_name}'",
                        "stdout": stdout,
                        "stderr": stderr
                    }, sfile, indent=4)

        threading.Thread(target=monitor_process, daemon=True).start()

        return jsonify({
            "status": "running",
            "message": f"🚀 Despliegue de '{scenario_name}' iniciado.",
            "pid": process.pid,
            "file": file_path,
            "output_dir": TF_OUT_DIR
        }), 202

    except Exception as e:
        logging.error(f"❌ Error al procesar escenario: {e}", exc_info=True)
        return jsonify({"status": "error", "message": f"Error interno: {str(e)}"}), 500


# === ESTADO DE DESPLIEGUE ===
@app.route('/api/deployment_status', methods=['GET'])
def deployment_status():
    status_file = "scenario/deployment_status.json"

    if not os.path.exists(status_file):
        return jsonify({
            "status": "unknown",
            "message": "⚠️ No existe archivo de estado de despliegue."
        }), 404

    try:
        with open(status_file, "r") as sfile:
            data = json.load(sfile)
        return jsonify(data), 200
    except json.JSONDecodeError:
        return jsonify({
            "status": "error",
            "message": "⚠️ Error al leer JSON de estado."
        }), 500
    except Exception as e:
        return jsonify({
            "status": "error",
            "message": f"⚠️ Error interno: {str(e)}"
        }), 500

@app.route('/api/destroy_initial_environment_setup', methods=['POST'])
def destroy_initial_environment_setup():
    try:
        logger.info("===============================================")
        logger.info("🟦 API CALL: /api/run_initial_environment_setup")
        logger.info("===============================================")

        BASE_DIR = os.path.abspath(os.path.dirname(__file__))
        INITIAL_DIR = os.path.join(BASE_DIR, "initial")
       




        script_path = os.path.join(INITIAL_DIR, "limpiar_inicial.sh")

        if not os.path.exists(script_path):
            return jsonify({
                "status": "error",
                "message": f"❌ Script no encontrado: {script_path}"
            }), 404

        if not os.access(script_path, os.X_OK):
            os.chmod(script_path, 0o755)

        logger.info("🚀 Ejecutando script (modo BLOQUEANTE)...")

        result = subprocess.run(
            ["bash", script_path],
            cwd=INITIAL_DIR,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )

        logger.info("📤 STDOUT:")
        logger.info(result.stdout)
        logger.info("📥 STDERR:")
        logger.info(result.stderr)

        if result.returncode == 0:
            return jsonify({
                "status": "success",
                "message": "✅ Entorno inicial desplegado correctamente.",
                "stdout": result.stdout,
                "stderr": result.stderr
            }), 200
        else:
            return jsonify({
                "status": "error",
                "message": "❌ Error durante el despliegue inicial.",
                "stdout": result.stdout,
                "stderr": result.stderr
            }), 500

    except Exception as e:
        logger.exception("❌ Error inesperado")
        return jsonify({
            "status": "error",
            "message": str(e)
        }), 500



@app.route('/api/run_initial_environment_setup', methods=['POST'])
def run_initial_environment_setup():
    try:
        logger.info("===============================================")
        logger.info("🟦 API CALL: /api/run_initial_environment_setup")
        logger.info("===============================================")

        BASE_DIR = os.path.abspath(os.path.dirname(__file__))
        INITIAL_DIR = os.path.join(BASE_DIR, "initial")
        CONFIG_DIR = os.path.join(INITIAL_DIR, "configs")

        os.makedirs(CONFIG_DIR, exist_ok=True)

        json_path = os.path.join(CONFIG_DIR, "scenario_config.json")

        data = request.get_json()
        if not data:
            return jsonify({
                "status": "error",
                "message": "❌ No se recibió JSON válido"
            }), 400

        with open(json_path, "w") as f:
            json.dump(data, f, indent=4)

        script_path = os.path.join(INITIAL_DIR, "generar_desde_json.sh")

        if not os.path.exists(script_path):
            return jsonify({
                "status": "error",
                "message": f"❌ Script no encontrado: {script_path}"
            }), 404

        if not os.access(script_path, os.X_OK):
            os.chmod(script_path, 0o755)

        logger.info("🚀 Ejecutando script (modo BLOQUEANTE)...")

        result = subprocess.run(
            ["bash", script_path, json_path],
            cwd=INITIAL_DIR,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )

        logger.info("📤 STDOUT:")
        logger.info(result.stdout)
        logger.info("📥 STDERR:")
        logger.info(result.stderr)

        if result.returncode == 0:
            return jsonify({
                "status": "success",
                "message": "✅ Entorno inicial desplegado correctamente.",
                "stdout": result.stdout,
                "stderr": result.stderr
            }), 200
        else:
            return jsonify({
                "status": "error",
                "message": "❌ Error durante el despliegue inicial.",
                "stdout": result.stdout,
                "stderr": result.stderr
            }), 500

    except Exception as e:
        logger.exception("❌ Error inesperado")
        return jsonify({
            "status": "error",
            "message": str(e)
        }), 500



@app.route('/')
def index():
    return send_from_directory('static', 'index.html')

@app.route('/<path:path>')
def static_files(path):
    return send_from_directory('static', path)

    
if __name__ == "__main__":
    app.run(host="localhost", port=5001, debug=True)
