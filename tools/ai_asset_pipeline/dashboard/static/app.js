const state = { bootstrap: null, assets: [], jobs: [], selected: null, yaw: 0.6, pitch: 0.4, zoom: 1.4, mesh: null };

const $ = (id) => document.getElementById(id);

async function api(path, options) {
  const response = await fetch(path, options);
  const data = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(data.error || response.statusText);
  return data;
}

function mediaUrl(asset, relative) {
  const [kind, filename] = relative.split("/");
  if (!kind || !filename) return "";
  return `/media/${asset.asset_id}/${kind}/${encodeURIComponent(filename)}`;
}

function reviewImageFile(asset) {
  const files = [...(asset.processed_files || []), ...(asset.original_files || [])];
  return files.find((file) => /(^|\/)albedo\.png$/.test(file))
    || files.find((file) => file.startsWith("preview/") && file.endsWith(".png"))
    || files.find((file) => file.endsWith(".png"))
    || "";
}

function thumb(asset) {
  const files = [...(asset.processed_files || []), ...(asset.original_files || [])];
  const preview = files.find((file) => file.startsWith("preview/") && file.endsWith(".png"));
  const image = preview || files.find((file) => file.endsWith(".png"));
  return image ? mediaUrl(asset, image) : "";
}

function renderLibrary() {
  const query = $("search").value.toLowerCase();
  const category = $("filter-category").value;
  const status = $("filter-status").value;
  const grid = $("library-grid");
  grid.innerHTML = "";
  const known = new Set();
  state.assets.forEach((asset) => known.add(asset.category));
  if ($("filter-category").options.length <= 1) {
    [...known].sort().forEach((name) => {
      const option = document.createElement("option");
      option.value = name;
      option.textContent = name;
      $("filter-category").appendChild(option);
    });
  }
  state.assets.filter((asset) => {
    const haystack = `${asset.asset_name} ${asset.category} ${asset.prompt}`.toLowerCase();
    if (query && !haystack.includes(query)) return false;
    if (category && asset.category !== category) return false;
    if (status === "rejected") return asset.approval_status === "rejected";
    if (status === "approved") return asset.approval_status === "approved";
    if (status && asset.processing_status !== status && asset.approval_status !== status) return false;
    return true;
  }).forEach((asset) => {
    const card = document.createElement("article");
    const image = thumb(asset);
    card.innerHTML = `${image ? `<img src="${image}" alt="">` : "<p>No preview image</p>"}
      <h2>${asset.asset_name}</h2>
      <p>${asset.category} · ${asset.provider || "unknown"} · v${asset.version}</p>
      <p class="${asset.processing_status === "failed" ? "bad" : "ok"}">${asset.approval_status} / ${asset.processing_status}</p>`;
    card.addEventListener("click", () => selectAsset(asset.asset_id));
    if (asset.approval_status !== "approved" && image) {
      const remove = document.createElement("button");
      remove.type = "button";
      remove.className = "danger";
      remove.textContent = "Remove";
      remove.addEventListener("click", (event) => {
        event.stopPropagation();
        removeAsset(asset);
      });
      card.appendChild(remove);
    }
    grid.appendChild(card);
  });
}

function renderQueue() {
  const list = $("queue-list");
  list.innerHTML = "";
  state.jobs.forEach((job) => {
    const card = document.createElement("article");
    const errors = (job.errors || []).join("\n");
    const request = job.request || {};
    card.innerHTML = `<h2>${request.name || job.job_id}</h2>
      <p>${request.kind || "job"} / ${request.category || ""}</p>
      <p class="${job.status === "failed" ? "bad" : "ok"}">${job.status}</p>
      <p>${job.message || ""}</p>
      <pre>${errors}</pre>`;
    if (job.status === "failed" || job.status === "ready_for_review") {
      const button = document.createElement("button");
      button.type = "button";
      button.textContent = "Retry";
      button.addEventListener("click", async () => {
        await api(`/api/jobs/${job.job_id}/retry`, { method: "POST" });
        await refresh();
      });
      card.appendChild(button);
    }
    list.appendChild(card);
  });
}

function chosenPicture(name) {
  return (state.assets || []).find((asset) => asset.asset_name === name && asset.approval_status !== "rejected" && ["ready_for_review", "approved"].includes(asset.processing_status));
}

function reviewLabel(asset) {
  if (asset.approval_status === "approved") return "In the game";
  if (asset.approval_status === "rejected") return "Set aside";
  if (asset.processing_status === "failed") return "Failed";
  if (asset.processing_status === "ready_for_review") return "Ready for review";
  return asset.processing_status || "Review";
}

