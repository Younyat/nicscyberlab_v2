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
def get_scenario_by_name(scenarioName):
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
        BASE_DIR = os.path.abspath(os.path.dirname(__file__))
        SCENARIO_DIR = os.path.join(BASE_DIR, "scenario")
        script_path = os.path.join(SCENARIO_DIR, "destroy_scenario_openstack_mejorado.sh")

        if not os.path.exists(script_path):
            return jsonify({"status": "error", "message": "Script no encontrado"}), 404

        # Ejecutar destruir en background
        process = subprocess.Popen(
            ["bash", script_path, "tf_out"],
            cwd=BASE_DIR,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )

        # Guardar estado inicial
        status_file = os.path.join(SCENARIO_DIR, "destroy_status.json")
        with open(status_file, "w") as sf:
            json.dump({"status": "running"}, sf)

        # Monitorizar en segundo hilo
        def monitor():
            stdout, stderr = process.communicate()
            with open(status_file, "w") as sf:
                json.dump({
                    "status": "success" if process.returncode == 0 else "error",
                    "stdout": stdout,
                    "stderr": stderr
                }, sf)

        threading.Thread(target=monitor, daemon=True).start()

        return jsonify({
            "status": "running",
            "message": "🧨 Destrucción iniciada.",
            "pid": process.pid
        }), 202

    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500

@app.route('/api/destroy_status')
def destroy_status():
    status_file = "scenario/destroy_status.json"

    if not os.path.exists(status_file):
        return jsonify({"status": "unknown"}), 404

    with open(status_file) as f:
        return jsonify(json.load(f)), 200


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
        script_path = os.path.join(SCENARIO_DIR, "main_generator_inicial_openstack.sh")

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

        script_path = os.path.join(INITIAL_DIR, "run_scenario_from_json.sh")

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


from flask import Response

@app.route('/api/run_initial_generator_stream')
def stream_logs():
    def generate():
        yield "data: iniciando...\n\n"
        with open("app.log", "r") as f:
            for line in f:
                yield f"data: {line}\n\n"
    return Response(generate(), mimetype='text/event-stream')













import openstack

def get_openstack_connection():
    """Devuelve una conexión OpenStack usando las variables cargadas desde admin-openrc.sh"""
    return openstack.connection.Connection(
        auth_url=os.environ.get("OS_AUTH_URL"),
        project_name=os.environ.get("OS_PROJECT_NAME"),
        username=os.environ.get("OS_USERNAME"),
        password=os.environ.get("OS_PASSWORD"),
        region_name=os.environ.get("OS_REGION_NAME"),
        user_domain_name=os.environ.get("OS_USER_DOMAIN_NAME", "Default"),
        project_domain_name=os.environ.get("OS_PROJECT_DOMAIN_NAME", "Default"),
        compute_api_version="2",
        identity_interface="public"
    )

@app.route("/api/openstack/instances", methods=["GET"])
def api_get_openstack_instances():
    try:
        conn = get_openstack_connection()

        instances = []

        for server in conn.compute.servers():

            ip_private = None
            ip_floating = None

            # Leer direcciones correctamente
            for net_name, addresses in server.addresses.items():
                for addr in addresses:
                    ip = addr.get("addr")
                    if addr.get("OS-EXT-IPS:type") == "floating":
                        ip_floating = ip
                    else:
                        ip_private = ip

            instances.append({
                "id": server.id,
                "name": server.name,
                "status": server.status,

                # 🔥 Nuevos campos
                "ip_private": ip_private,
                "ip_floating": ip_floating,
                "ip": ip_floating or ip_private or "N/A",

                "image": server.image["id"] if server.image else None,
                "flavor": server.flavor["id"] if server.flavor else None
            })

        return jsonify({"instances": instances}), 200

    except Exception as e:
        logger.error(f"❌ Error al consultar instancias OpenStack: {e}", exc_info=True)
        return jsonify({"error": str(e)}), 500


@app.route('/api/add_tool_to_instance', methods=['POST'])
def add_tool_to_instance():
    print("➡ Método HTTP:", request.method)
    print("➡ Headers:", dict(request.headers))
    print("➡ request.data crudo:", request.data)

    try:
        data = request.get_json(force=True)

        if not data:
            return jsonify({"status": "error", "msg": "JSON vacío"}), 400

        # 🔥 Tomamos "instance" correctamente
        instance = data.get("instance") or data.get("name")

        if not instance:
            return jsonify({"status": "error", "msg": "Falta el nombre de instancia"}), 400

        tools = data.get("tools", [])

        BASE = os.path.abspath(os.path.dirname(__file__))
        DIR = os.path.join(BASE, "tools-installer-tmp")
        os.makedirs(DIR, exist_ok=True)

        safe = re.sub(r'[^a-zA-Z0-9_-]', '_', instance.lower())
        path = os.path.join(DIR, f"{safe}_tools.json")

        with open(path, "w") as f:
            json.dump(data, f, indent=4)

        print("📂 Guardado en:", path)

        return jsonify({"status": "success", "saved": path})

    except Exception as e:
        print("❌ ERROR:", e)
        return jsonify({"status": "error", "msg": str(e)}), 500






        

