console.log("JS CARGADO CORRECTAMENTE ✅");

/* ============================================================
   🔥 VARIABLES GLOBALES
   ============================================================ */
let cy = null;
let selectedInstance = null;

/* ============================================================
   🔥 SE EJECUTA AL CARGAR LA PÁGINA
   ============================================================ */
document.addEventListener("DOMContentLoaded", () => {
    console.log("🔄 Cargando escenario inicial…");
    loadExistingScenario();
});

/* ============================================================
   Inicializar Cytoscape de forma segura (evita errores)
   ============================================================ */
function ensureCy() {
    const container = document.getElementById("cy");

    if (!container) {
        console.error("❌ Contenedor #cy no encontrado.");
        return false;
    }

    if (typeof cytoscape === "undefined") {
        console.error("❌ Cytoscape NO está cargado.");
        return false;
    }

    // Si ya existe un cy previo → destruirlo correctamente
    if (cy && typeof cy.destroy === "function") {
        cy.destroy();
    }

    cy = cytoscape({
        container: container,
        elements: [],
        style: [
            {
                selector: "node",
                style: {
                    "background-color": "#4A90E2",
                    "label": "data(label)",
                    "color": "white",
                    "text-outline-color": "#1E3A8A",
                    "text-outline-width": 2
                }
            },
            { selector: 'node[type="attack"]', style: { "background-color": "#e53935" } },
            { selector: 'node[type="victim"]', style: { "background-color": "#1976d2" } },
            { selector: 'node[type="monitor"]', style: { "background-color": "#43a047" } },

            { selector: "edge", style: { "width": 3, "line-color": "#888" } }
        ]
    });

    console.log("🟢 Cytoscape inicializado correctamente.");
    return true;
}

/* ============================================================
   1. Consultar instancias en OpenStack
   ============================================================ */
async function loadExistingScenario() {
    console.log("🔍 Iniciando carga del escenario...");

    try {
        const res = await fetch("/api/openstack/instances");
        const raw = await res.text();

        console.log("📡 RAW API RESPONSE:", raw);

        let data;
        try {
            data = JSON.parse(raw);
        } catch (err) {
            console.error("❌ Error parseando JSON:", err);
            showNoScenario();
            return;
        }

        console.log("📦 JSON PARSEADO:", data);

        if (!data.instances || data.instances.length === 0) {
            console.warn("⚠️ No hay instancias en OpenStack");
            showNoScenario();
            return;
        }

const scenario = {
    nodes: data.instances.map((vm, i) => ({
        id: vm.id,
        name: vm.name,
        type: detectType(vm.name),

        // 🔥 Nueva información
        ip: vm.ip_floating || vm.ip_private || "N/A",
        ip_private: vm.ip_private,
        ip_floating: vm.ip_floating,
        image: vm.image_name,
        flavor: vm.flavor_name,
        status: vm.status,

        tools: [],

        position: { x: 200 + i * 200, y: 150 }
    })),
    edges: []
};


        loadScenarioGraph(scenario);
        loadScenarioTools(scenario);

    } catch (error) {
        console.error("❌ Error llamando al backend:", error);
        showNoScenario();
    }
}

/* ============================================================
   Detectar tipo de instancia según nombre
   ============================================================ */
function detectType(name) {
    name = name.toLowerCase();
    if (name.includes("monitor")) return "monitor";
    if (name.includes("attack")) return "attack";
    if (name.includes("victim")) return "victim";
    return "generic";
}

/* ============================================================
   2. Si NO hay instancias
   ============================================================ */
function showNoScenario() {
    document.getElementById("instance-list").innerHTML = `
        <div class="p-4 bg-red-700 rounded-lg text-center">
            ❌ No hay instancias en OpenStack.<br>
            ⚠️ Verifica que OpenStack esté funcionando.
        </div>
    `;

    if (cy && typeof cy.destroy === "function") {
        cy.destroy();
        cy = null;
    }
}

/* ============================================================
   3. Pintar grafo
   ============================================================ */