async function selectAsset(id) {
  state.selected = await api(`/api/assets/${id}`);
  document.querySelectorAll("nav button").forEach((button) => button.classList.toggle("active", button.dataset.tab === "preview"));
  document.querySelectorAll("main section").forEach((section) => { section.hidden = section.id !== "preview"; });
  const asset = state.selected;
  const icon = asset.category === "item_icon";
  $("preview-title").textContent = asset.asset_name;
  const meshNote = asset.polygon_count ? `${asset.polygon_count} triangles` : asset.model || asset.provider;
  $("preview-meta").textContent = `${asset.category} · ${asset.provider} · ${meshNote}`;
  $("preview-status").textContent = reviewLabel(asset);
  $("preview-status").className = asset.processing_status === "failed" || asset.approval_status === "rejected" ? "bad" : "ok";
  const image = thumb(asset);
  $("preview-image").hidden = !image;
  if (image) $("preview-image").src = image;
  const glb = (asset.processed_files || []).find((file) => file.endsWith(".glb") && !file.includes("lod"));
  state.mesh = null;
  $("preview-3d").hidden = !glb;
  $("tile-control").hidden = icon || !image || Boolean(glb);
  $("reprocess-label").hidden = asset.kind === "texture" || !glb;
  $("remove").disabled = asset.approval_status === "approved";
  $("preview-edit-image").disabled = asset.kind !== "texture" || !reviewImageFile(asset);
  if (state.editAsset !== asset.asset_id) {
    $("preview-edit").value = "";
    state.editAsset = asset.asset_id;
  }
  $("preview-hint").textContent = asset.approval_status === "approved"
    ? "This picture is already in the game. Keep can replace it after you check the box below."
    : "Keep copies this picture into the game. Remove deletes this review copy.";
  if (glb) loadMesh(mediaUrl(asset, glb));
  const notes = $("preview-notes");
  notes.innerHTML = "";
  [...(asset.errors || []), ...(asset.warnings || []), ...(asset.manual_steps || [])].forEach((line) => {
    const item = document.createElement("li");
    item.textContent = line;
    notes.appendChild(item);
  });
  const sent = (asset.generation_parameters && asset.generation_parameters.sent_prompt) || asset.prompt || "";
  $("preview-prompt").value = sent;
  $("preview-json").textContent = JSON.stringify(asset, null, 2);
  const strip = $("preview-strip");
  strip.innerHTML = "";
  state.assets.filter((item) => item.asset_name === asset.asset_name).forEach((item) => {
    const shot = thumb(item);
    if (!shot) return;
    const choice = document.createElement("button");
    choice.type = "button";
    choice.className = item.asset_id === asset.asset_id ? "current" : "";
    choice.title = reviewLabel(item);
    const picture = document.createElement("img");
    picture.alt = item.asset_name;
    picture.src = shot;
    choice.appendChild(picture);
    choice.addEventListener("click", () => selectAsset(item.asset_id));
    strip.appendChild(choice);
  });
}

async function removeAsset(asset) {
  if (!asset) return;
  try {
    await api(`/api/assets/${asset.asset_id}/delete`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: "{}",
    });
    const name = asset.asset_name;
    const removed = asset.asset_id;
    await refresh();
    state.statusNote = `Removed ${name}.`;
    $("status-line").textContent = state.statusNote;
    if (state.selected && state.selected.asset_id === removed) {
      const next = (state.assets || []).find((item) => item.asset_name === name);
      if (next) await selectAsset(next.asset_id);
      else {
        state.selected = null;
        $("preview-title").textContent = "Nothing selected";
        $("preview-meta").textContent = "That picture was removed.";
        $("preview-image").hidden = true;
        $("preview-3d").hidden = true;
        $("preview-status").textContent = "";
        $("preview-notes").innerHTML = "";
        $("preview-strip").innerHTML = "";
        $("preview-prompt").value = "";
        $("preview-edit").value = "";
        $("preview-edit-image").disabled = true;
        $("preview-json").textContent = "";
      }
    }
  } catch (error) {
    state.statusNote = error.message;
    $("status-line").textContent = error.message;
  }
}

async function loadMesh(url) {
  const buffer = await fetch(url).then((response) => response.arrayBuffer());
  const view = new DataView(buffer);
  if (view.getUint32(0, true) !== 0x46546c67) return;
  const jsonLength = view.getUint32(12, true);
  const documentJson = JSON.parse(new TextDecoder().decode(new Uint8Array(buffer, 20, jsonLength)));
  const binStart = 20 + jsonLength + 8;
  const mesh = documentJson.meshes && documentJson.meshes[0];
  if (!mesh) return;
  const primitive = mesh.primitives[0];
  const positions = readAccessor(documentJson, buffer, binStart, primitive.attributes.POSITION);
  const normals = primitive.attributes.NORMAL !== undefined ? readAccessor(documentJson, buffer, binStart, primitive.attributes.NORMAL) : null;
  const indices = primitive.indices !== undefined ? readIndices(documentJson, buffer, binStart, primitive.indices) : null;
  state.mesh = { positions, normals, indices };
  drawMesh();
}

function accessorView(documentJson, buffer, binStart, index) {
  const accessor = documentJson.accessors[index];
  const bufferView = documentJson.bufferViews[accessor.bufferView];
  const start = binStart + (bufferView.byteOffset || 0) + (accessor.byteOffset || 0);
  return { accessor, start };
}

function readAccessor(documentJson, buffer, binStart, index) {
  const { accessor, start } = accessorView(documentJson, buffer, binStart, index);
  const view = new DataView(buffer, start);
  const values = [];
  for (let i = 0; i < accessor.count; i += 1) {
    values.push([view.getFloat32(i * 12, true), view.getFloat32(i * 12 + 4, true), view.getFloat32(i * 12 + 8, true)]);
  }
  return values;
}

function readIndices(documentJson, buffer, binStart, index) {
  const { accessor, start } = accessorView(documentJson, buffer, binStart, index);
  const view = new DataView(buffer, start);
  const values = [];
  const width = accessor.componentType === 5125 ? 4 : 2;
  for (let i = 0; i < accessor.count; i += 1) {
    values.push(width === 4 ? view.getUint32(i * 4, true) : view.getUint16(i * 2, true));
  }
  return values;
}