@app.route('/api/read_tools_configs', methods=['GET'])
def read_tools_configs():
    print("📥 Leyendo archivos tools-installer/ ...")

    BASE = os.path.abspath(os.path.dirname(__file__))
    DIR = os.path.join(BASE, "tools-installer-tmp")

    if not os.path.exists(DIR):
        return jsonify({"files": []})

    result = []

    for filename in os.listdir(DIR):
        if filename.endswith("_tools.json"):
            path = os.path.join(DIR, filename)

            with open(path, "r") as f:
                data = json.load(f)

            result.append({
                "file": filename,
                "instance": data.get("instance"),
                "tools": data.get("tools", [])
            })

            print(f"📄 {filename}: {data}")

    return jsonify({"files": result})







    from flask import Response

@app.route('/api/install_tools', methods=['POST'])
def install_tools():
    print("🚀 Iniciando instalación de tools...")

    BASE = os.path.abspath(os.path.dirname(__file__))
    SCRIPT = os.path.join(BASE, "tools-installer", "tools_install_master.sh")

    if not os.path.exists(SCRIPT):
        return jsonify({"status": "error", "msg": "Script maestro no encontrado"}), 404

    os.chmod(SCRIPT, 0o755)

    def generate():
        process = subprocess.Popen(
            ["bash", SCRIPT],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,  # stderr unido a stdout
            text=True,
            bufsize=1
        )

        for line in process.stdout:
            yield f"data: {line.strip()}\n\n"

        process.wait()
        yield f"data: [FIN] Exit Code: {process.returncode}\n\n"

    return Response(generate(), mimetype='text/event-stream')







@app.route('/api/get_tools_for_instance', methods=['GET'])
def get_tools_for_instance():
    instance = request.args.get("instance")

    if not instance:
        return jsonify({"tools": []})

    BASE = os.path.abspath(os.path.dirname(__file__))
    DIR = os.path.join(BASE, "tools-installer-tmp")

    instance = instance.strip().lower()

    print(f"🔎 Buscando JSON para instancia: {instance}")

    for filename in os.listdir(DIR):
        if filename.endswith("_tools.json"):
            path = os.path.join(DIR, filename)

            with open(path, "r") as f:
                data = json.load(f)

            stored = (data.get("instance") or "").strip().lower()

            if stored == instance:
                print(f"📄 JSON encontrado: {filename}")
                return jsonify({
                    "instance": instance,
                    "tools": data.get("tools", [])
                })

    print("⚠️ JSON NO encontrado para esta instancia")
    return jsonify({"instance": instance, "tools": []})






from tools_uninstall_manager.tools_uninstall_manager import uninstall_tool

@app.route('/api/uninstall_tool_from_instance', methods=['POST'])
def api_uninstall_tool():
    try:
        data = request.get_json()

        if not data:
            return jsonify({"status": "error", "msg": "JSON vacío"}), 400

        instance = data.get("instance")
        ip_private = data.get("ip_private", "")
        ip_floating = data.get("ip_floating", "")
        tool = data.get("tool")  # 🔥 ahora correcto

        if not instance or not tool:
            return jsonify({
                "status": "error",
                "msg": "Faltan campos: instance y tool son obligatorios"
            }), 400

        result = uninstall_tool(
            instance,
            tool,
            ip_private,
            ip_floating
        )

        return jsonify(result), 200

    except Exception as e:
        logger.error(f"❌ Error API uninstall: {e}", exc_info=True)
        return jsonify({"status": "error", "msg": str(e)}), 500