function loadScenarioGraph(scenario) {
    console.log("🎨 Renderizando grafo…");

    if (!ensureCy()) return;

    let elements = [];

    // Nodos
    scenario.nodes.forEach(n => {
        elements.push({
            data: {
                    id: n.id,
                    label: n.name,
                    type: n.type,
                    ip_private: n.ip_private,
                    ip_floating: n.ip_floating,
                    ip: n.ip_floating || n.ip_private || "N/A",

                    status: n.status,
                    image: n.image,
                    flavor: n.flavor,
                    tools: n.tools || []
                },
            position: n.position
        });
    });

    // Aristas
    scenario.edges.forEach(e => {
        elements.push({
            data: { id: e.id, source: e.source, target: e.target }
        });
    });

    cy.add(elements);

    cy.on("tap", "node", evt => {
        const node = evt.target.data();
        selectInstanceFromScenario(node);
    });
    /* ============================================================
   🎨 Aplicar colores según el estado de OpenStack
   ============================================================ */
   
}

/* ============================================================
   4. Panel izquierdo
   ============================================================ */
function loadScenarioTools(scenario) {
    const list = document.getElementById("instance-list");
    list.innerHTML = "";

    scenario.nodes.forEach(node => {
        const card = document.createElement("div");
        card.className = "p-3 bg-gray-700 hover:bg-gray-600 rounded-lg cursor-pointer";
        card.innerHTML = `
            <p class="font-bold">${node.name}</p>
            <p class="text-xs text-gray-300">${node.ip}</p>
        `;

        card.onclick = () => selectInstanceFromScenario(node);

        list.appendChild(card);
    });
}

/* ============================================================
   5. Seleccionar instancia
   ============================================================ */
async function selectInstanceFromScenario(node) {
    selectedInstance = node;

    const instanceName = node.name || node.label || node.id;

    document.getElementById("selected-instance-info").classList.remove("hidden");
    document.getElementById("instance-name").innerText = instanceName;
    document.getElementById("instance-ip").innerText = `Privada: ${node.ip_private || "N/A"} | Flotante: ${node.ip_floating || "N/A"}`;

    // === 🔥 Cargar tools desde backend ===
    let tools = [];
    try {
        const res = await fetch(`/api/get_tools_for_instance?instance=${instanceName}`);
        const data = await res.json();
        tools = data.tools || [];
        node.tools = tools;  // 🔥 Guardar en memoria
    } catch (err) {
        console.log("❌ Error obteniendo tools:", err);
    }

    const toolsBox = document.getElementById("installed-tools");
    toolsBox.innerHTML = "";

    if (tools.length === 0) {
        toolsBox.innerHTML = `<p class="text-gray-400 text-sm">No hay herramientas instaladas.</p>`;
        return;
    }

    tools.forEach(tool => {
        const row = document.createElement("div");
        row.className = "flex justify-between bg-gray-800 p-2 rounded-lg";

        row.innerHTML = `
            <span>${tool}</span>
            <button onclick="removeToolFromScenario('${tool}')" class="text-red-500">🗑</button>
        `;

        toolsBox.appendChild(row);
    });
}





/* ============================================================
   6. Añadir herramienta + enviar JSON al backend
   ============================================================ */
async function addTool() {
    const select = document.getElementById("available-tools");
    const tool = select.value;

    if (!selectedInstance || !tool) return;

    const instanceName = selectedInstance.name || selectedInstance.label || selectedInstance.id;

    // 1️⃣ Actualizar lista en memoria
    selectedInstance.tools.push(tool);

    // 2️⃣ Enviar al backend
    const payload = {
            instance: selectedInstance.name,
            id: selectedInstance.id,
            name: selectedInstance.name || selectedInstance.label,
            type: selectedInstance.type,

            ip_private: selectedInstance.ip_private,
            ip_floating: selectedInstance.ip_floating,
            ip: selectedInstance.ip,

            status: selectedInstance.status,
            image: selectedInstance.image,
            flavor: selectedInstance.flavor,

            tools: selectedInstance.tools
    };


    await fetch("/api/add_tool_to_instance", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload)
    });

    // 3️⃣ Ahora recargar herramientas REALES desde backend
    await selectInstanceFromScenario(selectedInstance);
}

/* ============================================================
   7. Leer archivos JSON con configuraciones de tools
   ============================================================ */
