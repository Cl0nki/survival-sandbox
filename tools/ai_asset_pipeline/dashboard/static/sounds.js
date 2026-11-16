const state = {
  data: null,
  group: "all",
  pick: {},
  current: null,
  currentButton: null,
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
  if (!response.ok) throw new Error(data.error || "That did not work.");
  return data;
}

function post(path, body) {
  return api(path, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body || {}),
  });
}

function setStatus(text, bad) {
  const node = $("status");
  node.textContent = text || "";
  node.classList.toggle("bad", Boolean(bad));
}

function kb(bytes) {
  return bytes >= 1048576 ? `${(bytes / 1048576).toFixed(1)} MB` : `${Math.max(1, Math.round(bytes / 1024))} KB`;
}

function metaLine(file) {
  const parts = [];
  if (file.seconds != null) parts.push(`${file.seconds}s`);
  parts.push(kb(file.bytes));
  return parts.join(" · ");
}

function eventById(id) {
  return state.data.events.find((event) => event.id === id);
}

function stopPlayback() {
  if (state.current) {
    state.current.pause();
    state.current = null;
  }
  if (state.currentButton) {
    state.currentButton.classList.remove("live");
    state.currentButton.textContent = state.currentButton.dataset.label || "▶";
    state.currentButton = null;
  }
}

// Applies the event's volume and pitch so the preview is close to what the game plays.
function play(url, button, tuning) {
  const wasThis = state.currentButton === button;
  stopPlayback();
  if (wasThis) return;
  const audio = new Audio(url);
  if (tuning) {
    audio.volume = Math.min(1, Math.max(0.02, Math.pow(10, tuning.volume_db / 20)));
    const pitch = tuning.pitch_min + Math.random() * (tuning.pitch_max - tuning.pitch_min);
    audio.preservesPitch = false;
    audio.playbackRate = pitch;
  }
  audio.addEventListener("ended", stopPlayback);
  audio.addEventListener("error", () => {
    stopPlayback();
    setStatus("The browser could not play that file.", true);
  });
  state.current = audio;
  state.currentButton = button;
  button.dataset.label = button.dataset.label || button.textContent;
  button.classList.add("live");
  button.textContent = "■";
  audio.play().catch(() => stopPlayback());
}

function playButton(url, tuning) {
  const button = el("button", "round", "▶");
  button.type = "button";
  button.title = "Play";
  button.addEventListener("click", (clickEvent) => {
    clickEvent.stopPropagation();
    play(url, button, tuning);
  });
  return button;
}

function adopt(data, message) {
  state.data = data;
  render();
  if (message !== undefined) setStatus(message);
}

async function act(path, body, fallback) {
  try {
    const data = await post(path, body);
    adopt(data, data.message || fallback || "");
  } catch (error) {
    setStatus(error.message, true);
  }
}

function assign(name, eventId) {
  if (!eventId) {
    setStatus("Pick which event that sound belongs to.", true);
    return;
  }
  delete state.pick[name];
  stopPlayback();
  act("/api/sounds/assign", { name, event: eventId });
}

function renderSummary() {
  const data = state.data;
  const files = data.events.reduce((sum, event) => sum + event.files.length, 0);
  $("summary").textContent = `${data.covered} of ${data.total} events have a sound · ${files} file${files === 1 ? "" : "s"} · saved to ${data.audio_dir}`;
  const button = $("import");
  button.textContent = data.pending_import ? `Import into Godot (${data.pending_import} new)` : "Import into Godot";
  button.disabled = !data.godot;
  button.title = data.godot
    ? "Runs Godot headless so new files are imported. The game also plays them before this."
    : "Godot was not found. Set GODOT_BIN in tools/ai_asset_pipeline/.env.";
}

function renderFilters() {
  const root = $("filters");
  root.replaceChildren();
  const groups = ["all", ...new Set(state.data.events.map((event) => event.group))];
  groups.forEach((group) => {
    const chip = el("button", `chip${state.group === group ? " on" : ""}`, group === "all" ? "All" : group);
    chip.type = "button";
    chip.addEventListener("click", () => {
      state.group = group;
      render();
    });
    root.append(chip);
  });
}