@app.route("/api/instance_roles", methods=["GET"])
def api_instance_roles():
    """
    Detecta automáticamente attacker / monitor / victim según el nombre.
    Maneja correctamente las conexiones OpenStack para evitar fugas.
    """
    conn = None

    try:
        conn = get_openstack_connection()
        servers = conn.compute.servers()

        result = {
            "attacker": None,
            "monitor": None,
            "victim": None,
            "unknown": []
        }

        for server in servers:

            # ==========================
            #        OBTENER IPs
            # ==========================
            ip_private = None
            ip_floating = None

            for net, addrs in server.addresses.items():
                for addr in addrs:
                    if addr.get("OS-EXT-IPS:type") == "floating":
                        ip_floating = addr["addr"]
                    else:
                        ip_private = addr["addr"]

            ip_final = ip_floating or ip_private or "N/A"

            # ==========================
            #     CLASIFICACIÓN POR NOMBRE
            # ==========================

            name = server.name.lower()

            # 🟥 ATACANTE
            if any(x in name for x in ["attack", "attacker", "redteam", "pentest"]):
                result["attacker"] = {
                    "name": server.name,
                    "ip": ip_final,
                    "status": server.status
                }
                continue

            # 🟩 MONITOR
            if any(x in name for x in ["monitor", "wazuh", "log", "siem"]):
                result["monitor"] = {
                    "name": server.name,
                    "ip": ip_final,
                    "status": server.status
                }
                continue

            # 🟦 VÍCTIMA
            if any(x in name for x in ["victim", "target", "blue", "server", "web"]):
                result["victim"] = {
                    "name": server.name,
                    "ip": ip_final,
                    "status": server.status
                }
                continue

            # 🟨 OTROS
            result["unknown"].append({
                "name": server.name,
                "ip": ip_final,
                "status": server.status
            })

        return jsonify(result), 200

    except Exception as e:
        logger.error(f"❌ Error en /api/instance_roles: {e}", exc_info=True)
        return jsonify({"error": str(e)}), 500

    finally:
        # 🔥 CIERRE CRÍTICO → evita “Too many open files”
        if conn:
            try:
                conn.close()
            except Exception:
                pass

@app.route('/api/check_wazuh', methods=['POST'])
def api_check_wazuh():
    try:
        data = request.get_json()

        instance = data.get("instance")
        ip = data.get("ip")

        if not instance or not ip:
            return jsonify({"status": "error", "msg": "Faltan campos instance/ip"}), 400

        # === Buscar clave SSH en ~/.ssh ===
        SSH_DIR = os.path.expanduser("~/.ssh")
        SSH_KEY = ""

        for fname in os.listdir(SSH_DIR):
            full = os.path.join(SSH_DIR, fname)

            if fname.endswith(".pub"):
                continue

            if os.path.isfile(full):
                with open(full, "r", errors="ignore") as f:
                    content = f.read()
                    if "PRIVATE KEY" in content:
                        SSH_KEY = full
                        break

        if not SSH_KEY:
            return jsonify({"status": "error", "msg": "No se encontró clave privada"}), 500

        # === Detectar usuario real (Ubuntu / Debian / Kali / Root) ===
        user = detect_remote_user(ip, SSH_KEY)

        command = """
            (systemctl status wazuh-dashboard.service 2>/dev/null ||
             systemctl status wazuh-indexer.service 2>/dev/null ||
             echo '❌ Wazuh NO está instalado')
        """

        ssh_cmd = [
            "ssh",
            "-o", "StrictHostKeyChecking=no",
            "-i", SSH_KEY,
            f"{user}@{ip}",
            command
        ]

        proc = subprocess.run(
            ssh_cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )

        return jsonify({
            "status": "success",
            "stdout": proc.stdout,
            "stderr": proc.stderr,
            "exit_code": proc.returncode
        })

    except Exception as e:
        return jsonify({"status": "error", "msg": str(e)}), 500



@app.route("/api/change_password", methods=["POST"])
def api_change_password():
    try:
        data = request.get_json()

        instance = data.get("instance")
        ip = data.get("ip")
        new_pass = data.get("new_password")

        if not instance or not ip or not new_pass:
            return jsonify({"error": "Faltan parámetros"}), 400

        SSH_DIR = os.path.expanduser("~/.ssh")
        SSH_KEY = ""

        for fname in os.listdir(SSH_DIR):
            full = os.path.join(SSH_DIR, fname)
            if fname.endswith(".pub"): 
                continue
            if os.path.isfile(full):
                if "PRIVATE KEY" in open(full,"r",errors="ignore").read():
                    SSH_KEY = full
                    break

        if not SSH_KEY:
            return jsonify({"error": "Clave privada no encontrada"}), 500

        # Detectar usuario automáticamente
        user = detect_remote_user(ip, SSH_KEY)

        cmd_change = f"echo '{user}:{new_pass}' | sudo chpasswd"

        proc_change = subprocess.run(
            ["ssh","-o","StrictHostKeyChecking=no","-i",SSH_KEY,f"{user}@{ip}",cmd_change],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )

        return jsonify({
            "instance": instance,
            "ip": ip,
            "user": user,
            "stdout": proc_change.stdout,
            "stderr": proc_change.stderr,
            "exitcode": proc_change.returncode
        })

    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route("/api/change_keyboard_layout", methods=["POST"])
