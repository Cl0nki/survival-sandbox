const RECIPE = new Set(["craft", "cook", "smelt"]);
const SOURCE_FILTERS = [
  ["all", "All"],
  ["gather", "Gather"],
  ["dig", "Dig"],
  ["fill", "Fill"],
  ["craft", "Craft"],
  ["cook", "Cook"],
  ["smelt", "Smelt"],
];

const state = {
  items: [],
  families: {},
  folders: [],
  categories: [],
  query: "",
  source: "all",
  family: "all",
  showDebug: false,
  openId: "",
  creating: false,
  dragId: "",
};

const $ = (id) => document.getElementById(id);

function el(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text != null) node.textContent = text;
  return node;
}

async function api(path, options) {
  const response = await fetch(path, options);
  const data = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(data.error || "The Codex could not save that.");
  return data;
}

function setStatus(text, bad) {
  const node = $("status");
  node.textContent = text || "";
  node.classList.toggle("bad", Boolean(bad));
}

function swatchCss(swatch) {
  const [red, green, blue] = swatch || [0.7, 0.7, 0.7];
  return `rgb(${Math.round(red * 255)}, ${Math.round(green * 255)}, ${Math.round(blue * 255)})`;
}

function hexToSwatch(hex) {
  const value = hex.replace("#", "");
  return [0, 2, 4].map((index) => parseInt(value.slice(index, index + 2), 16) / 255).concat(1);
}

function swatchToHex(swatch) {
  const part = (channel) => Math.round((channel || 0) * 255).toString(16).padStart(2, "0");
  return `#${part(swatch[0])}${part(swatch[1])}${part(swatch[2])}`;
}

function iconNode(item, large) {
  if (item.has_art) {
    const image = el("img", "icon");
    image.alt = "";
    image.src = `/item-art/${item.id}.png`;
    image.addEventListener("error", () => image.replaceWith(swatchNode(item, large)));
    return image;
  }
  return swatchNode(item, large);
}

function swatchNode(item, _large) {
  const node = el("div", "swatch", (item.display_name || "?").slice(0, 1));
  node.style.background = swatchCss(item.swatch);
  return node;
}

function gateStations(familyId) {
  const families = familyId
    ? [state.families[familyId]].filter(Boolean)
    : Object.values(state.families);
  const gates = [];
  families.forEach((family) => {
    const seen = new Set();
    family.stations.forEach((station) => {
      if (seen.has(station.tier)) return;
      seen.add(station.tier);
      const twins = family.stations.filter((other) => other.tier === station.tier && other.kind !== station.kind);
      const extra = twins.map((other) => other.name).join(", ");
      gates.push({
        ...station,
        family: family.id,
        label: extra ? `${station.name} (also ${extra})` : station.name,
        hint: extra ? `Also ${extra}` : family.label,
      });
    });
  });
  return gates;
}

function stationByKind(kind) {
  return gateStations().find((station) => station.kind === kind) || null;
}

function holdingRecipes(item) {
  return item.sources.filter((source) => RECIPE.has(source.kind) && source.station_kind === item.column);
}

function boardColumns() {
  const columns = [{ id: "gather", title: "Collect", hint: "Gather, dig, or fill" }];
  gateStations().forEach((station) => columns.push({
    id: station.kind,
    title: station.name,
    hint: station.hint,
    family: station.family,
    tier: station.tier,
  }));
  columns.push({ id: "none", title: "No source", hint: "Not in the world yet" });
  return columns;
}

function movesFor(item, columnId) {
  const target = stationByKind(columnId);
  const holding = holdingRecipes(item);
  if (!target || !holding.length || columnId === item.column) return [];
  if (holding.some((source) => source.family !== target.family)) return [];
  if (holding.every((source) => source.tier === target.tier)) return [];
  return holding.map((source) => ({
    family: source.family,
    input: source.input,
    extra: source.extra || "",
    output: item.id,
    tier: target.tier,
  }));
}