function drawMesh() {
  const canvas = $("preview-3d");
  const context = canvas.getContext("2d");
  context.clearRect(0, 0, canvas.width, canvas.height);
  if (!state.mesh) return;
  const light = Number($("light").value);
  const { positions, normals, indices } = state.mesh;
  const center = positions.reduce((acc, point) => [acc[0] + point[0], acc[1] + point[1], acc[2] + point[2]], [0, 0, 0]).map((value) => value / positions.length);
  const sy = Math.sin(state.yaw);
  const cy = Math.cos(state.yaw);
  const sp = Math.sin(state.pitch);
  const cp = Math.cos(state.pitch);
  const projected = positions.map((point, index) => {
    let x = point[0] - center[0];
    let y = point[1] - center[1];
    let z = point[2] - center[2];
    const x1 = x * cy - z * sy;
    const z1 = x * sy + z * cy;
    const y1 = y * cp - z1 * sp;
    const z2 = y * sp + z1 * cp;
    const scale = 180 * state.zoom / (z2 + 4);
    let shade = light;
    if (normals && normals[index]) {
      const normal = normals[index];
      shade = light * (0.35 + 0.75 * Math.max(0, normal[0] * 0.4 + normal[1] * 0.8 + normal[2] * 0.4));
    }
    return [canvas.width / 2 + x1 * scale, canvas.height / 2 - y1 * scale, z2, shade];
  });
  const triangles = [];
  const source = indices || positions.map((_, index) => index);
  const step = Math.max(1, Math.floor(source.length / 3 / 2500));
  for (let i = 0; i < source.length; i += 3 * step) {
    const a = projected[source[i]];
    const b = projected[source[i + 1]];
    const c = projected[source[i + 2]];
    if (!a || !b || !c) continue;
    triangles.push({ depth: (a[2] + b[2] + c[2]) / 3, a, b, c, shade: (a[3] + b[3] + c[3]) / 3 });
  }
  triangles.sort((left, right) => left.depth - right.depth);
  triangles.forEach((triangle) => {
    const tone = Math.max(0, Math.min(255, triangle.shade * 150));
    context.beginPath();
    context.moveTo(triangle.a[0], triangle.a[1]);
    context.lineTo(triangle.b[0], triangle.b[1]);
    context.lineTo(triangle.c[0], triangle.c[1]);
    context.closePath();
    context.fillStyle = `rgb(${tone * 0.7}, ${tone * 0.75}, ${tone * 0.65})`;
    context.fill();
  });
}

async function refresh() {
  const [assets, jobs] = await Promise.all([api("/api/assets"), api("/api/jobs")]);
  state.assets = assets.assets;
  state.jobs = jobs.jobs;
  $("status-line").textContent = describeStatus();
  renderLibrary();
  renderQueue();
  if (state.itemSignature !== itemArtSignature()) {
    state.itemSignature = itemArtSignature();
    if (state.items) renderIcons();
    if (state.items || state.surfaces) renderIngame();
  }
}

function describeStatus() {
  const active = state.jobs.filter((job) => ["waiting", "generating", "downloading", "processing"].includes(job.status));
  if (active.length) {
    const job = active[0];
    const name = (job.request && job.request.name) || job.job_id;
    return job.message || `Generating ${name}.`;
  }
  const latest = state.jobs.find((job) => job.request && job.request.name);
  if (latest && latest.status === "failed") {
    const reason = (latest.errors && latest.errors[0]) || latest.message || "The job failed.";
    return `${latest.request.name} failed. ${reason}`;
  }
  if (latest && latest.status === "ready_for_review") {
    return `${latest.request.name} is ready for review.`;
  }
  return state.statusNote || "Idle. Generation runs in the background.";
}

function itemArtSignature() {
  return state.assets.map((asset) => `${asset.asset_id}:${asset.asset_name}:${asset.processing_status}`).join("|")
    + state.jobs.map((job) => `${job.job_id}:${job.status}`).join("|");
}

const SIZE = 48;

function shade(color, amount, towardWhite) {
  return color.map((channel, index) => {
    if (index === 3) return channel;
    const next = towardWhite ? channel + (1 - channel) * amount : channel * (1 - amount);
    return Math.max(0, Math.min(1, next));
  });
}

function putPixel(image, x, y, color) {
  const pixel = image.data;
  const offset = (y * SIZE + x) * 4;
  pixel[offset] = Math.round(color[0] * 255);
  pixel[offset + 1] = Math.round(color[1] * 255);
  pixel[offset + 2] = Math.round(color[2] * 255);
  pixel[offset + 3] = 255;
}

function paint(image, x, y, color) {
  if (x < 1 || y < 1 || x >= SIZE - 1 || y >= SIZE - 1) return;
  putPixel(image, x, y, color);
}

function fillRect(image, x, y, width, height, color) {
  for (let py = 0; py < height; py += 1) {
    for (let px = 0; px < width; px += 1) paint(image, x + px, y + py, color);
  }
}

function fillDisc(image, cx, cy, radius, color) {
  for (let py = cy - radius; py <= cy + radius; py += 1) {
    for (let px = cx - radius; px <= cx + radius; px += 1) {
      if (Math.hypot(px - cx, py - cy) <= radius) paint(image, px, py, color);
    }
  }
}