def api_change_keyboard_layout():
    try:
        data = request.get_json()

        instance = data.get("instance")
        ip = data.get("ip")
        layout = data.get("layout", "es")

        if not instance or not ip:
            return jsonify({"error": "Faltan parámetros"}), 400

        # Buscar clave SSH
        SSH_DIR = os.path.expanduser("~/.ssh")
        SSH_KEY = ""

        for fname in os.listdir(SSH_DIR):
            full = os.path.join(SSH_DIR, fname)
            if fname.endswith(".pub"): continue
            if os.path.isfile(full):
                with open(full, "r", errors="ignore") as f:
                    if "PRIVATE KEY" in f.read():
                        SSH_KEY = full
                        break

        if not SSH_KEY:
            return jsonify({"error": "Clave privada no encontrada"}), 500

        # Detectar usuario correcto
        user = detect_remote_user(ip, SSH_KEY)

        # --- SOLO UN COMANDO: NO INSTALA NADA ---
        cmd = f"sudo loadkeys {layout}"

        proc = subprocess.run(
            ["ssh","-o","StrictHostKeyChecking=no","-i",SSH_KEY,f"{user}@{ip}",cmd],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )

        return jsonify({
            "instance": instance,
            "ip": ip,
            "user": user,
            "layout": layout,
            "stdout": proc.stdout,
            "stderr": proc.stderr
        })

    except Exception as e:
        return jsonify({"error": str(e)}), 500

def detect_remote_user(ip, ssh_key):
    """
    Detecta usuario SSH válido y SO sin bloquear.
    Compatible con Ubuntu / Debian / Kali / Root.
    """

    candidates = ["ubuntu", "debian", "kali", "root"]

    for user in candidates:
        try:
            proc = subprocess.run(
                [
                    "ssh",
                    "-o", "BatchMode=yes",
                    "-o", "StrictHostKeyChecking=no",
                    "-o", "ConnectTimeout=5",
                    "-i", ssh_key,
                    f"{user}@{ip}",
                    "cat /etc/os-release"
                ],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True
            )

            output = (proc.stdout + proc.stderr).lower()

            if proc.returncode == 0:
                # 🎯 Usuario válido encontrado
                if "ubuntu" in output:
                    return "ubuntu"
                if "debian" in output:
                    return "debian"
                if "kali" in output:
                    return "kali"

                # Usuario válido aunque no detectemos distro
                return user

        except Exception:
            continue

    raise RuntimeError("❌ No se pudo detectar usuario SSH válido")





@app.route("/api/run_tool_version", methods=["POST"])
def api_run_tool_version():
    try:
        data = request.get_json()
        tool = data.get("tool")        # snort | suricata
        instance = data.get("instance")
        ip = data.get("ip")

        if tool not in ["snort", "suricata"]:
            return jsonify({"error": "Tool no soportada"}), 400

        if not instance or not ip:
            return jsonify({"error": "Faltan parámetros"}), 400

        # 🔑 Buscar clave SSH
        SSH_DIR = os.path.expanduser("~/.ssh")
        SSH_KEY = None

        for f in os.listdir(SSH_DIR):
            p = os.path.join(SSH_DIR, f)
            if f.endswith(".pub"):
                continue
            if os.path.isfile(p):
                with open(p, "r", errors="ignore") as fd:
                    if "PRIVATE KEY" in fd.read():
                        SSH_KEY = p
                        break

        if not SSH_KEY:
            return jsonify({"error": "No se encontró clave SSH"}), 500

        # 👤 Detectar usuario remoto
        user = detect_remote_user(ip, SSH_KEY)

        # 🧪 Comando seguro
        cmd = f"{tool} --version"

        ssh_cmd = [
            "ssh",
            "-o", "StrictHostKeyChecking=no",
            "-i", SSH_KEY,
            f"{user}@{ip}",
            cmd
        ]

        proc = subprocess.run(
            ssh_cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )

        return jsonify({
            "status": "success",
            "tool": tool,
            "stdout": proc.stdout.strip(),
            "stderr": proc.stderr.strip(),
            "exit_code": proc.returncode
        })

    except Exception as e:
        logger.exception("❌ Error ejecutando tool --version")
        return jsonify({"error": str(e)}), 500


@app.route('/')
def index():
    return send_from_directory('static', 'index.html')

@app.route('/<path:path>')
def static_files(path):
    return send_from_directory('static', path)

    
if __name__ == "__main__":
   app.run(host="localhost", port=5001, debug=True)