function visibleItems() {
  const query = state.query.trim().toLowerCase();
  return state.items.filter((item) => {
    if (item.debug && !state.showDebug) return false;
    if (state.source !== "all" && !item.sources.some((source) => source.kind === state.source)) return false;
    if (state.family !== "all" && !item.sources.some((source) => source.family === state.family)) return false;
    if (!query) return true;
    const haystack = [
      item.display_name,
      item.id,
      item.description,
      item.category,
      ...item.sources.flatMap((source) => [source.chip, source.node_name, source.station, ...(source.biomes || []).map((biome) => biome.name)]),
    ].join(" ").toLowerCase();
    return haystack.includes(query);
  });
}

function renderFilters() {
  const bar = $("filters");
  bar.replaceChildren();
  const add = (label, on, action) => {
    const button = el("button", on ? "chip on" : "chip", label);
    button.type = "button";
    button.addEventListener("click", action);
    bar.appendChild(button);
  };
  SOURCE_FILTERS.forEach(([id, label]) => add(label, state.source === id, () => {
    state.source = id;
    render();
  }));
  add("Any station", state.family === "all", () => {
    state.family = "all";
    render();
  });
  Object.values(state.families).forEach((family) => add(family.label, state.family === family.id, () => {
    state.family = family.id;
    render();
  }));
  add(state.showDebug ? "Hide debug" : "Debug", state.showDebug, () => {
    state.showDebug = !state.showDebug;
    render();
  });
}

function renderBoard() {
  const board = $("board");
  const scrolls = [...board.querySelectorAll(".cards")].map((node) => node.scrollTop);
  const items = visibleItems();
  board.replaceChildren();
  boardColumns().forEach((column) => {
    const section = el("section", "column");
    section.dataset.column = column.id;
    const head = el("header");
    const count = items.filter((item) => item.column === column.id).length;
    head.append(el("h2", "", `${column.title}`), el("p", "meta", `${count} · ${column.hint}`));
    const list = el("div", "cards");
    items.filter((item) => item.column === column.id).forEach((item) => list.appendChild(cardNode(item)));
    if (!list.childElementCount) list.appendChild(el("p", "empty", "Nothing here"));
    section.append(head, list);
    section.addEventListener("dragover", (event) => {
      const item = state.items.find((row) => row.id === state.dragId);
      if (!item || !movesFor(item, column.id).length) return;
      event.preventDefault();
      section.classList.add("drop");
    });
    section.addEventListener("dragleave", () => section.classList.remove("drop"));
    section.addEventListener("drop", (event) => {
      event.preventDefault();
      section.classList.remove("drop");
      const item = state.items.find((row) => row.id === state.dragId);
      if (!item) return;
      const moves = movesFor(item, column.id);
      if (!moves.length) return;
      saveMoves(moves, item.display_name);
    });
    board.appendChild(section);
  });
  board.querySelectorAll(".cards").forEach((node, index) => {
    node.scrollTop = scrolls[index] || 0;
  });
}

function cardNode(item) {
  const button = el("div", "card");
  button.tabIndex = 0;
  button.setAttribute("role", "button");
  if (item.id === state.openId) button.classList.add("selected");
  const movable = holdingRecipes(item).length > 0;
  if (movable) {
    button.classList.add("draggable");
    button.draggable = true;
    button.addEventListener("dragstart", (event) => {
      state.dragId = item.id;
      event.dataTransfer.effectAllowed = "move";
      event.dataTransfer.setData("text/plain", item.id);
    });
    button.addEventListener("dragend", () => {
      state.dragId = "";
      document.querySelectorAll(".column.drop").forEach((node) => node.classList.remove("drop"));
    });
  }
  button.addEventListener("click", () => openItem(item.id));
  button.addEventListener("keydown", (event) => {
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      openItem(item.id);
    }
  });
  const copy = el("div");
  copy.appendChild(el("h3", "", item.display_name));
  const chips = el("div", "chips");
  const shown = item.sources.filter((source) => source.kind !== "loot").slice(0, 3);
  shown.forEach((source) => chips.appendChild(el("span", `tag ${source.kind}`, source.chip)));
  const extra = item.sources.filter((source) => source.kind !== "loot").length - shown.length;
  if (extra > 0) chips.appendChild(el("span", "tag more", `+${extra}`));
  if (!shown.length) chips.appendChild(el("span", "tag more", item.debug ? "Debug" : "No world source"));
  copy.appendChild(chips);
  button.append(iconNode(item), copy);
  return button;
}