function drawItemIcon(canvas, item) {
  const context = canvas.getContext("2d", { willReadFrequently: true });
  const image = context.createImageData(SIZE, SIZE);
  const swatch = item.swatch;
  const edge = shade(swatch, 0.5, false);
  const ink = shade(swatch, 0.55, true);
  for (let i = 0; i < SIZE * SIZE; i += 1) {
    const offset = i * 4;
    image.data[offset] = Math.round(swatch[0] * 255);
    image.data[offset + 1] = Math.round(swatch[1] * 255);
    image.data[offset + 2] = Math.round(swatch[2] * 255);
    image.data[offset + 3] = 255;
  }
  for (let i = 0; i < SIZE; i += 1) {
    putPixel(image, i, 0, edge);
    putPixel(image, i, SIZE - 1, edge);
    putPixel(image, 0, i, edge);
    putPixel(image, SIZE - 1, i, edge);
  }
  switch (item.category) {
    case "medical":
      fillRect(image, 20, 8, 8, 32, ink);
      fillRect(image, 8, 20, 32, 8, ink);
      break;
    case "ammo":
      fillRect(image, 10, 12, 28, 6, ink);
      fillRect(image, 10, 21, 28, 6, ink);
      fillRect(image, 10, 30, 28, 6, ink);
      break;
    case "food":
      fillDisc(image, 24, 24, 12, ink);
      break;
    case "weapon":
      fillRect(image, 8, 18, 32, 6, ink);
      fillRect(image, 16, 24, 8, 14, ink);
      break;
    case "tool":
      fillRect(image, 10, 10, 28, 8, ink);
      fillRect(image, 21, 18, 6, 22, ink);
      break;
    case "harvest":
      fillRect(image, 16, 22, 16, 16, ink);
      fillRect(image, 20, 14, 8, 10, ink);
      break;
    case "refined":
      fillRect(image, 12, 12, 24, 24, ink);
      fillRect(image, 18, 18, 12, 12, edge);
      break;
    case "component":
      fillRect(image, 8, 8, 12, 12, ink);
      fillRect(image, 28, 8, 12, 12, ink);
      fillRect(image, 8, 28, 12, 12, ink);
      fillRect(image, 28, 28, 12, 12, ink);
      break;
    case "explosive":
      fillDisc(image, 24, 26, 10, ink);
      fillRect(image, 21, 8, 6, 12, ink);
      break;
    default:
      fillRect(image, 14, 14, 20, 20, ink);
  }
  context.putImageData(image, 0, 0);
}

function drawSurface(canvas, item) {
  const context = canvas.getContext("2d");
  context.fillStyle = `rgb(${Math.round(item.swatch[0] * 255)}, ${Math.round(item.swatch[1] * 255)}, ${Math.round(item.swatch[2] * 255)})`;
  context.fillRect(0, 0, SIZE, SIZE);
  const edge = shade(item.swatch, 0.45, false);
  context.fillStyle = `rgb(${Math.round(edge[0] * 255)}, ${Math.round(edge[1] * 255)}, ${Math.round(edge[2] * 255)})`;
  context.fillRect(0, 0, SIZE, 3);
  context.fillRect(0, SIZE - 3, SIZE, 3);
  context.fillRect(0, 0, 3, SIZE);
  context.fillRect(SIZE - 3, 0, 3, SIZE);
}

function paintCards(options) {
  const grid = $(options.gridId);
  const records = options.records;
  if (!grid || !records) return;
  const query = $(options.searchId).value.toLowerCase();
  const category = $(options.categoryId).value;
  const art = $(options.artId).value;
  const visible = records.filter((item) => {
    const group = options.group ? options.group(item) : item.category;
    const haystack = `${item.display_name} ${item.id} ${item.description} ${group}`.toLowerCase();
    if (query && !haystack.includes(query)) return false;
    if (category && group !== category) return false;
    if (art === "missing" && item.has_art) return false;
    if (art === "has" && !item.has_art) return false;
    return true;
  });
  const missing = records.filter((item) => item.needs_art).length;
  $(options.summaryId).textContent = options.summary(records.length, missing);
  grid.innerHTML = "";
  visible.forEach((item) => {
    const card = document.createElement("article");
    card.className = "item-card";
    const icon = document.createElement("canvas");
    icon.className = "item-icon";
    icon.width = SIZE;
    icon.height = SIZE;
    const file = item.has_art && item.art_file && options.artUrl;
    if (file) {
      const picture = document.createElement("img");
      picture.className = "item-art";
      picture.alt = `${item.display_name} icon`;
      picture.src = options.artUrl(item);
      card.appendChild(picture);
    } else {
      card.appendChild(icon);
    }
    const title = document.createElement("h2");
    title.textContent = item.display_name;
    const meta = document.createElement("p");
    const group = options.group ? options.group(item) : item.category;
    meta.textContent = `${group} · ${item.id}`;
    const description = document.createElement("p");
    description.textContent = item.description;
    const badge = document.createElement("p");
    badge.className = item.has_art ? "badge ok" : "badge bad";
    badge.textContent = item.has_art ? options.readyLabel : options.missingLabel;
    card.append(title, meta, description, badge);
    if (options.queue && (!options.queueWhen || options.queueWhen(item))) {
      const running = (state.jobs || []).some((job) => job.request && job.request.name === item.id && ["waiting", "generating", "downloading", "processing"].includes(job.status));
      const button = document.createElement("button");
      button.type = "button";
      button.textContent = running ? "Generating" : options.buttonLabel(item);
      button.disabled = running;
      button.addEventListener("click", () => options.queue(item));
      const row = document.createElement("div");
      row.className = "actions";
      row.append(button);
      if (options.editPrompt) {
        const edit = document.createElement("button");
        edit.type = "button";
        edit.textContent = "Edit prompt";
        edit.disabled = running;
        edit.addEventListener("click", () => options.editPrompt(item));
        row.append(edit);
      }
      card.appendChild(row);
    }
    grid.appendChild(card);
    if (!file) options.draw(icon, item);
  });
}