function slider(label, key, event, min, max, step, format) {
  const row = el("label");
  row.append(el("span", "", label));
  const input = document.createElement("input");
  input.type = "range";
  input.min = min;
  input.max = max;
  input.step = step;
  input.value = event.tuning[key];
  const out = el("output", "", format(event.tuning[key]));
  input.addEventListener("input", () => {
    out.textContent = format(Number(input.value));
  });
  input.addEventListener("change", () => {
    const body = { event: event.id };
    event.tuning[key] = Number(input.value);
    ["volume_db", "pitch_min", "pitch_max", "cooldown", "max_distance"].forEach((name) => {
      body[name] = event.tuning[name];
    });
    act("/api/sounds/tune", body, "Saved.");
  });
  row.append(input, out);
  return row;
}

function tuneBox(event) {
  const box = el("details", "tune");
  box.append(el("summary", "", "Tune"));
  box.append(
    slider("Volume", "volume_db", event, -40, 12, 0.5, (value) => `${value > 0 ? "+" : ""}${value} dB`),
    slider("Pitch low", "pitch_min", event, 0.5, 2, 0.01, (value) => `${Number(value).toFixed(2)}x`),
    slider("Pitch high", "pitch_max", event, 0.5, 2, 0.01, (value) => `${Number(value).toFixed(2)}x`),
    slider("Cooldown", "cooldown", event, 0, 2, 0.01, (value) => `${Number(value).toFixed(2)}s`),
    slider("Hearing", "max_distance", event, 5, 120, 1, (value) => `${value} m`),
  );
  const actions = el("div", "tune-actions");
  const reset = el("button", "", "Reset to defaults");
  reset.type = "button";
  reset.addEventListener("click", () => act("/api/sounds/tune/reset", { event: event.id }));
  const test = el("button", "", "Test");
  test.type = "button";
  test.addEventListener("click", () => {
    if (!event.files.length) {
      setStatus("Add a sound to this event first.", true);
      return;
    }
    const file = event.files[Math.floor(Math.random() * event.files.length)];
    play(`/sound-file/bank/${event.id}/${encodeURIComponent(file.name)}`, test, event.tuning);
  });
  actions.append(test, reset);
  box.append(actions);
  return box;
}

function findLinks(event) {
  const wrap = el("p", "find");
  wrap.append(document.createTextNode("Find more: "));
  const query = encodeURIComponent(event.find);
  const links = [
    ["Freesound CC0", `https://freesound.org/search/?q=${query}&f=license%3A%22Creative+Commons+0%22`],
    ["OpenGameArt", `https://opengameart.org/art-search?keys=${query}`],
  ];
  links.forEach(([label, href]) => {
    const link = el("a", "", label);
    link.href = href;
    link.target = "_blank";
    link.rel = "noopener noreferrer";
    wrap.append(link);
  });
  return wrap;
}

function soundRow(event, file) {
  const row = el("div", "snd");
  const url = `/sound-file/bank/${event.id}/${encodeURIComponent(file.name)}`;
  row.append(playButton(url, event.tuning));
  const text = el("div");
  text.append(el("div", "name", file.name));
  const sub = el("div", "sub", metaLine(file));
  if (!file.imported) {
    const warn = el("span", "warn", " · not imported yet");
    warn.title = "The game still plays it. Import into Godot bakes it for exports.";
    sub.append(warn);
  }
  text.append(sub);
  row.append(text);
  const remove = el("button", "x", "×");
  remove.type = "button";
  remove.title = "Remove from the game";
  remove.addEventListener("click", () => {
    if (state.current) stopPlayback();
    act("/api/sounds/remove", { event: event.id, name: file.name }, "Removed.");
  });
  row.append(remove);
  return row;
}

