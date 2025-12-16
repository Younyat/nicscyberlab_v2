let cy;
let nodeCounter = 0;
let connectionMode = false;
let selectedNodes = [];
let industrialMode = null;

/* =========================
   INIT CYTOSCAPE
========================= */
document.addEventListener("DOMContentLoaded", () => {
    cy = cytoscape({
        container: document.getElementById("cy"),
        elements: [],
        style: [
            {
                selector: "node",
                style: {
                    label: "data(name)",
                    color: "#ffffff",
                    "background-color": "#374151",
                    "border-width": 3,
                    "border-color": "#9ca3af",
                    "font-size": "12px"
                }
            },
            { selector: 'node[type="monitor"]', style: { "background-color": "#16a34a" } },
            { selector: 'node[type="victim"]',  style: { "background-color": "#2563eb" } },
            { selector: 'node[type="attack"]',  style: { "background-color": "#dc2626" } },

            { selector: 'node[type^="industrial_"]', style: {
                shape: "round-rectangle",
                "background-color": "#9333ea",
                "border-color": "#c084fc"
            }},

            {
                selector: "edge",
                style: {
                    width: 2,
                    "line-color": "#9ca3af",
                    "target-arrow-shape": "triangle",
                    "target-arrow-color": "#9ca3af",
                    "curve-style": "bezier"
                }
            }
        ],
        layout: { name: "preset" }
    });

    cy.on("select", "node", evt => {

        /* === MODO INDUSTRIAL === */
        if (industrialMode) {
            addIndustrialComponent(industrialMode);
            industrialMode = null;
            cy.$(":selected").unselect();
            return;
        }

        /* === MODO CONEXIÓN === */
        if (!connectionMode) return;

        selectedNodes.push(evt.target);
        if (selectedNodes.length === 2) {
            connectNodes(selectedNodes[0], selectedNodes[1]);
            selectedNodes = [];
            connectionMode = false;
            toast("Modo conexión desactivado");
        }
    });

    updateStats();
});

/* =========================
   LOAD BASE SCENARIO
========================= */
async function loadScenario() {
    try {
        const res = await fetch("http://127.0.0.1:5001/api/get_scenario/file");
        if (!res.ok) throw new Error("Error cargando escenario");

        const scenario = await res.json();

        cy.elements().remove();
        nodeCounter = 0;

        const elements = [];

        scenario.nodes.forEach(n => {
            elements.push({
                group: "nodes",
                data: {
                    id: n.id,
                    name: n.name,
                    type: n.type,
                    ...n.properties
                },
                position: n.position
            });

            const num = parseInt(n.id.replace("node", ""));
            if (!isNaN(num) && num > nodeCounter) nodeCounter = num;
        });

        scenario.edges.forEach(e => {
            elements.push({
                group: "edges",
                data: e
            });
        });

        cy.add(elements);
        updateStats();
        toast("Escenario base cargado");

    } catch (e) {
        console.error(e);
        toast("Error cargando escenario base");
    }
}

/* =========================
   INDUSTRIAL MODE
========================= */
function setIndustrialMode(type) {
    industrialMode = type;
    toast(`Modo industrial: ${type}. Selecciona un nodo base`);
}

function addIndustrialComponent(type) {
    const selected = cy.$("node:selected");
    if (selected.length !== 1) {
        toast("Selecciona un nodo base");
        return;
    }

    const base = selected[0];
    if (!["monitor", "victim", "attack"].includes(base.data("type"))) {
        toast("Solo se puede enlazar a nodos base");
        return;
    }

    const id = `${type}_${Date.now()}`;

    cy.add([
        {
            group: "nodes",
            data: {
                id,
                name: type.toUpperCase(),
                type: `industrial_${type}`,
                industrial: true,
                linked_to: base.id()
            },
            position: {
                x: base.position("x") + 120,
                y: base.position("y") + 120
            }
        },
        {
            group: "edges",
            data: {
                id: `edge_${base.id()}_${id}`,
                source: base.id(),
                target: id
            }
        }
    ]);

    updateStats();
    toast("Componente industrial añadido");
}

/* =========================
   CONNECTION MODE
========================= */
function toggleConnectionMode() {
    connectionMode = !connectionMode;
    selectedNodes = [];
    toast(connectionMode ? "Modo conexión activo" : "Modo conexión desactivado");
}

function connectNodes(a, b) {
    const id = `edge_${a.id()}_${b.id()}`;
    if (cy.getElementById(id).length > 0) return;

    cy.add({
        group: "edges",
        data: { id, source: a.id(), target: b.id() }
    });

    updateStats();
}

/* =========================
   DELETE / CLEAR
========================= */
function deleteSelected() {
    const selected = cy.$(":selected");

    if (selected.length === 0) {
        toast("No hay selección");
        return;
    }

    const forbidden = selected.filter(el =>
        el.isNode() &&
        ["monitor", "victim", "attack"].includes(el.data("type"))
    );

    if (forbidden.length > 0) {
        toast("No se pueden eliminar nodos base");
        return;
    }

    selected.remove();
    updateStats();
    toast("Elemento eliminado");
}

function clearScenario() {
    const industrialNodes = cy.nodes('[industrial]');
    const industrialEdges = cy.edges().filter(e =>
        industrialNodes.contains(e.source()) ||
        industrialNodes.contains(e.target())
    );

    industrialEdges.remove();
    industrialNodes.remove();

    updateStats();
    toast("Componentes industriales eliminados");
}

/* =========================
   SAVE INDUSTRIAL SCENARIO
========================= */
async function saveIndustrialScenario() {
    const payload = {
        scenario: {
            scenario_name: "industrial_file",
            base_scenario: "scenario/scenario_file.json",
            nodes: cy.nodes().map(n => ({
                id: n.id(),
                name: n.data("name"),
                type: n.data("type"),
                industrial: n.data("industrial") || false,
                linked_to: n.data("linked_to") || null,
                position: n.position()
            })),
            edges: cy.edges().map(e => ({
                id: e.id(),
                source: e.source().id(),
                target: e.target().id()
            }))
        }
    };

    await fetch("http://127.0.0.1:5001/api/save_industrial_scenario", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload)
    });

    toast("Escenario industrial guardado");
}

/* =========================
   UI HELPERS
========================= */
function updateStats() {
    document.getElementById("nodeCount").textContent = cy.nodes().length;
    document.getElementById("edgeCount").textContent = cy.edges().length;
}

function toast(msg) {
    const t = document.getElementById("toast");
    t.textContent = msg;
    t.classList.add("show");
    setTimeout(() => t.classList.remove("show"), 3000);
}