function renderIcons() {
  paintCards({
    records: state.items,
    gridId: "item-grid",
    searchId: "item-search",
    categoryId: "item-category",
    artId: "item-art",
    summaryId: "item-summary",
    summary: (total, missing) => {
      const ready = total - missing;
      const readyLabel = ready === 1 ? "1 uses an icon file" : `${ready} use an icon file`;
      return `${total} icons. ${readyLabel}, scaled down in the game. ${missing} still use the placeholder.`;
    },
    draw: drawItemIcon,
    readyLabel: "Icon",
    missingLabel: "Placeholder",
    artUrl: (item) => `/item-art/${item.art_file}`,
    queue: queueIcon,
    editPrompt: editIconPrompt,
    buttonLabel: (item) => item.has_art ? "New icon" : "Make icon",
  });
}

function iconRequest(item, extra) {
  return {
    kind: "texture",
    category: "item_icon",
    name: item.id,
    prompt: `Inventory icon of one ${item.display_name}. ${item.description} Side view. Guns point to the right.`,
    provider: "openai",
    icon_category: item.category,
    swatch: item.swatch,
    resolution: 1024,
    variations: 1,
    quality: "medium",
    ...extra,
  };
}

function renderIconDraft() {
  const list = $("icon-prompt-shots");
  list.innerHTML = "";
  (state.iconDraft || []).forEach((entry, index) => {
    const figure = document.createElement("figure");
    const image = document.createElement("img");
    image.alt = "Reference image";
    image.src = entry.url;
    const remove = document.createElement("button");
    remove.type = "button";
    remove.textContent = "Remove";
    remove.addEventListener("click", () => {
      URL.revokeObjectURL(entry.url);
      state.iconDraft.splice(index, 1);
      renderIconDraft();
    });
    figure.append(image, remove);
    list.append(figure);
  });
}

function addIconDraftFiles(files) {
  if (!state.iconDraft) state.iconDraft = [];
  const room = 16 - state.iconDraft.length;
  if (room <= 0) {
    $("icon-prompt-note").textContent = "A prompt can include at most 16 images.";
    return;
  }
  [...files].slice(0, room).forEach((file) => {
    if (!file.type.startsWith("image/")) return;
    state.iconDraft.push({ file, url: URL.createObjectURL(file) });
  });
  renderIconDraft();
}

async function editIconPrompt(item) {
  (state.iconDraft || []).forEach((entry) => URL.revokeObjectURL(entry.url));
  state.iconDraft = [];
  state.iconEdit = item;
  renderIconDraft();
  $("icon-prompt-title").textContent = item.display_name;
  $("icon-prompt-text").value = "";
  $("icon-prompt-note").textContent = "Loading the prompt.";
  $("icon-prompt").showModal();
  try {
    const preview = await api("/api/prompt-preview", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(iconRequest(item)),
    });
    if (state.iconEdit === item) {
      $("icon-prompt-text").value = preview.prompt || "";
      $("icon-prompt-note").textContent = "";
    }
  } catch (error) {
    $("icon-prompt-note").textContent = error.message;
  }
}

async function queueIcon(item) {
  state.statusNote = `Queuing an icon for ${item.display_name}.`;
  $("status-line").textContent = state.statusNote;
  try {
    await api("/api/jobs", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(iconRequest(item)),
    });
    state.statusNote = null;
    document.querySelector('[data-tab="queue"]').click();
    await refresh();
  } catch (error) {
    state.statusNote = error.message;
    $("status-line").textContent = error.message;
  }
}

function ingameRecords() {
  const world = (state.items || []).map((item) => ({
    id: item.id,
    display_name: item.display_name,
    description: item.category === "deployable"
      ? `Placed object is still a colored box. ${item.description}`
      : `World pickup is still a colored box. ${item.description}`,
    category: item.category === "deployable" ? "deployable" : "world pickup",
    swatch: item.swatch,
    has_art: false,
    needs_art: true,
    art_file: "",
  }));
  const surfaces = (state.surfaces || []).map((item) => ({
    ...item,
    category: "building surface",
    description: `${item.category} is still a flat color. ${item.description}`,
  }));
  return [...world, ...surfaces];
}

function renderIngame() {
  if (!state.items && !state.surfaces) return;
  paintCards({
    records: ingameRecords(),
    gridId: "ingame-grid",
    searchId: "ingame-search",
    categoryId: "ingame-category",
    artId: "ingame-art",
    summaryId: "ingame-summary",
    summary: (total, missing) => `${total} world graphics. ${missing} are still a box or a flat color. Wall, floor, post, and stair textures ask the image API.`,
    draw: drawSurface,
    readyLabel: "World art",
    missingLabel: "Needs a model",
    artUrl: (item) => `/texture-art/${item.id}/albedo.png`,
    queue: queueSurface,
    queueWhen: (item) => Boolean(item.pipeline_category),
    buttonLabel: () => "New texture",
  });
}

async function queueSurface(surface) {
  state.statusNote = `Queuing a texture for ${surface.display_name}.`;
  $("status-line").textContent = state.statusNote;
  try {
    await api("/api/jobs", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        kind: "texture",
        category: surface.pipeline_category,
        name: surface.id,
        prompt: `${surface.display_name}. ${surface.description} Seamless tileable surface, no object, no text.`,
        provider: "openai",
        resolution: 1024,
        variations: 1,
        quality: "medium",
      }),
    });
    state.statusNote = null;
    document.querySelector('[data-tab="queue"]').click();
    await refresh();
  } catch (error) {
    state.statusNote = error.message;
    $("status-line").textContent = error.message;
  }
}

function fillSelect(id, names) {
  const select = $(id);
  if (select.options.length > 1) return;
  [...new Set(names)].sort().forEach((name) => {
    const option = document.createElement("option");
    option.value = name;
    option.textContent = name;
    select.appendChild(option);
  });
}

