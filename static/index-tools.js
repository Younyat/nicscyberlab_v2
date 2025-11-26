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
                ip: vm.ip,
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
                ip: n.ip,
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
function selectInstanceFromScenario(node) {
    selectedInstance = node;

    document.getElementById("selected-instance-info").classList.remove("hidden");
    document.getElementById("instance-name").innerText = node.label;
    document.getElementById("instance-ip").innerText = node.ip;

    const toolsBox = document.getElementById("installed-tools");
    toolsBox.innerHTML = "";

    (node.tools || []).forEach(tool => {
        const row = document.createElement("div");
        row.className = "flex justify-between bg-gray-800 p-2 rounded-lg";

        row.innerHTML = `
            <span>${tool}</span>
            <button onclick="removeToolFromScenario('${tool}')" class="text-red-500">🗑</button>
        `;
        toolsBox.appendChild(row);
    });
}

function removeToolFromScenario(tool) {
    console.log(`🗑 Eliminando herramienta ${tool}`);
}

/* ============================================================
   6. Añadir herramienta
   ============================================================ */
function addTool() {
    const select = document.getElementById("available-tools");
    const tool = select.value;

    if (!selectedInstance || !tool) return;

    selectedInstance.tools.push(tool);

    selectInstanceFromScenario(selectedInstance);
}