function column(event) {
  const node = el("section", "column");
  const head = el("header");
  const line = el("div", "line");
  line.append(el("h2", "", event.label));
  const count = el("span", `count${event.files.length ? "" : " none"}`, event.files.length ? `${event.files.length} sound${event.files.length === 1 ? "" : "s"}` : "silent");
  line.append(count);
  head.append(line, el("p", "played", event.played));
  node.append(head);

  const cards = el("div", "cards");
  if (event.files.length) {
    event.files.forEach((file) => cards.append(soundRow(event, file)));
  } else {
    cards.append(el("p", "empty", "Nothing here yet, so this event is silent in the game. Drop a sound from the inbox onto this column."));
  }
  node.append(cards, findLinks(event), tuneBox(event));

  node.addEventListener("dragover", (dragEvent) => {
    if (dragEvent.dataTransfer.types.includes("text/x-sound-inbox")) {
      dragEvent.preventDefault();
      node.classList.add("drop");
    }
  });
  node.addEventListener("dragleave", () => node.classList.remove("drop"));
  node.addEventListener("drop", (dragEvent) => {
    node.classList.remove("drop");
    const name = dragEvent.dataTransfer.getData("text/x-sound-inbox");
    if (!name) return;
    dragEvent.preventDefault();
    assign(name, event.id);
  });
  return node;
}

function renderBoard() {
  const board = $("board");
  board.replaceChildren();
  state.data.events
    .filter((event) => state.group === "all" || event.group === state.group)
    .forEach((event) => board.append(column(event)));
}

function inboxRow(item) {
  const row = el("div", "pick");
  row.draggable = true;
  row.addEventListener("dragstart", (dragEvent) => {
    dragEvent.dataTransfer.setData("text/x-sound-inbox", item.name);
    dragEvent.dataTransfer.effectAllowed = "move";
  });
  row.append(playButton(`/sound-file/inbox/${encodeURIComponent(item.name)}`, null));
  const text = el("div");
  text.append(el("div", "name", item.name), el("div", "sub", metaLine(item)));
  row.append(text);

  const controls = el("div", "controls");
  const select = document.createElement("select");
  const blank = el("option", "", "Choose an event…");
  blank.value = "";
  select.append(blank);
  state.data.events.forEach((event) => {
    const option = el("option", "", event.label);
    option.value = event.id;
    select.append(option);
  });
  select.value = state.pick[item.name] ?? item.suggest ?? "";
  select.addEventListener("change", () => {
    state.pick[item.name] = select.value;
    add.disabled = !select.value;
  });
  const add = el("button", "add", "Add");
  add.type = "button";
  add.disabled = !select.value;
  add.addEventListener("click", () => assign(item.name, select.value));
  const remove = el("button", "x", "×");
  remove.type = "button";
  remove.title = "Delete from the inbox";
  remove.addEventListener("click", () => {
    stopPlayback();
    act("/api/sounds/inbox/delete", { name: item.name }, "Removed from the inbox.");
  });
  controls.append(select, add, remove);
  row.append(controls);
  return row;
}

async function uploadFiles(files) {
  const list = [...files];
  if (!list.length) return;
  const form = new FormData();
  list.forEach((file) => form.append("files", file, file.name));
  setStatus(`Uploading ${list.length} file${list.length === 1 ? "" : "s"}…`);
  try {
    const data = await api("/api/sounds/upload", { method: "POST", body: form });
    adopt(data, data.message);
  } catch (error) {
    setStatus(error.message, true);
  }
}

function uploadBox() {
  const label = el("label", "upload");
  label.append(document.createTextNode("Drop WAV, OGG, MP3 or a pack ZIP here, or click to choose"));
  const input = document.createElement("input");
  input.type = "file";
  input.multiple = true;
  input.accept = ".wav,.ogg,.mp3,.zip,audio/*";
  input.addEventListener("change", () => {
    uploadFiles(input.files);
    input.value = "";
  });
  label.append(input);
  label.addEventListener("dragover", (event) => {
    if (event.dataTransfer.types.includes("Files")) {
      event.preventDefault();
      label.classList.add("over");
    }
  });
  label.addEventListener("dragleave", () => label.classList.remove("over"));
  label.addEventListener("drop", (event) => {
    event.preventDefault();
    label.classList.remove("over");
    uploadFiles(event.dataTransfer.files);
  });
  return label;
}