async function loadItems() {
  if (!state.items) {
    const payload = await api("/api/items");
    state.items = payload.items;
    fillSelect("item-category", state.items.map((item) => item.category));
  }
  renderIcons();
}

async function loadIngame() {
  if (!state.items) {
    const payload = await api("/api/items");
    state.items = payload.items;
    fillSelect("item-category", state.items.map((item) => item.category));
  }
  if (!state.surfaces) {
    const payload = await api("/api/surfaces");
    state.surfaces = payload.surfaces;
  }
  fillSelect("ingame-category", ["world pickup", "deployable", "building surface"]);
  renderIngame();
}

document.querySelectorAll("nav button").forEach((button) => {
  button.addEventListener("click", () => {
    document.querySelectorAll("nav button").forEach((item) => item.classList.toggle("active", item === button));
    document.querySelectorAll("main section").forEach((section) => { section.hidden = section.id !== button.dataset.tab; });
    if (button.dataset.tab === "style") loadStyle().catch((error) => { $("style-note").textContent = error.message; });
    if (button.dataset.tab === "icons") loadItems().catch((error) => { $("item-summary").textContent = error.message; });
    if (button.dataset.tab === "ingame") loadIngame().catch((error) => { $("ingame-summary").textContent = error.message; });
  });
});

$("item-search").addEventListener("input", renderIcons);
$("item-category").addEventListener("change", renderIcons);
$("item-art").addEventListener("change", renderIcons);
$("ingame-search").addEventListener("input", renderIngame);
$("ingame-category").addEventListener("change", renderIngame);
$("ingame-art").addEventListener("change", renderIngame);
$("search").addEventListener("input", renderLibrary);
$("filter-category").addEventListener("change", renderLibrary);
$("filter-status").addEventListener("change", renderLibrary);
function drawTiles() {
  const image = $("preview-image");
  const canvas = $("preview-3d");
  if (!image.getAttribute("src")) return;
  const paint = () => {
    const repeats = Number($("tile-repeat").value);
    const context = canvas.getContext("2d");
    context.setTransform(1, 0, 0, 1, 0, 0);
    context.clearRect(0, 0, canvas.width, canvas.height);
    const light = Number($("light").value);
    context.filter = `brightness(${light})`;
    const cellW = canvas.width / repeats;
    const cellH = canvas.height / repeats;
    for (let y = 0; y < repeats; y += 1) {
      for (let x = 0; x < repeats; x += 1) {
        context.drawImage(image, x * cellW, y * cellH, cellW, cellH);
      }
    }
    context.filter = "none";
  };
  if (image.complete) paint();
  else image.addEventListener("load", paint, { once: true });
}

$("light").addEventListener("input", () => {
  $("preview-image").style.filter = `brightness(${$("light").value})`;
  if (state.mesh) drawMesh();
  else drawTiles();
});
$("tile-repeat").addEventListener("input", () => {
  if (state.mesh) return;
  const repeats = Number($("tile-repeat").value);
  $("preview-3d").hidden = repeats <= 1;
  if (repeats > 1) drawTiles();
});
$("preview-3d").addEventListener("pointerdown", (event) => {
  const startX = event.clientX;
  const startY = event.clientY;
  const yaw = state.yaw;
  const pitch = state.pitch;
  function move(next) {
    state.yaw = yaw + (next.clientX - startX) * 0.01;
    state.pitch = pitch + (next.clientY - startY) * 0.01;
    drawMesh();
  }
  function up() {
    window.removeEventListener("pointermove", move);
    window.removeEventListener("pointerup", up);
  }
  window.addEventListener("pointermove", move);
  window.addEventListener("pointerup", up);
});
$("preview-3d").addEventListener("wheel", (event) => {
  event.preventDefault();
  state.zoom = Math.max(0.4, Math.min(4, state.zoom * (event.deltaY > 0 ? 0.9 : 1.1)));
  drawMesh();
}, { passive: false });

function showStyle(style, fillPrompt) {
  $("style-summary").value = style.summary || "";
  $("style-palette").checked = style.use_palette !== false;
  $("style-avoid").value = (style.avoid || []).join("\n");
  if (fillPrompt) $("style-image-prompt").value = style.image_prompt || "";
  const colors = style.palette || {};
  $("style-palette-list").textContent = Object.entries(colors).map(([name, color]) => `${name} ${color}`).join(" · ");
  const image = $("style-image");
  const missing = $("style-image-missing");
  if (style.reference_present) {
    image.hidden = false;
    image.src = `/style-reference.png?v=${Date.now()}`;
    missing.hidden = true;
  } else {
    image.hidden = true;
    image.removeAttribute("src");
    missing.hidden = false;
  }
  const candidate = $("style-candidate");
  if (style.candidate_present) {
    candidate.hidden = false;
    $("style-candidate-image").src = `/style-candidate.png?v=${Date.now()}`;
  } else {
    candidate.hidden = true;
    $("style-candidate-image").removeAttribute("src");
  }
  if (Array.isArray(style.image_screenshots)) renderStyleShots(style.image_screenshots);
}

function renderStyleShots(names) {
  const list = $("style-shot-list");
  list.innerHTML = "";
  names.forEach((name) => {
    const figure = document.createElement("figure");
    const image = document.createElement("img");
    image.alt = "Style prompt screenshot";
    image.src = `/style-screenshots/${encodeURIComponent(name)}?v=${Date.now()}`;
    const remove = document.createElement("button");
    remove.type = "button";
    remove.textContent = "Remove";
    remove.addEventListener("click", () => deleteStyleShot(name));
    figure.append(image, remove);
    list.append(figure);
  });
}