function render() {
  renderFilters();
  renderBoard();
  $("shell").classList.toggle("open", state.creating || Boolean(state.openId));
  if (state.creating) renderCreate();
  else if (state.openId) renderDetail(state.items.find((item) => item.id === state.openId));
  else $("drawer").hidden = true;
}

function closeDrawer() {
  state.creating = false;
  state.openId = "";
  render();
}

function openItem(itemId) {
  state.creating = false;
  state.openId = itemId;
  render();
}

function field(label, control) {
  const wrap = el("label", "stack");
  wrap.append(el("span", "", label), control);
  return wrap;
}

function renderDetail(item) {
  const drawer = $("drawer");
  if (!item) {
    drawer.hidden = true;
    return;
  }
  drawer.hidden = false;
  drawer.replaceChildren();
  const head = el("div", "drawer-head");
  const titles = el("div");
  titles.append(el("h2", "", item.display_name), el("p", "id-line", `${item.id} · ${item.category}${item.folder ? " · " + item.folder : ""}`));
  const close = el("button", "ghost", "Close");
  close.type = "button";
  close.addEventListener("click", closeDrawer);
  head.append(titles, close);
  const hero = el("div", "hero");
  hero.appendChild(iconNode(item, true));
  const blurb = el("div");
  if (item.harvest_kind) {
    blurb.appendChild(el("p", "muted", `${item.harvest_kind} · harvest tier ${item.harvest_tier} · power ${item.harvest_power}`));
  }
  hero.appendChild(blurb);

  const name = document.createElement("input");
  name.value = item.display_name;
  const description = document.createElement("textarea");
  description.value = item.description;
  const stack = document.createElement("input");
  stack.type = "number";
  stack.min = "1";
  stack.max = "999";
  stack.value = String(item.max_stack);
  const weight = document.createElement("input");
  weight.type = "number";
  weight.min = "0";
  weight.step = "0.01";
  weight.value = String(item.weight);
  const color = document.createElement("input");
  color.type = "color";
  color.value = swatchToHex(item.swatch);
  const save = el("button", "primary", "Save details");
  save.type = "button";
  save.addEventListener("click", () => saveDetails(item, { name, description, stack, weight, color }));

  const numbers = el("div", "row");
  numbers.append(field("Stack", stack), field("Weight", weight));
  drawer.append(
    head,
    hero,
    field("Name", name),
    field("Description", description),
    numbers,
    field("Color", color),
    save,
    el("h3", "", "Sources"),
  );
  const world = item.sources.filter((source) => source.kind !== "loot");
  if (!world.length) drawer.appendChild(el("p", "muted", "Nothing in the world or a station produces this yet."));
  world.forEach((source) => drawer.appendChild(sourceBlock(item, source)));
  const crates = item.sources.filter((source) => source.kind === "loot");
  if (crates.length) {
    drawer.appendChild(el("h3", "", "Test layout"));
    crates.forEach((source) => {
      const row = el("p", "muted", `${source.label} · ${source.qty}`);
      drawer.appendChild(row);
    });
  }
  if (item.used_by.length) {
    drawer.appendChild(el("h3", "", "Used to make"));
    const list = el("ul", "used");
    item.used_by.forEach((use) => {
      const line = el("li", "", `${use.qty} × ${use.output_name} · ${use.station}`);
      list.appendChild(line);
    });
    drawer.appendChild(list);
  }
}