async function loadToolsConfig() {
    const terminal = document.getElementById("tools-terminal");
    terminal.innerHTML += "🔍 Leyendo archivos de configuración...\n";

    try {
        const res = await fetch("/api/read_tools_configs");
        const data = await res.json();

        terminal.innerHTML += "📂 Archivos detectados:\n";

        data.files.forEach(file => {
            terminal.innerHTML += `➡ ${file.instance}: ${JSON.stringify(file.tools)}\n`;
        });

        terminal.innerHTML += "✅ Lectura completada.\n";

    } catch (err) {
        terminal.innerHTML += `❌ Error leyendo archivos: ${err}\n`;
    }
}
/* ============================================================
   8. Ejecutar instalación de tools
   ============================================================ */
async function installTools() {
    const terminal = document.getElementById("tools-terminal");

    // Limpiar terminal y congelar la interfaz
    terminal.innerHTML += "\n🚀 Iniciando instalación de herramientas...\n";
    freezeUI();  // 🔥 Congelar la UI

    try {
        const res = await fetch("/api/install_tools", { method: "POST" });
        const data = await res.json();

        terminal.innerHTML += "📢 Instalación iniciada:\n";

        data.output.forEach(line => {
            terminal.innerHTML += `➡ ${line}\n`;
        });

        terminal.innerHTML += "✅ Instalación completada.\n";

    } catch (err) {
        terminal.innerHTML += `❌ Error ejecutando instalación: ${err}\n`;
    }

    // 🔥 Descongelar la UI
    unfreezeUI();
}






async function removeToolFromScenario(tool) {
    if (!selectedInstance) return;

    const instanceName = selectedInstance.name || selectedInstance.label || selectedInstance.id;

    console.log(`🗑 Eliminando herramienta ${tool} de ${instanceName}`);

    // 1️⃣ Eliminar de la instancia EN MEMORIA
    selectedInstance.tools = selectedInstance.tools.filter(t => t !== tool);

    // 2️⃣ ACTUALIZAR LA UI INMEDIATAMENTE
    renderToolsList(selectedInstance.tools);

    // 3️⃣ Actualizar backend
    const payload = {
        instance: selectedInstance.name,
        id: selectedInstance.id,
        name: selectedInstance.name || selectedInstance.label,
        type: selectedInstance.type,
        ip_private: selectedInstance.ip_private,
        ip_floating: selectedInstance.ip_floating,
        ip: selectedInstance.ip,
        status: selectedInstance.status,
        image: selectedInstance.image,
        flavor: selectedInstance.flavor,
        tools: selectedInstance.tools
    };


    await fetch("/api/add_tool_to_instance", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload)
    });

    // 4️⃣ Releer desde backend (sincronizar)
    await selectInstanceFromScenario(selectedInstance);
}

function renderToolsList(tools) {
    const toolsBox = document.getElementById("installed-tools");
    toolsBox.innerHTML = "";

    if (!tools || tools.length === 0) {
        toolsBox.innerHTML = `<p class="text-gray-400 text-sm">No hay herramientas instaladas.</p>`;
        return;
    }

    tools.forEach(tool => {
        const row = document.createElement("div");
        row.className = "flex justify-between bg-gray-800 p-2 rounded-lg";

        row.innerHTML = `
            <span>${tool}</span>
            <button onclick="removeToolFromScenario('${tool}')" class="text-red-500">🗑</button>
        `;
        toolsBox.appendChild(row);
    });
}





async function updateToolsBackend(instance) {
    const payload = {
        instance: instance.name || instance.label || instance.id,
        tools: instance.tools
    };

    await fetch("/api/add_tool_to_instance", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload)
    });
}


/* ============================================================
   🔒 BLOQUEAR / DESBLOQUEAR FRONTEND
   ============================================================ */
function freezeUI() {
    const overlay = document.createElement("div");
    overlay.id = "ui-freeze";
    overlay.className = `
        fixed inset-0 bg-black bg-opacity-60
        flex items-center justify-center
        z-50
    `;
    overlay.innerHTML = `
        <div class="text-center">
            <div class="animate-spin rounded-full h-16 w-16 border-t-4 border-b-4 border-blue-400 mx-auto"></div>
            <p class="mt-4 text-lg font-bold text-white">Instalando herramientas...</p>
        </div>
    `;
    document.body.appendChild(overlay);
}

function unfreezeUI() {
    const overlay = document.getElementById("ui-freeze");
    if (overlay) overlay.remove();
}