function clipboardImages(data) {
  const files = [];
  if (data && data.files) {
    for (const file of data.files) if (file.type.startsWith("image/")) files.push(file);
  }
  if (!files.length && data && data.items) {
    for (const item of data.items) {
      if (item.kind === "file" && item.type.startsWith("image/")) {
        const file = item.getAsFile();
        if (file) files.push(file);
      }
    }
  }
  return files;
}

async function uploadStyleShots(files) {
  if (!files.length) return;
  const body = new FormData();
  files.forEach((file) => body.append("file", file));
  const response = await fetch("/api/style/screenshots", { method: "POST", body });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(data.error || "The screenshot was not added.");
  if (!state.bootstrap) state.bootstrap = { style: {} };
  if (!state.bootstrap.style) state.bootstrap.style = {};
  state.bootstrap.style.image_screenshots = data.screenshots || [];
  renderStyleShots(state.bootstrap.style.image_screenshots);
  $("style-note").textContent = "Screenshot added. It will be sent with the next style image.";
}

async function deleteStyleShot(name) {
  try {
    const data = await api("/api/style/screenshots/delete", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ name }),
    });
    if (state.bootstrap && state.bootstrap.style) state.bootstrap.style.image_screenshots = data.screenshots || [];
    renderStyleShots(data.screenshots || []);
    $("style-note").textContent = "Screenshot removed.";
  } catch (error) {
    $("style-note").textContent = error.message;
  }
}

async function loadStyle() {
  const bootstrap = await api("/api/bootstrap");
  state.bootstrap = bootstrap;
  showStyle(bootstrap.style, true);
}

$("style-form").addEventListener("submit", async (event) => {
  event.preventDefault();
  try {
    const saved = await api("/api/style", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        summary: $("style-summary").value,
        use_palette: $("style-palette").checked,
        avoid: $("style-avoid").value,
      }),
    });
    if (state.bootstrap && state.bootstrap.style) {
      state.bootstrap.style.summary = saved.summary;
      state.bootstrap.style.use_palette = saved.use_palette;
      state.bootstrap.style.avoid = saved.avoid;
    }
    $("style-note").textContent = saved.use_palette
      ? "Saved. New pictures still name the palette colors."
      : "Saved. New pictures no longer name the palette colors.";
  } catch (error) {
    $("style-note").textContent = error.message;
  }
});

$("style-file").addEventListener("change", async (event) => {
  const file = event.target.files && event.target.files[0];
  if (!file) return;
  const body = new FormData();
  body.append("file", file);
  try {
    const response = await fetch("/api/style/reference", { method: "POST", body });
    const data = await response.json();
    if (!response.ok) throw new Error(data.error || "The style image was not saved.");
    if (!state.bootstrap) state.bootstrap = { style: {} };
    if (!state.bootstrap.style) state.bootstrap.style = {};
    state.bootstrap.style.reference_present = true;
    showStyle(state.bootstrap.style, false);
    $("style-note").textContent = "Style image replaced. New pictures are asked to follow it.";
  } catch (error) {
    $("style-note").textContent = error.message;
  }
  event.target.value = "";
});

$("icon-prompt-file").addEventListener("change", (event) => {
  addIconDraftFiles(event.target.files || []);
  event.target.value = "";
});

$("icon-prompt").addEventListener("paste", (event) => {
  const files = clipboardImages(event.clipboardData);
  if (!files.length) return;
  event.preventDefault();
  addIconDraftFiles(files);
});

$("icon-prompt-cancel").addEventListener("click", () => {
  $("icon-prompt").close();
});

$("icon-prompt-generate").addEventListener("click", async () => {
  const item = state.iconEdit;
  const prompt = $("icon-prompt-text").value.trim();
  if (!item || !prompt) {
    $("icon-prompt-note").textContent = "Write a prompt first.";
    return;
  }
  const button = $("icon-prompt-generate");
  button.disabled = true;
  $("icon-prompt-note").textContent = state.iconDraft && state.iconDraft.length
    ? "Queuing the icon with the reference image."
    : "Queuing the icon.";
  try {
    const paths = [];
    for (const entry of state.iconDraft || []) {
      const body = new FormData();
      body.append("file", entry.file);
      const response = await fetch("/api/upload", { method: "POST", body });
      const data = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(data.error || "The reference image was not uploaded.");
      paths.push(data.path);
    }
    await api("/api/jobs", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(iconRequest(item, { prompt_override: prompt, reference_images: paths })),
    });
    $("icon-prompt").close();
    document.querySelector('[data-tab="queue"]').click();
    await refresh();
  } catch (error) {
    $("icon-prompt-note").textContent = error.message;
  } finally {
    button.disabled = false;
  }
});

$("style-shots").addEventListener("change", async (event) => {
  const files = [...(event.target.files || [])];
  event.target.value = "";
  try {
    await uploadStyleShots(files);
  } catch (error) {
    $("style-note").textContent = error.message;
  }
});

$("style-image-panel").addEventListener("paste", async (event) => {
  const files = clipboardImages(event.clipboardData);
  if (!files.length) return;
  event.preventDefault();
  try {
    await uploadStyleShots(files);
  } catch (error) {
    $("style-note").textContent = error.message;
  }
});