function scanBox() {
  const box = el("div", "scan");
  const path = document.createElement("input");
  path.placeholder = "C:\\Users\\Admin\\Downloads  or  a .zip path";
  path.value = localStorage.getItem("sounds.scan.path") || "";
  const query = document.createElement("input");
  query.placeholder = "Only names with… (footstep)";
  query.value = localStorage.getItem("sounds.scan.query") || "";
  const limit = document.createElement("input");
  limit.type = "number";
  limit.min = 1;
  limit.max = 800;
  limit.value = localStorage.getItem("sounds.scan.limit") || "200";
  limit.title = "Most sounds to copy into the inbox";
  const two = el("div", "two");
  two.append(query, limit);
  const go = el("button", "small", "Scan and add to inbox");
  go.type = "button";
  go.addEventListener("click", async () => {
    localStorage.setItem("sounds.scan.path", path.value);
    localStorage.setItem("sounds.scan.query", query.value);
    localStorage.setItem("sounds.scan.limit", limit.value);
    go.disabled = true;
    setStatus("Scanning…");
    await act("/api/sounds/scan", { path: path.value, query: query.value, limit: Number(limit.value) || 200 });
    go.disabled = false;
  });
  box.append(path, two, go);
  return box;
}

function sourceRow(source) {
  const node = el("div", "source");
  const title = el("div");
  const link = el("a", "source-link", source.name);
  link.href = source.url;
  link.target = "_blank";
  link.rel = "noopener noreferrer";
  title.append(link, el("span", "lic", source.license));
  node.append(title, el("p", "muted", source.note));
  const chips = el("div", "for");
  source.best_for.forEach((id) => {
    const event = eventById(id);
    if (event) chips.append(el("span", "tag", event.label));
  });
  node.append(chips);
  return node;
}

function renderDrawer() {
  const drawer = $("drawer");
  const scrollTop = drawer.scrollTop;
  drawer.replaceChildren();
  drawer.append(el("h2", "", "Add sounds"));
  drawer.append(el("p", "hint", "Files wait in the inbox until you pick an event. Drag one onto a column, or choose and press Add."));
  drawer.append(uploadBox());

  drawer.append(el("h3", "", "Scan a folder or ZIP on this PC"));
  drawer.append(el("p", "hint", "Good for big downloads such as Sonniss. The filter keeps only matching names and folders."));
  drawer.append(scanBox());

  const head = el("div", "inbox-head");
  head.append(el("h3", "", `Inbox (${state.data.inbox.length})`));
  if (state.data.inbox.length) {
    const clear = el("button", "small", "Clear");
    clear.type = "button";
    clear.addEventListener("click", () => {
      stopPlayback();
      act("/api/sounds/inbox/clear", {}, "Cleared.");
    });
    head.append(clear);
  }
  drawer.append(head);
  const inbox = el("div", "inbox");
  if (state.data.inbox.length) {
    state.data.inbox.forEach((item) => inbox.append(inboxRow(item)));
  } else {
    inbox.append(el("p", "empty", "Empty. Upload or scan to fill it."));
  }
  drawer.append(inbox);

  drawer.append(el("h3", "", "Where to get free sounds"));
  state.data.sources.forEach((source) => drawer.append(sourceRow(source)));
  drawer.append(el("p", "drawer-note", `The game reads ${state.data.manifest}. Sounds take effect the next time the game starts. Check each file's licence before you ship.`));
  drawer.scrollTop = scrollTop;
}

function render() {
  renderSummary();
  renderFilters();
  renderBoard();
  renderDrawer();
}

$("import").addEventListener("click", async () => {
  const button = $("import");
  button.disabled = true;
  setStatus("Godot is importing. This can take a little while…");
  try {
    const data = await post("/api/sounds/import", {});
    adopt(data, data.message);
  } catch (error) {
    setStatus(error.message, true);
  }
  button.disabled = !(state.data && state.data.godot);
});

window.addEventListener("beforeunload", stopPlayback);

(async function start() {
  try {
    adopt(await api("/api/sounds"), "");
  } catch (error) {
    setStatus(error.message, true);
  }
})();