function sourceBlock(item, source) {
  const block = el("div", "source");
  const title = el("strong", "", source.chip);
  block.appendChild(title);
  if (RECIPE.has(source.kind)) {
    const note = el("p", "muted", source.station_note || "");
    const select = document.createElement("select");
    select.className = "tier";
    gateStations(source.family).forEach((station) => {
      select.appendChild(new Option(station.label, station.kind));
    });
    select.value = source.station_kind || "";
    select.addEventListener("change", () => {
      const station = stationByKind(select.value);
      if (!station || station.tier === source.tier) return;
      saveMoves([{
        family: source.family,
        input: source.input,
        extra: source.extra || "",
        output: item.id,
        tier: station.tier,
      }], item.display_name);
    });
    block.append(note, select);
    return block;
  }
  const where = (source.biomes || []).map((biome) => biome.name).join(", ");
  const bits = [];
  if (source.tool) bits.push(source.tool);
  if (source.qty) bits.push(`×${source.qty}`);
  if (where) bits.push(where);
  if (bits.length) block.appendChild(el("p", "muted", bits.join(" · ")));
  return block;
}

async function saveMoves(moves, name) {
  try {
    const data = await api("/api/codex/tier", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ moves }),
    });
    applyCatalog(data, `Moved ${name}. Now requires ${data.message}.`);
  } catch (error) {
    setStatus(error.message, true);
    render();
  }
}

async function saveDetails(item, fields) {
  try {
    const data = await api("/api/codex/items/update", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        id: item.id,
        display_name: fields.name.value,
        description: fields.description.value,
        max_stack: Number(fields.stack.value),
        weight: Number(fields.weight.value),
        swatch: hexToSwatch(fields.color.value),
      }),
    });
    state.openId = item.id;
    applyCatalog(data, data.message);
  } catch (error) {
    setStatus(error.message, true);
  }
}

function renderCreate() {
  const drawer = $("drawer");
  drawer.hidden = false;
  drawer.replaceChildren();
  const head = el("div", "drawer-head");
  head.append(el("h2", "", "New item"), (() => {
    const close = el("button", "ghost", "Close");
    close.type = "button";
    close.addEventListener("click", closeDrawer);
    return close;
  })());
  const form = document.createElement("form");
  const id = document.createElement("input");
  id.required = true;
  id.placeholder = "iron_buckle";
  id.pattern = "[a-z0-9_]+";
  const name = document.createElement("input");
  name.required = true;
  const description = document.createElement("textarea");
  const category = document.createElement("select");
  (state.categories.length ? state.categories : ["misc"]).forEach((value) => category.appendChild(new Option(value, value)));
  if ([...category.options].some((option) => option.value === "harvest")) category.value = "harvest";
  const folder = document.createElement("select");
  folder.appendChild(new Option("Items root", ""));
  state.folders.forEach((value) => folder.appendChild(new Option(value, value)));
  if ([...folder.options].some((option) => option.value === "harvestable")) folder.value = "harvestable";
  const stack = document.createElement("input");
  stack.type = "number";
  stack.min = "1";
  stack.max = "999";
  stack.value = "20";
  const weight = document.createElement("input");
  weight.type = "number";
  weight.min = "0";
  weight.step = "0.01";
  weight.value = "0.2";
  const color = document.createElement("input");
  color.type = "color";
  color.value = "#c6b48a";
  const useRecipe = document.createElement("input");
  useRecipe.type = "checkbox";
  const recipeBox = document.createElement("fieldset");
  recipeBox.hidden = true;
  const station = document.createElement("select");
  gateStations().forEach((entry) => station.appendChild(new Option(entry.label, entry.kind)));
  const input = document.createElement("input");
  input.setAttribute("list", "codex-items");
  input.placeholder = "log";
  const extra = document.createElement("input");
  extra.setAttribute("list", "codex-items");
  extra.placeholder = "optional";
  const counts = ["in_n", "extra_n", "out_n"].map((key) => {
    const control = document.createElement("input");
    control.type = "number";
    control.min = "0";
    control.max = "99";
    control.value = key === "extra_n" ? "0" : "1";
    control.dataset.key = key;
    return control;
  });
  const alloy = document.createElement("input");
  alloy.type = "checkbox";
  const list = document.createElement("datalist");
  list.id = "codex-items";
  state.items.forEach((item) => {
    const option = document.createElement("option");
    option.value = item.id;
    option.label = item.display_name;
    list.appendChild(option);
  });

  function fillStation() {
    const chosen = stationByKind(station.value);
    const smelt = !chosen || chosen.family === "smelt";
    const extraCount = counts[1].parentElement;
    if (extraCount) extraCount.hidden = smelt;
    if (extra.parentElement) extra.parentElement.hidden = smelt;
    if (alloy.parentElement) alloy.parentElement.hidden = !smelt;
  }

  station.addEventListener("change", fillStation);
  useRecipe.addEventListener("change", () => {
    recipeBox.hidden = !useRecipe.checked;
  });
  const countRow = el("div", "row three");
  countRow.append(field("Input count", counts[0]), field("Extra count", counts[1]), field("Output count", counts[2]));
  recipeBox.append(
    el("legend", "", "First recipe"),
    field("Station", station),
    field("Input", input),
    field("Second ingredient", extra),
    countRow,
    field("Alloy melt", alloy),
  );
  const numbers = el("div", "row");
  numbers.append(field("Stack", stack), field("Weight", weight));
  const cats = el("div", "row");
  cats.append(field("Category", category), field("Folder", folder));
  const recipeToggle = field("Also add a recipe", useRecipe);
  recipeToggle.classList.add("check");
  const submit = el("button", "primary", "Create item");
  submit.type = "submit";
  form.append(
    field("Id", id),
    field("Name", name),
    field("Description", description),
    cats,
    numbers,
    field("Color", color),
    recipeToggle,
    recipeBox,
    list,
    submit,
  );
  fillStation();
  form.addEventListener("submit", (event) => {
    event.preventDefault();
    createFromForm({ id, name, description, category, folder, stack, weight, color, useRecipe, station, input, extra, counts, alloy });
  });
  drawer.append(head, el("p", "muted", "The new card lands on Collect, a station, or No source."), form);
}