$("style-generate").addEventListener("click", async () => {
  const button = $("style-generate");
  const prompt = $("style-image-prompt").value.trim();
  if (!prompt) {
    $("style-note").textContent = "Write a prompt for the style image.";
    return;
  }
  const shots = (state.bootstrap && state.bootstrap.style && state.bootstrap.style.image_screenshots) || [];
  button.disabled = true;
  $("style-note").textContent = shots.length
    ? `Generating the style image with ${shots.length} screenshot${shots.length === 1 ? "" : "s"}.`
    : "Generating the style image.";
  try {
    const result = await api("/api/style/generate", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ prompt }),
    });
    if (!state.bootstrap) state.bootstrap = { style: {} };
    if (!state.bootstrap.style) state.bootstrap.style = {};
    state.bootstrap.style.image_prompt = result.prompt;
    state.bootstrap.style.candidate_present = true;
    showStyle(state.bootstrap.style, true);
    const count = result.screenshot_count || 0;
    $("style-note").textContent = count
      ? `New style image is ready. It used ${count} screenshot${count === 1 ? "" : "s"}. Use it to replace the current one, or discard it.`
      : "New style image is ready. Use it to replace the current one, or discard it.";
  } catch (error) {
    $("style-note").textContent = error.message;
  } finally {
    button.disabled = false;
  }
});

$("style-use").addEventListener("click", async () => {
  try {
    await api("/api/style/candidate/accept", { method: "POST" });
    if (!state.bootstrap) state.bootstrap = { style: {} };
    if (!state.bootstrap.style) state.bootstrap.style = {};
    state.bootstrap.style.reference_present = true;
    state.bootstrap.style.candidate_present = false;
    showStyle(state.bootstrap.style, false);
    $("style-note").textContent = "Style image replaced. New pictures are asked to follow it.";
  } catch (error) {
    $("style-note").textContent = error.message;
  }
});

$("style-discard").addEventListener("click", async () => {
  try {
    await api("/api/style/candidate/discard", { method: "POST" });
    if (state.bootstrap && state.bootstrap.style) state.bootstrap.style.candidate_present = false;
    showStyle((state.bootstrap && state.bootstrap.style) || {}, false);
    $("style-note").textContent = "Generated style image discarded.";
  } catch (error) {
    $("style-note").textContent = error.message;
  }
});

async function queueReviewed(prompt, referenceImages) {
  const asset = state.selected;
  let request = {};
  if (asset.job_id) request = (await api(`/api/jobs/${asset.job_id}`)).request || {};
  await api("/api/jobs", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      kind: request.kind || asset.kind || "texture",
      category: request.category || asset.category,
      name: request.name || asset.asset_name,
      provider: referenceImages && referenceImages.length ? "openai" : (request.provider || (asset.category === "item_icon" ? "openai" : asset.provider) || "openai"),
      resolution: request.resolution || asset.texture_resolution || 1024,
      quality: request.quality || "medium",
      icon_category: request.icon_category,
      swatch: request.swatch,
      variations: 1,
      prompt_override: prompt,
      reference_images: referenceImages || [],
    }),
  });
}

$("preview-generate").addEventListener("click", async () => {
  const asset = state.selected;
  const prompt = $("preview-prompt").value.trim();
  if (!asset || !prompt) return;
  try {
    await queueReviewed(prompt, []);
    $("status-line").textContent = `Generating a new ${asset.asset_name} image.`;
    document.querySelector('[data-tab="queue"]').click();
    await refresh();
  } catch (error) {
    $("preview-hint").textContent = error.message;
  }
});

$("preview-edit-image").addEventListener("click", async () => {
  const asset = state.selected;
  const change = $("preview-edit").value.trim();
  const relative = asset ? reviewImageFile(asset) : "";
  if (!asset || !relative || asset.kind !== "texture") {
    $("preview-hint").textContent = "This review has no picture to edit.";
    return;
  }
  if (!change) {
    $("preview-hint").textContent = "Describe what to change on this picture.";
    return;
  }
  const button = $("preview-edit-image");
  button.disabled = true;
  try {
    const image = await fetch(mediaUrl(asset, relative));
    if (!image.ok) throw new Error("The review picture could not be read.");
    const body = new FormData();
    body.append("file", await image.blob(), "review.png");
    const uploaded = await fetch("/api/upload", { method: "POST", body });
    const data = await uploaded.json().catch(() => ({}));
    if (!uploaded.ok) throw new Error(data.error || "The review picture was not uploaded.");
    await queueReviewed(change, [data.path]);
    $("status-line").textContent = `Editing ${asset.asset_name}.`;
    document.querySelector('[data-tab="queue"]').click();
    await refresh();
  } catch (error) {
    $("preview-hint").textContent = error.message;
    button.disabled = false;
  }
});

$("approve").addEventListener("click", async () => {
  if (!state.selected) return;
  try {
    await api(`/api/assets/${state.selected.asset_id}/approve`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        acknowledge_limitations: $("ack").checked,
        confirm_overwrite_approved: $("confirm-overwrite").checked,
        force: $("confirm-overwrite").checked,
      }),
    });
    await selectAsset(state.selected.asset_id);
    await refresh();
  } catch (error) {
    $("preview-hint").textContent = error.message;
  }
});

$("remove").addEventListener("click", () => {
  if (state.selected) removeAsset(state.selected);
});

$("reprocess-file").addEventListener("change", async (event) => {
  if (!state.selected || !event.target.files[0]) return;
  const body = new FormData();
  body.append("file", event.target.files[0]);
  const response = await fetch(`/api/assets/${state.selected.asset_id}/reprocess`, { method: "POST", body });
  const data = await response.json();
  if (!response.ok) {
    $("preview-hint").textContent = data.error || "Reprocess failed.";
    return;
  }
  await selectAsset(state.selected.asset_id);
});

api("/api/bootstrap").then((bootstrap) => {
  state.bootstrap = bootstrap;
  return refresh();
}).then(() => loadItems()).catch((error) => {
  $("status-line").textContent = error.message;
});
setInterval(() => { refresh().catch(() => {}); }, 2000);