async function createFromForm(fields) {
  try {
  const payload = {
    id: fields.id.value.trim(),
    display_name: fields.name.value.trim(),
    description: fields.description.value,
    category: fields.category.value,
    folder: fields.folder.value,
    max_stack: Number(fields.stack.value),
    weight: Number(fields.weight.value),
    swatch: hexToSwatch(fields.color.value),
  };
  if (fields.useRecipe.checked) {
    const chosen = stationByKind(fields.station.value);
    if (!chosen) throw new Error("Pick a station.");
    const smelt = chosen.family === "smelt";
    payload.recipe = {
      kind: smelt ? "smelt" : "craft",
      family: chosen.family,
      tier: chosen.tier,
      input: fields.input.value.trim(),
      extra: smelt ? "" : fields.extra.value.trim(),
      in_n: Number(fields.counts[0].value),
      extra_n: smelt ? 0 : Number(fields.counts[1].value),
      out_n: smelt ? 1 : Number(fields.counts[2].value),
      alloy: smelt && fields.alloy.checked,
    };
  }
    const data = await api("/api/codex/items", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
    state.creating = false;
    state.openId = data.created || payload.id;
    applyCatalog(data, data.message);
  } catch (error) {
    setStatus(error.message, true);
  }
}

function applyCatalog(data, message) {
  state.items = data.items || [];
  state.families = data.families || {};
  state.folders = data.folders || [];
  state.categories = data.categories || [];
  if (message) setStatus(message, false);
  render();
}

$("search").addEventListener("input", (event) => {
  state.query = event.target.value;
  renderBoard();
});
$("new-item").addEventListener("click", () => {
  state.creating = true;
  state.openId = "";
  render();
});
document.addEventListener("keydown", (event) => {
  if (event.key === "Escape") closeDrawer();
});

api("/api/codex").then((data) => {
  const shown = (data.items || []).filter((item) => !item.debug).length;
  applyCatalog(data, `${shown} items`);
}).catch((error) => setStatus(error.message, true));
