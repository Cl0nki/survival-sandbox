const state = { bootstrap: null, assets: [], jobs: [], selected: null, detail: null, production: null, costs: null, yaw: 0.6, pitch: 0.4, zoom: 1.4, mesh: null, libraryFiltersReady: false, imageRotation: 0 };

const $ = (id) => document.getElementById(id);

function showTab(name) {
  document.querySelectorAll("nav button").forEach((button) => button.classList.toggle("active", button.dataset.tab === name));
  document.querySelectorAll("main section").forEach((section) => { section.hidden = section.id !== name; });
  if (name === "production") refreshProduction().catch(() => {});
  if (name === "costs") refreshCosts().catch(() => {});
}

function workshopLabels() {
  const categories = (state.bootstrap && state.bootstrap.workshop && state.bootstrap.workshop.categories) || {};
  return categories;
}

function statusText(value) {
  const labels = (state.bootstrap && state.bootstrap.workshop && state.bootstrap.workshop.status_labels) || {};
  return labels[value] || (value || "").replaceAll("_", " ");
}

function workshopOf(asset) {
  return asset.workshop_category
    || (asset.generation_parameters && asset.generation_parameters.workshop_category)
    || "";
}

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

function fillLibraryFilters() {
  if (state.libraryFiltersReady) return;
  const workshop = workshopLabels();
  Object.keys(workshop).sort().forEach((key) => {
    const option = document.createElement("option");
    option.value = key;
    option.textContent = workshop[key].label || key;
    $("filter-workshop").appendChild(option);
  });
  state.libraryFiltersReady = true;
}

function renderLibrary() {
  fillLibraryFilters();
  const query = $("search").value.toLowerCase();
  const workshop = $("filter-workshop").value;
  const category = $("filter-category").value;
  const provider = $("filter-provider").value;
  const status = $("filter-status").value;
  const sort = $("filter-sort").value;
  const grid = $("library-grid");
  grid.innerHTML = "";
  const known = new Set();
  const providers = new Set();
  state.assets.forEach((asset) => {
    known.add(asset.category);
    if (asset.provider) providers.add(asset.provider);
  });
  const categorySelect = $("filter-category");
  const previous = categorySelect.value;
  categorySelect.innerHTML = '<option value="">All presets</option>';
  [...known].sort().forEach((name) => {
    const option = document.createElement("option");
    option.value = name;
    option.textContent = name;
    categorySelect.appendChild(option);
  });
  categorySelect.value = [...known].includes(previous) ? previous : "";
  const providerSelect = $("filter-provider");
  const previousProvider = providerSelect.value;
  providerSelect.innerHTML = '<option value="">All providers</option>';
  [...providers].sort().forEach((name) => {
    const option = document.createElement("option");
    option.value = name;
    option.textContent = name;
    providerSelect.appendChild(option);
  });
  providerSelect.value = [...providers].includes(previousProvider) ? previousProvider : "";
  let filtered = state.assets.filter((asset) => {
    const workshopCategory = workshopOf(asset);
    const haystack = `${asset.asset_name} ${asset.category} ${workshopCategory} ${asset.provider || ""} ${asset.prompt}`.toLowerCase();
    if (query && !haystack.includes(query)) return false;
    if (workshop && workshopCategory !== workshop) return false;
    if (category && asset.category !== category) return false;
    if (provider && asset.provider !== provider) return false;
    if (status === "rejected") return asset.approval_status === "rejected";
    if (status === "approved") return asset.approval_status === "approved";
    if (status && asset.processing_status !== status && asset.approval_status !== status) return false;
    return true;
  });
  filtered = filtered.slice().sort((left, right) => {
    if (sort === "name") return left.asset_name.localeCompare(right.asset_name);
    if (sort === "status") return `${left.approval_status}${left.processing_status}`.localeCompare(`${right.approval_status}${right.processing_status}`);
    return String(right.created_at || "").localeCompare(String(left.created_at || ""));
  });
  if ($("library-summary")) {
    $("library-summary").textContent = `${filtered.length} asset${filtered.length === 1 ? "" : "s"} shown · ${state.assets.length} total in library`;
  }
  filtered.forEach((asset) => {
    const card = document.createElement("article");
    const image = thumb(asset);
    const workshopCategory = workshopOf(asset);
    card.innerHTML = `${image ? `<img src="${image}" alt="">` : "<p>No preview image</p>"}
      <h2>${asset.asset_name}</h2>
      <p>${workshopCategory || asset.kind} · ${asset.category} · ${asset.provider || "unknown"} · v${asset.version}</p>
      <p class="${asset.processing_status === "failed" ? "bad" : "ok"}">${statusText(asset.approval_status)} / ${statusText(asset.processing_status)}</p>`;
    card.addEventListener("click", () => selectAsset(asset.asset_id));
    if (asset.approval_status !== "approved") {
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

async function refreshProduction() {
  const stats = await api("/api/workshop/stats");
  state.production = stats;
  if (state.bootstrap) state.bootstrap.production = stats;
  renderProduction();
}

async function refreshCosts() {
  const summary = await api("/api/costs/summary");
  state.costs = summary;
  if (state.bootstrap) state.bootstrap.costs = summary;
  renderCosts();
}

function renderCosts() {
  const summary = state.costs || (state.bootstrap && state.bootstrap.costs);
  if (!summary || !$("costs-summary")) return;
  const currency = summary.currency || "USD";
  $("costs-summary").textContent = `Recorded spend ${currency} ${Number(summary.total_usd || 0).toFixed(2)} · this month ${Number(summary.month_usd || 0).toFixed(2)} (${summary.month || ""})`;
  const budgets = summary.budgets || {};
  const monthly = budgets.monthly_usd;
  const within = summary.within_monthly !== false;
  $("costs-budget").textContent = monthly == null
    ? "No monthly budget configured."
    : `Monthly budget $${Number(monthly).toFixed(2)} · ${within ? "within limit" : "over budget"}${budgets.hard_limit ? " (hard limit on)" : " (soft warnings)"}`;
  const fill = (id, map) => {
    const body = $(id);
    if (!body) return;
    body.innerHTML = "";
    const entries = Object.entries(map || {});
    if (!entries.length) {
      body.innerHTML = `<tr><td colspan="2" class="muted">None yet</td></tr>`;
      return;
    }
    entries.forEach(([key, value]) => {
      const tr = document.createElement("tr");
      tr.innerHTML = `<td>${key}</td><td>${Number(value).toFixed(4)}</td>`;
      body.appendChild(tr);
    });
  };
  fill("costs-by-provider", summary.by_provider);
  fill("costs-by-operation", summary.by_operation);
  fill("costs-by-category", summary.by_category);
  $("costs-unknown").textContent = summary.unknown_records
    ? `${summary.unknown_records} cost record(s) have unknown USD (pricing table incomplete).`
    : `${summary.known_records || 0} priced cost record(s).`;
}

function renderProduction() {
  const stats = state.production || (state.bootstrap && state.bootstrap.production);
  const body = $("production-body");
  if (!body || !stats) return;
  body.innerHTML = "";
  (stats.rows || []).forEach((row) => {
    const tr = document.createElement("tr");
    tr.innerHTML = `<td>${row.label}</td><td>${row.approved}</td><td>${row.target}</td><td>${row.remaining}</td><td>${row.in_progress}</td><td>${row.pending_review}</td><td>${row.failed}</td>`;
    body.appendChild(tr);
  });
  const totals = stats.totals || {};
  $("production-summary").textContent = `Approved unique assets toward the ${totals.target || 280}-asset target.`;
  $("production-totals").textContent = `${totals.approved || 0} approved · ${totals.remaining || 0} remaining · ${totals.in_progress || 0} in progress · ${totals.pending_review || 0} ready for review · ${totals.failed || 0} failed`;
}

function fillWorkshopForm() {
  const categorySelect = $("workshop-category");
  if (!categorySelect || categorySelect.options.length) return;
  const workshop = workshopLabels();
  Object.keys(workshop).forEach((key) => {
    const option = document.createElement("option");
    option.value = key;
    option.textContent = workshop[key].label || key;
    categorySelect.appendChild(option);
  });
  fillWorkshopPresets();
}

function fillWorkshopPresets() {
  const workshopId = $("workshop-category").value;
  const profile = workshopLabels()[workshopId] || {};
  const section = profile.catalog_section || workshopId;
  const catalog = (state.bootstrap && state.bootstrap.catalog) || {};
  const presets = catalog[section] || {};
  const select = $("workshop-preset");
  select.innerHTML = "";
  Object.keys(presets).forEach((key) => {
    const option = document.createElement("option");
    option.value = key;
    option.textContent = presets[key].label || key;
    select.appendChild(option);
  });
  const mesh = $("workshop-mesh");
  if (profile.mesh_provider) mesh.value = profile.mesh_provider;
  const first = presets[select.value];
  if (first && first.mesh_provider) mesh.value = first.mesh_provider;
  syncWorkshopConceptSource();
  if ($("workshop-prompt-preview")) $("workshop-prompt-preview").value = "";
}

function syncWorkshopConceptSource() {
  const source = ($("workshop-concept-source") && $("workshop-concept-source").value) || "openai";
  const uploadWrap = $("workshop-concept-upload-wrap");
  if (uploadWrap) uploadWrap.hidden = source !== "upload";
  const mesh = $("workshop-mesh");
  if (!mesh) return;
  if (source === "meshy_text") {
    mesh.value = "meshy_text";
  } else if (mesh.value === "meshy_text") {
    const profile = workshopLabels()[$("workshop-category").value] || {};
    mesh.value = profile.mesh_provider || "meshy";
  }
}

function workshopRequest(extra) {
  const workshopId = $("workshop-category").value;
  const profile = workshopLabels()[workshopId] || {};
  const source = ($("workshop-concept-source") && $("workshop-concept-source").value) || "openai";
  const edited = (($("workshop-prompt-preview") && $("workshop-prompt-preview").value) || "").trim();
  const notes = ($("workshop-prompt").value || "").trim();
  const payload = {
    workshop_category: workshopId,
    kind: profile.kind,
    category: $("workshop-preset").value,
    name: ($("workshop-name").value || "").trim(),
    mesh_provider: $("workshop-mesh").value || profile.mesh_provider || "meshy",
    variations: Number($("workshop-variations").value || 1),
    prompt: notes,
    quality: "medium",
    ...extra,
  };
  if (source === "meshy_text") {
    payload.mesh_provider = "meshy_text";
    payload.provider = "openai";
  } else if (source === "upload") {
    payload.provider = "manual";
  } else {
    payload.provider = "openai";
    if (edited) payload.prompt_override = edited;
  }
  return payload;
}

function renderQueue() {
  const list = $("queue-list");
  list.innerHTML = "";
  const summary = $("queue-summary");
  if (summary) {
    summary.textContent = state.jobs.length
      ? `${state.jobs.length} job${state.jobs.length === 1 ? "" : "s"} in the queue.`
      : "No jobs yet. Generate from Preview and stay on that tab while they run.";
  }
  if (!state.jobs.length) {
    const empty = document.createElement("li");
    empty.className = "muted";
    empty.textContent = "The queue is empty.";
    list.appendChild(empty);
    return;
  }
  state.jobs.forEach((job) => {
    const row = document.createElement("li");
    row.className = "queue-row";
    const request = job.request || {};
    const name = document.createElement("strong");
    name.textContent = request.name || job.job_id;
    const kind = document.createElement("span");
    kind.textContent = [request.kind || "job", request.category || ""].filter(Boolean).join(" · ");
    const status = document.createElement("span");
    status.className = job.status === "failed" ? "bad" : "ok";
    status.textContent = job.status;
    const message = document.createElement("span");
    message.className = "muted";
    message.textContent = (job.errors || []).join(" ") || job.message || "";
    const actions = document.createElement("span");
    actions.className = "queue-actions";
    const assetId = (job.asset_ids || [])[0];
    if (assetId && (job.status === "ready_for_review" || job.status === "approved")) {
      const open = document.createElement("button");
      open.type = "button";
      open.textContent = "Open";
      open.addEventListener("click", () => selectAsset(assetId));
      actions.appendChild(open);
    }
    if (job.status === "failed" || job.status === "ready_for_review") {
      const button = document.createElement("button");
      button.type = "button";
      button.textContent = "Retry";
      button.addEventListener("click", async () => {
        await api(`/api/jobs/${job.job_id}/retry`, { method: "POST" });
        await refresh();
      });
      actions.appendChild(button);
    }
    row.append(name, kind, status, message, actions);
    list.appendChild(row);
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

async function selectAsset(id, options) {
  const detail = await api(`/api/assets/${id}/detail`).catch(async () => ({ asset: await api(`/api/assets/${id}`), tasks: [], costs: [] }));
  state.detail = detail;
  state.selected = detail.asset;
  showTab("preview");
  const asset = state.selected;
  const icon = asset.category === "item_icon";
  $("preview-title").textContent = asset.asset_name;
  const workshopCategory = workshopOf(asset);
  const meshNote = asset.polygon_count ? `${asset.polygon_count} triangles` : asset.model || asset.provider;
  $("preview-meta").textContent = `${workshopCategory || asset.kind} · ${asset.category} · ${asset.provider} · ${meshNote}`;
  $("preview-status").textContent = reviewLabel(asset);
  $("preview-status").className = asset.processing_status === "failed" || asset.approval_status === "rejected" ? "bad" : "ok";
  const image = thumb(asset);
  $("preview-image").hidden = !image;
  if (image) $("preview-image").src = `${image}${image.includes("?") ? "&" : "?"}t=${Date.now()}`;
  resetImageRotation();
  syncRotateControls(Boolean(image) && asset.approval_status === "approved");
  const glb = (asset.processed_files || []).find((file) => file.endsWith(".glb") && !file.includes("lod"));
  state.mesh = null;
  $("preview-3d").hidden = !glb;
  $("tile-control").hidden = icon || !image || Boolean(glb);
  if ($("wireframe-control")) $("wireframe-control").hidden = !glb;
  if ($("ground-control")) $("ground-control").hidden = !glb;
  if ($("preview-metrics")) {
    const size = asset.dimensions && asset.dimensions.size;
    const sizeText = size ? ` · ${size.map((value) => Number(value).toFixed(2)).join("×")} m` : "";
    const tex = asset.texture_resolution ? ` · tex ${asset.texture_resolution}` : "";
    $("preview-metrics").textContent = glb
      ? `${asset.polygon_count || "?"} tris${sizeText}${tex} · orbit drag, scroll zoom`
      : "";
  }
  $("reprocess-label").hidden = asset.kind === "texture" || !glb;
  $("remove").disabled = asset.approval_status === "approved";
  $("preview-edit-image").disabled = asset.kind !== "texture" || !reviewImageFile(asset);
  if ($("preview-retry")) {
    $("preview-retry").hidden = !(asset.job_id && (asset.processing_status === "failed" || asset.approval_status === "rejected"));
  }
  if ($("preview-another")) {
    $("preview-another").hidden = !(asset.kind !== "texture" && asset.category);
  }
  renderAssetDetailLists(detail);
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
  const match = recordForName(asset.asset_name);
  if (match) {
    if (!state.iconEdit || state.iconEdit.id !== match.record.id) fillEditor(match.kind, match.record);
  } else if (!options || !options.keepPrompt) {
    state.iconEdit = null;
    state.copyKind = null;
    $("copy-ingame").value = "";
    $("copy-image").value = "";
    $("copy-ingame-hint").textContent = "";
    $("copy-image-hint").textContent = "";
  }
  if (!options || !options.keepPrompt) {
    $("preview-prompt").value = sent;
    state.promptTouched = true;
  }
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
        syncRotateControls(false);
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

function renderAssetDetailLists(detail) {
  const tasks = $("preview-tasks");
  const costs = $("preview-costs");
  if (!tasks || !costs) return;
  tasks.innerHTML = "";
  costs.innerHTML = "";
  (detail.tasks || []).forEach((task) => {
    const item = document.createElement("li");
    item.textContent = `${task.operation || "task"} · ${statusText(task.status)} · ${task.provider || ""} ${task.provider_task_id || ""}`.trim();
    tasks.appendChild(item);
  });
  if (!(detail.tasks || []).length) {
    const item = document.createElement("li");
    item.textContent = "No provider tasks recorded for this asset yet.";
    tasks.appendChild(item);
  }
  (detail.costs || []).forEach((cost) => {
    const item = document.createElement("li");
    const money = cost.actual_usd != null ? `$${Number(cost.actual_usd).toFixed(2)}` : (cost.estimated_usd != null ? `~$${Number(cost.estimated_usd).toFixed(2)}` : "cost unknown");
    item.textContent = `${cost.operation} · ${cost.provider} · ${cost.credits != null ? `${cost.credits} credits` : "credits n/a"} · ${money}`;
    costs.appendChild(item);
  });
  if (!(detail.costs || []).length) {
    const item = document.createElement("li");
    item.textContent = "No cost records yet.";
    costs.appendChild(item);
  }
}

function drawMesh() {
  const canvas = $("preview-3d");
  const context = canvas.getContext("2d");
  context.clearRect(0, 0, canvas.width, canvas.height);
  if (!state.mesh) return;
  const light = Number($("light").value);
  const wireframe = $("wireframe") && $("wireframe").checked;
  const ground = !$("ground-plane") || $("ground-plane").checked;
  const { positions, normals, indices } = state.mesh;
  const center = positions.reduce((acc, point) => [acc[0] + point[0], acc[1] + point[1], acc[2] + point[2]], [0, 0, 0]).map((value) => value / positions.length);
  const sy = Math.sin(state.yaw);
  const cy = Math.cos(state.yaw);
  const sp = Math.sin(state.pitch);
  const cp = Math.cos(state.pitch);
  const project = (point) => {
    let x = point[0] - center[0];
    let y = point[1] - center[1];
    let z = point[2] - center[2];
    const x1 = x * cy - z * sy;
    const z1 = x * sy + z * cy;
    const y1 = y * cp - z1 * sp;
    const z2 = y * sp + z1 * cp;
    const scale = 180 * state.zoom / (z2 + 4);
    return [canvas.width / 2 + x1 * scale, canvas.height / 2 - y1 * scale, z2];
  };
  if (ground) {
    const corners = [[-1, 0, -1], [1, 0, -1], [1, 0, 1], [-1, 0, 1]].map((point) => project(point.map((value, index) => center[index] + value)));
    context.beginPath();
    context.moveTo(corners[0][0], corners[0][1]);
    corners.slice(1).forEach((corner) => context.lineTo(corner[0], corner[1]));
    context.closePath();
    context.fillStyle = "rgba(53, 68, 81, 0.55)";
    context.fill();
  }
  const projected = positions.map((point, index) => {
    const [x, y, z] = project(point);
    let shade = light;
    if (normals && normals[index]) {
      const normal = normals[index];
      shade = light * (0.35 + 0.75 * Math.max(0, normal[0] * 0.4 + normal[1] * 0.8 + normal[2] * 0.4));
    }
    return [x, y, z, shade];
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
    if (wireframe) {
      context.strokeStyle = `rgb(${tone}, ${tone}, ${tone})`;
      context.stroke();
    } else {
      context.fillStyle = `rgb(${tone * 0.7}, ${tone * 0.75}, ${tone * 0.65})`;
      context.fill();
    }
  });
}

async function refresh() {
  const [assets, jobs] = await Promise.all([api("/api/assets"), api("/api/jobs")]);
  state.assets = assets.assets;
  state.jobs = jobs.jobs;
  $("status-line").textContent = describeStatus();
  renderLibrary();
  renderQueue();
  if (!$("production").hidden) refreshProduction().catch(() => {});
  if (!$("costs").hidden) refreshCosts().catch(() => {});
  if (state.itemSignature !== itemArtSignature()) {
    state.itemSignature = itemArtSignature();
    if (state.items) renderIcons();
    if (state.surfaces && !$("surfaces").hidden) loadSurfaces().catch(() => {});
    else if (state.surfaces) renderSurfaces();
    if (state.items) renderIngame();
  }
}

function describeStatus() {
  const active = state.jobs.filter((job) => ["waiting", "generating", "texturing", "rigging", "animating", "downloading", "processing", "validating"].includes(job.status));
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
    const haystack = `${item.display_name} ${item.id} ${item.description} ${item.image_description || ""} ${group}`.toLowerCase();
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
    const artSrc = (options.previewUrl && options.previewUrl(item))
      || (item.has_art && item.art_file && options.artUrl ? options.artUrl(item) : "");
    if (artSrc) {
      const picture = document.createElement("img");
      picture.className = "item-art";
      picture.alt = `${item.display_name} icon`;
      picture.src = artSrc;
      card.appendChild(picture);
    } else {
      card.appendChild(icon);
    }
    const title = document.createElement("h2");
    title.textContent = item.display_name;
    const meta = document.createElement("p");
    const group = options.group ? options.group(item) : item.category;
    meta.textContent = options.meta ? options.meta(item, group) : `${group} · ${item.id}`;
    const description = document.createElement("p");
    description.textContent = item.description;
    const badge = document.createElement("p");
    badge.className = item.has_art ? "badge ok" : "badge bad";
    badge.textContent = item.has_art ? options.readyLabel : options.missingLabel;
    const parts = [title, meta, description];
    if (options.detail) {
      const extra = document.createElement("p");
      extra.className = "muted";
      extra.textContent = options.detail(item);
      parts.push(extra);
    }
    parts.push(badge);
    card.append(...parts);
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
      if (options.upload && (!options.uploadWhen || options.uploadWhen(item))) {
        const upload = document.createElement("button");
        upload.type = "button";
        upload.textContent = item.has_art ? "Upload replace" : "Upload";
        upload.addEventListener("click", () => options.upload(item));
        row.append(upload);
      }
      card.appendChild(row);
    }
    grid.appendChild(card);
    if (!artSrc) options.draw(icon, item);
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
    queue: (item) => openCopy("item", item),
    upload: (item) => pickUploadFor("item", item),
    detail: (item) => item.image_description ? `Image: ${item.image_description}` : "Image: name only, until you write an image description.",
    buttonLabel: (item) => item.has_art ? "New icon" : "Make icon",
  });
}

function isFirearm(item) {
  const category = item.item_category || item.category || "";
  if (category === "weapon") return true;
  const blob = `${item.id || ""} ${item.display_name || ""} ${item.image_description || ""}`.toLowerCase().replaceAll("_", " ");
  return ["gun", "pistol", "rifle", "revolver", "shotgun", "firearm", "sidearm", "carbine", "blaster", "build tool"].some((word) => blob.includes(word));
}

function iconRequest(item, extra) {
  const visual = (item.image_description || "").trim();
  return {
    kind: "texture",
    category: "item_icon",
    name: item.id,
    prompt: visual
      ? `Inventory icon of one ${item.display_name}. ${visual}`
      : `Inventory icon of one ${item.display_name}.`,
    provider: "openai",
    icon_category: item.category,
    swatch: item.swatch,
    resolution: 512,
    variations: 1,
    quality: isFirearm(item) ? "high" : "medium",
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
    $("preview-hint").textContent = "A prompt can include at most 16 images.";
    return;
  }
  [...files].slice(0, room).forEach((file) => {
    if (!file.type.startsWith("image/")) return;
    state.iconDraft.push({ file, url: URL.createObjectURL(file) });
  });
  renderIconDraft();
}

function presetPrompt(surface) {
  const catalog = state.bootstrap && state.bootstrap.catalog;
  if (!catalog) return "";
  const section = surface.asset_kind === "prop" ? catalog.props : catalog.textures;
  const preset = section && section[surface.pipeline_category];
  return (preset && preset.prompt) || "";
}

function surfaceRequest(surface, extra) {
  const visual = (surface.image_description || "").trim();
  if (surface.asset_kind === "prop") {
    return {
      kind: "prop",
      category: surface.pipeline_category,
      name: surface.id,
      prompt: "",
      subject_override: visual,
      provider: "openai",
      mesh_provider: "meshy",
      polycount: Number(surface.polycount) || 4000,
      variations: 1,
      ...extra,
    };
  }
  return {
    kind: "texture",
    category: surface.pipeline_category,
    name: surface.id,
    prompt: "",
    subject_override: visual,
    provider: "openai",
    resolution: 512,
    variations: 1,
    quality: "medium",
    ...extra,
  };
}

function pickUploadFor(kind, record) {
  const picker = document.createElement("input");
  picker.type = "file";
  picker.accept = ".png,.jpg,.jpeg,.webp,image/png,image/jpeg,image/webp";
  picker.addEventListener("change", async () => {
    const file = picker.files && picker.files[0];
    if (!file) return;
    try {
      await queueManualUpload(kind, record, file);
    } catch (error) {
      $("status-line").textContent = error.message;
      if ($("preview-hint")) $("preview-hint").textContent = error.message;
    }
  });
  picker.click();
}

async function uploadImageFile(file) {
  const body = new FormData();
  body.append("file", file);
  const response = await fetch("/api/upload", { method: "POST", body });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(data.error || "The image was not uploaded.");
  return data.path;
}

async function queueManualUpload(kind, record, file) {
  if (!record) throw new Error("Choose a surface or icon first.");
  if (kind === "surface" && record.asset_kind === "prop") {
    throw new Error("Upload replace is for textures and icons. Props still need a mesh.");
  }
  const path = await uploadImageFile(file);
  const request = kind === "item"
    ? iconRequest(record, { provider: "manual", source_file: path })
    : surfaceRequest(record, { provider: "manual", source_file: path });
  delete request.quality;
  await openCopy(kind, record);
  if (record.has_art) $("confirm-overwrite").checked = true;
  $("preview-hint").textContent = `Uploading ${record.display_name}. Maps are derived from your albedo; Keep publishes it.`;
  $("status-line").textContent = `Uploading ${record.display_name}.`;
  await api("/api/jobs", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(request),
  });
  await refresh();
  $("preview-hint").textContent = record.has_art
    ? `${record.display_name} is processing. When ready, Keep with “Replace an approved file” checked.`
    : `${record.display_name} is processing. When ready, press Keep to publish it.`;
}

function recordForName(name) {
  const surface = (state.surfaces || []).find((item) => item.id === name);
  if (surface) return { kind: "surface", record: surface };
  const item = (state.items || []).find((entry) => entry.id === name);
  if (item) return { kind: "item", record: item };
  return null;
}

function fillEditor(kind, record) {
  state.iconEdit = record;
  state.copyKind = kind;
  $("preview-title").textContent = record.display_name;
  $("copy-ingame").value = record.description || "";
  $("copy-image").value = record.image_description || (kind === "surface" ? presetPrompt(record) : "");
  const mesh = (kind === "surface" && record.asset_kind === "prop") || kind === "ingame";
  $("copy-ingame-hint").textContent = kind === "item" || kind === "ingame"
    ? "Shown on the item in the game. The image model does not read this."
    : "Kept with this surface. The image model does not read this.";
  $("copy-image-hint").textContent = kind === "item"
    ? "What the object looks like. Leave this empty to send only the name."
    : kind === "ingame"
      ? "Optional mesh notes. Generate uses the inventory icon as the Meshy concept; Keep publishes the GLB."
      : mesh
        ? "What the 3D model should look like. Generate builds a mesh; the Preview tab shows it in 3D when ready."
        : "The material the image model paints for this wall or floor. Edit it, then generate. Clear it to go back to the category preset.";
  $("icon-prompt-ref-note").textContent = kind === "item"
    ? "Optional. The example is sent with the prompt. The icon still asks for a transparent background."
    : kind === "ingame"
      ? "The inventory icon is the concept. Extra example images are optional."
      : mesh
        ? "Optional. A concept picture is still made first, then turned into a GLB for the 3D preview."
        : "Optional. The example is sent with the prompt so the texture can follow it.";
}

function clearReviewPicture() {
  state.selected = null;
  state.mesh = null;
  $("preview-meta").textContent = "Write the prompt, then generate. The picture shows up here when one is ready.";
  $("preview-status").textContent = "";
  $("preview-image").hidden = true;
  $("preview-image").removeAttribute("src");
  $("preview-3d").hidden = true;
  $("preview-strip").innerHTML = "";
  $("preview-notes").innerHTML = "";
  $("preview-json").textContent = "";
  $("preview-edit").value = "";
  $("preview-edit-image").disabled = true;
  resetImageRotation();
  syncRotateControls(false);
}

function resetImageRotation() {
  state.imageRotation = 0;
  applyImageRotation();
}

function applyImageRotation() {
  const image = $("preview-image");
  if (image) image.style.transform = state.imageRotation ? `rotate(${state.imageRotation}deg)` : "";
  const save = $("preview-save-rotation");
  if (save) save.disabled = !state.imageRotation || !state.selected || state.selected.approval_status !== "approved";
  const label = $("preview-rotation-label");
  if (label) {
    label.textContent = state.imageRotation
      ? `${state.imageRotation}° clockwise — save to update the approved game files`
      : "";
  }
  if (!$("preview-3d").hidden && !state.mesh && Number($("tile-repeat").value) > 1) drawTiles();
}

function syncRotateControls(show) {
  const controls = $("preview-rotate-controls");
  if (!controls) return;
  controls.hidden = !show;
  if (!show) resetImageRotation();
  else applyImageRotation();
}

function requestForCopy(kind, record, extra) {
  if (kind === "item") return iconRequest(record, extra);
  if (kind === "ingame") return ingameRequest(record, extra);
  return surfaceRequest(record, extra);
}

async function openCopy(kind, record) {
  (state.iconDraft || []).forEach((entry) => URL.revokeObjectURL(entry.url));
  state.iconDraft = [];
  renderIconDraft();
  fillEditor(kind, record);
  state.promptTouched = false;
  $("preview-prompt").value = "";
  $("preview-hint").textContent = "Loading the prompt.";
  showTab("preview");
  const existing = chosenPicture(record.id);
  if (existing) await selectAsset(existing.asset_id, { keepPrompt: true });
  else clearReviewPicture();
  $("preview-title").textContent = record.display_name;
  try {
    if (kind === "ingame") {
      if (!record.has_icon && !record.art_file) {
        throw new Error("Make the inventory icon first. Ingame models start from that picture.");
      }
      const staged = await api("/api/items/stage-icon", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ id: record.id }),
      });
      record.concept_file = staged.path;
      state.iconEdit = record;
    }
    const preview = await api("/api/prompt-preview", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(requestForCopy(kind, record)),
    });
    if (state.iconEdit === record) {
      $("preview-prompt").value = preview.prompt || "";
      state.promptTouched = false;
      $("preview-hint").textContent = kind === "ingame"
        ? "Generate sends the inventory icon to Meshy. Meshy sizes the mesh to a real height, then it is fitted inside the footprint without stretching. World props are scaled to the size on the card."
        : "Generate uses this prompt and any example images. Edit image changes the picture shown here.";
    }
  } catch (error) {
    $("preview-hint").textContent = error.message;
  }
}

async function saveCopy() {
  const record = state.iconEdit;
  const kind = state.copyKind;
  if (!record || !kind) return null;
  const copyKind = kind === "ingame" ? "item" : kind;
  const data = await api("/api/copy", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      kind: copyKind,
      id: record.id,
      description: $("copy-ingame").value,
      image_description: $("copy-image").value,
    }),
  });
  const saved = copyKind === "item" ? data.item : data.surface;
  const list = copyKind === "item" ? state.items : state.surfaces;
  const index = (list || []).findIndex((item) => item.id === saved.id);
  if (index >= 0) list[index] = { ...list[index], ...saved };
  const merged = index >= 0 ? list[index] : saved;
  if (record.concept_file) merged.concept_file = record.concept_file;
  state.iconEdit = merged;
  $("copy-ingame").value = merged.description || "";
  $("copy-image").value = merged.image_description || "";
  if (kind === "item") renderIcons();
  else if (kind === "ingame") renderIngame();
  else renderSurfaces();
  return merged;
}

function sizeLabel(size) {
  if (!size || size.length !== 3) return "";
  return `${Number(size[0]).toFixed(2)}×${Number(size[1]).toFixed(2)}×${Number(size[2]).toFixed(2)} m`;
}

function footprintLabel(item) {
  if (item.category === "deployable") {
    if (item.mount === "opening") {
      return item.id.startsWith("window_") ? "Opening mount · window" : "Opening mount · door";
    }
    if (item.footprint && item.footprint[0] > 0) {
      return `Footprint ${item.footprint[0]}×${item.footprint[1]} · ${sizeLabel(item.target_size)}`;
    }
    return "Deployable · add footprint in deployable_dimensions.json";
  }
  if (item.category === "world_prop") {
    return `World prop · ${sizeLabel(item.target_size)}`;
  }
  return `World pickup · ${sizeLabel(item.target_size) || "0.38×0.28×0.38 m"}`;
}

function ingameRecords() {
  return (state.items || []).map((item) => {
    const deployable = item.category === "deployable";
    const worldProp = item.category === "world_prop";
    const ready = !!item.has_world_art;
    const base = item.description || "";
    return {
      ...item,
      description: ready
        ? base
        : (deployable
          ? `Placed object is still a colored box. ${base}`
          : (worldProp
            ? `World object is still built from primitive shapes. ${base}`
            : `World pickup is still a colored box. ${base}`)),
      category: deployable ? "deployable" : (worldProp ? "world prop" : "world pickup"),
      item_category: item.category,
      has_icon: !!item.has_art,
      icon_file: item.art_file || "",
      has_art: ready,
      needs_art: !ready,
      art_file: item.art_file || "",
    };
  });
}

function ingameRequest(item, extra) {
  const deployable = item.item_category === "deployable" || item.category === "deployable";
  const worldProp = item.item_category === "world_prop" || item.category === "world_prop";
  const visual = (item.image_description || "").trim();
  const subject = visual
    ? `${item.display_name}. ${visual}`
    : `${item.display_name}`;
  const payload = {
    workshop_category: deployable ? "deployables" : (worldProp ? "resources" : ""),
    kind: deployable ? "deployable" : (worldProp ? "resource" : "prop"),
    category: deployable || worldProp ? "from_icon" : "world_pickup",
    name: item.id,
    prompt: "",
    subject_override: subject,
    provider: "manual",
    mesh_provider: "meshy",
    polycount: deployable ? 6000 : (worldProp ? 8000 : 3000),
    variations: 1,
    target_size: item.target_size || undefined,
    ...extra,
  };
  if (item.concept_file) payload.source_file = item.concept_file;
  return payload;
}

function renderIngame() {
  if (!state.items) return;
  paintCards({
    records: ingameRecords(),
    gridId: "ingame-grid",
    searchId: "ingame-search",
    categoryId: "ingame-category",
    artId: "ingame-art",
    summaryId: "ingame-summary",
    summary: (total, missing) => {
      const ready = total - missing;
      const withIcon = (state.items || []).filter((item) => item.has_art).length;
      return `${total} world objects. ${ready} have a mesh. ${missing} are still a colored box. ${withIcon} already have an inventory icon for Meshy.`;
    },
    draw: drawItemIcon,
    readyLabel: "World art",
    missingLabel: "Needs a model",
    previewUrl: (item) => item.icon_file ? `/item-art/${item.icon_file}` : "",
    detail: (item) => footprintLabel(item),
    queue: (item) => openCopy("ingame", item),
    queueWhen: (item) => item.has_icon,
    buttonLabel: (item) => item.has_art ? "New model" : "Make model",
  });
}

function renderSurfaces() {
  if (!state.surfaces) return;
  const piece = $("surface-piece").value;
  const pieces = piece ? piece.split(" ") : null;
  const records = state.surfaces.filter((item) => !pieces || pieces.includes(item.category));
  const plants = records.some((item) => item.category === "vegetation");
  const onlyPlants = pieces && pieces.length === 1 && pieces[0] === "vegetation";
  paintCards({
    records,
    gridId: "surface-grid",
    searchId: "surface-search",
    categoryId: "surface-material",
    artId: "surface-art",
    summaryId: "surface-summary",
    group: (item) => item.material,
    summary: (total, missing) => onlyPlants
      ? `${total} trees, stones, and plants. ${missing} still need a mesh. Finished GLBs open in the 3D preview.`
      : `${total} surfaces in this view. ${missing} still need art. Forest/ground textures are 512 px; vegetation is a 3D mesh.`,

    meta: (item) => item.category === "vegetation"
      ? `${item.category} · ~${item.polycount || 0} tris · ${item.id}`
      : `${item.category} · roughness ${Number(item.roughness).toFixed(2)} · ${item.id}`,
    detail: (item) => item.image_description ? `Image: ${item.image_description}` : `Image preset: ${presetPrompt(item)}`,
    draw: drawSurface,
    readyLabel: plants && onlyPlants ? "Mesh" : "Texture",
    missingLabel: plants && onlyPlants ? "Needs a model" : "Flat color",
    artUrl: (item) => item.asset_kind === "prop" ? "" : `/texture-art/${item.id}/albedo.png`,
    queue: (item) => openCopy("surface", item),
    upload: (item) => pickUploadFor("surface", item),
    uploadWhen: (item) => item.asset_kind !== "prop",
    buttonLabel: (item) => item.asset_kind === "prop"
      ? (item.has_art ? "New model" : "Make model")
      : "New texture",
  });
}

function fillSelect(id, names, refresh = false) {
  const select = $(id);
  const selected = select.value;
  if (!refresh && select.options.length > 1) return;
  while (select.options.length > 1) select.remove(1);
  [...new Set(names)].sort().forEach((name) => {
    const option = document.createElement("option");
    option.value = name;
    option.textContent = name;
    select.appendChild(option);
  });
  if ([...select.options].some((option) => option.value === selected)) {
    select.value = selected;
  }
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
  const payload = await api("/api/items");
  state.items = payload.items;
  fillSelect("item-category", state.items.map((item) => item.category), true);
  fillSelect("ingame-category", ["world pickup", "deployable", "world prop"]);
  renderIngame();
}

async function loadSurfaces() {
  const payload = await api("/api/surfaces");
  state.surfaces = payload.surfaces;
  fillSelect("surface-material", state.surfaces.map((item) => item.material), true);
  renderSurfaces();
}


document.querySelectorAll("nav button").forEach((button) => {
  button.addEventListener("click", () => {
    showTab(button.dataset.tab);
    if (button.dataset.tab === "style") loadStyle().catch((error) => { $("style-note").textContent = error.message; });
    if (button.dataset.tab === "surfaces") loadSurfaces().catch((error) => { $("surface-summary").textContent = error.message; });
    if (button.dataset.tab === "icons") loadItems().catch((error) => { $("item-summary").textContent = error.message; });
    if (button.dataset.tab === "ingame") loadIngame().catch((error) => { $("ingame-summary").textContent = error.message; });
  });
});

$("item-search").addEventListener("input", renderIcons);
$("item-category").addEventListener("change", renderIcons);
$("item-art").addEventListener("change", renderIcons);
$("surface-search").addEventListener("input", renderSurfaces);
$("surface-piece").addEventListener("change", renderSurfaces);
$("surface-material").addEventListener("change", renderSurfaces);
$("surface-art").addEventListener("change", renderSurfaces);
$("ingame-search").addEventListener("input", renderIngame);
$("ingame-category").addEventListener("change", renderIngame);
$("ingame-art").addEventListener("change", renderIngame);
$("search").addEventListener("input", renderLibrary);
$("filter-workshop").addEventListener("change", renderLibrary);
$("filter-category").addEventListener("change", renderLibrary);
$("filter-provider").addEventListener("change", renderLibrary);
$("filter-status").addEventListener("change", renderLibrary);
$("filter-sort").addEventListener("change", renderLibrary);
$("workshop-category").addEventListener("change", fillWorkshopPresets);
$("workshop-preset").addEventListener("change", () => {
  const workshopId = $("workshop-category").value;
  const profile = workshopLabels()[workshopId] || {};
  const section = profile.catalog_section || workshopId;
  const preset = (((state.bootstrap && state.bootstrap.catalog) || {})[section] || {})[$("workshop-preset").value];
  if (preset && preset.mesh_provider) $("workshop-mesh").value = preset.mesh_provider;
  if ($("workshop-prompt-preview")) $("workshop-prompt-preview").value = "";
});
if ($("workshop-concept-source")) {
  $("workshop-concept-source").addEventListener("change", syncWorkshopConceptSource);
}
if ($("workshop-preview-prompt")) {
  $("workshop-preview-prompt").addEventListener("click", async () => {
    const note = $("workshop-note");
    try {
      const payload = workshopRequest();
      if (!payload.name) payload.name = "concept_preview";
      payload.provider = "openai";
      delete payload.prompt_override;
      delete payload.source_file;
      if (payload.mesh_provider === "meshy_text") payload.mesh_provider = "meshy";
      const preview = await api("/api/prompt-preview", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });
      $("workshop-prompt-preview").value = preview.prompt || "";
      note.textContent = "Prompt assembled with the same style system as icons and surfaces. Edit it before queueing if you want.";
    } catch (error) {
      note.textContent = error.message;
    }
  });
}
$("workshop-form").addEventListener("submit", async (event) => {
  event.preventDefault();
  const note = $("workshop-note");
  note.textContent = "Queueing…";
  try {
    const source = ($("workshop-concept-source") && $("workshop-concept-source").value) || "openai";
    const payload = workshopRequest();
    if (!payload.name) throw new Error("Enter an asset name.");
    if (source === "upload") {
      const concept = $("workshop-concept").files[0];
      if (!concept) throw new Error("Choose a concept image to upload, or switch concept source to OpenAI.");
      const body = new FormData();
      body.append("file", concept);
      const uploaded = await api("/api/upload", { method: "POST", body });
      payload.provider = "manual";
      payload.source_file = uploaded.path;
      delete payload.prompt_override;
    } else if (source === "openai") {
      payload.provider = "openai";
      if (!(($("workshop-prompt-preview") || {}).value || "").trim()) {
        const preview = await api("/api/prompt-preview", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ ...payload, name: payload.name || "concept_preview" }),
        });
        $("workshop-prompt-preview").value = preview.prompt || "";
        payload.prompt_override = preview.prompt || "";
      }
    }
    const job = await api("/api/jobs", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
    const conceptNote = source === "openai"
      ? "OpenAI concept first, then 3D."
      : (source === "upload" ? "Using uploaded concept." : "Meshy text-to-3D.");
    note.textContent = `Queued ${job.job_id}. ${conceptNote} Watch Queue / Preview.`;
    if ($("workshop-concept")) $("workshop-concept").value = "";
    await refresh();
    showTab("queue");
  } catch (error) {
    note.textContent = error.message;
  }
});
if ($("preview-retry")) {
  $("preview-retry").addEventListener("click", async () => {
    if (!state.selected || !state.selected.job_id) return;
    try {
      await api(`/api/jobs/${state.selected.job_id}/retry`, { method: "POST", headers: { "Content-Type": "application/json" }, body: "{}" });
      $("preview-hint").textContent = "Retry queued.";
      await refresh();
      showTab("queue");
    } catch (error) {
      $("preview-hint").textContent = error.message;
    }
  });
}
if ($("preview-another")) {
  $("preview-another").addEventListener("click", async () => {
    const asset = state.selected;
    if (!asset) return;
    const workshopId = workshopOf(asset) || "";
    const profile = workshopLabels()[workshopId] || {};
    const base = asset.asset_name.replace(/_\d+$/, "");
    const payload = {
      workshop_category: workshopId || undefined,
      kind: asset.kind,
      category: asset.category,
      name: `${base}_${String(Date.now()).slice(-4)}`,
      mesh_provider: asset.provider === "meshy" || asset.provider === "tripo" ? asset.provider : (profile.mesh_provider || "meshy"),
      variations: 1,
      prompt: asset.prompt || "",
    };
    try {
      const job = await api("/api/jobs", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });
      $("preview-hint").textContent = `Another version queued as ${job.request && job.request.name}.`;
      await refresh();
      showTab("queue");
    } catch (error) {
      $("preview-hint").textContent = error.message;
    }
  });
}
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
    const turn = ((state.imageRotation || 0) % 360) * Math.PI / 180;
    for (let y = 0; y < repeats; y += 1) {
      for (let x = 0; x < repeats; x += 1) {
        const cx = x * cellW + cellW / 2;
        const cy = y * cellH + cellH / 2;
        context.save();
        context.translate(cx, cy);
        context.rotate(turn);
        context.drawImage(image, -cellW / 2, -cellH / 2, cellW, cellH);
        context.restore();
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
if ($("wireframe")) $("wireframe").addEventListener("change", () => { if (state.mesh) drawMesh(); });
if ($("ground-plane")) $("ground-plane").addEventListener("change", () => { if (state.mesh) drawMesh(); });
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

$("preview").addEventListener("paste", (event) => {
  const files = clipboardImages(event.clipboardData);
  if (!files.length) return;
  event.preventDefault();
  addIconDraftFiles(files);
});

$("preview-prompt").addEventListener("input", () => {
  state.promptTouched = true;
});

$("copy-save").addEventListener("click", async () => {
  $("preview-hint").textContent = "Saving descriptions.";
  try {
    await saveCopy();
    $("preview-hint").textContent = "Descriptions saved.";
  } catch (error) {
    $("preview-hint").textContent = error.message;
  }
});

$("copy-rebuild").addEventListener("click", async () => {
  $("preview-hint").textContent = "Saving descriptions and rebuilding the prompt.";
  try {
    const saved = await saveCopy();
    if (!saved) return;
    const preview = await api("/api/prompt-preview", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(requestForCopy(state.copyKind, saved)),
    });
    $("preview-prompt").value = preview.prompt || "";
    state.promptTouched = false;
    $("preview-hint").textContent = "Prompt rebuilt from the saved descriptions.";
  } catch (error) {
    $("preview-hint").textContent = error.message;
  }
});

async function uploadDrafts() {
  const paths = [];
  for (const entry of state.iconDraft || []) {
    const body = new FormData();
    body.append("file", entry.file);
    const response = await fetch("/api/upload", { method: "POST", body });
    const data = await response.json().catch(() => ({}));
    if (!response.ok) throw new Error(data.error || "The example image was not uploaded.");
    paths.push(data.path);
  }
  return paths;
}

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

$("upload-albedo").addEventListener("change", async (event) => {
  const file = event.target.files && event.target.files[0];
  event.target.value = "";
  if (!file) return;
  const record = state.iconEdit;
  const kind = state.copyKind;
  if (!record || !kind) {
    $("preview-hint").textContent = "Open a surface or icon first, then upload an albedo.";
    return;
  }
  try {
    await queueManualUpload(kind, record, file);
  } catch (error) {
    $("preview-hint").textContent = error.message;
  }
});

$("preview-generate").addEventListener("click", async () => {
  const prompt = $("preview-prompt").value.trim();
  const record = state.iconEdit;
  if (!prompt) {
    $("preview-hint").textContent = "Write a prompt first.";
    return;
  }
  if (!record && !state.selected) {
    $("preview-hint").textContent = "Choose a surface, an icon, or a picture first.";
    return;
  }
  const button = $("preview-generate");
  button.disabled = true;
  const name = (record && record.display_name) || (state.selected && state.selected.asset_name) || "image";
  $("preview-hint").textContent = state.iconDraft && state.iconDraft.length
    ? `Generating ${name} from the example.`
    : `Generating ${name}.`;
  try {
    const paths = await uploadDrafts();
    if (record && state.copyKind) {
      const saved = await saveCopy();
      const active = saved || record;
      if (state.copyKind === "ingame" && !active.concept_file) {
        const staged = await api("/api/items/stage-icon", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ id: active.id }),
        });
        active.concept_file = staged.path;
      }
      let sent = prompt;
      if (!state.promptTouched) {
        const preview = await api("/api/prompt-preview", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(requestForCopy(state.copyKind, active)),
        });
        sent = (preview.prompt || prompt).trim();
      }
      const request = requestForCopy(state.copyKind, active);
      const body = { ...request, reference_images: paths };
      if (state.copyKind !== "ingame" || state.promptTouched) body.prompt_override = sent;
      else if (sent) body.subject_override = (active.image_description || active.display_name || sent).trim();
      await api("/api/jobs", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      });
    } else {
      await queueReviewed(prompt, paths);
    }
    $("status-line").textContent = `Generating ${name}.`;
    $("preview-hint").textContent = `Generating ${name}. It stays in the queue while you keep working here.`;
    await refresh();
  } catch (error) {
    $("preview-hint").textContent = error.message;
  } finally {
    button.disabled = false;
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
    $("preview-hint").textContent = `Editing ${asset.asset_name}. It stays in the queue while you keep working here.`;
    await refresh();
  } catch (error) {
    $("preview-hint").textContent = error.message;
  } finally {
    button.disabled = false;
  }
});

if ($("preview-rotate")) {
  $("preview-rotate").addEventListener("click", () => {
    if (!state.selected || $("preview-image").hidden) return;
    if (state.selected.approval_status !== "approved") {
      $("preview-hint").textContent = "Only approved images can be rotated. Keep the picture first.";
      return;
    }
    state.imageRotation = (state.imageRotation + 90) % 360;
    applyImageRotation();
  });
}

if ($("preview-save-rotation")) {
  $("preview-save-rotation").addEventListener("click", async () => {
    const asset = state.selected;
    const degrees = state.imageRotation;
    if (!asset || !degrees) return;
    if (asset.approval_status !== "approved") {
      $("preview-hint").textContent = "Only approved images can be rotated. Keep the picture first.";
      return;
    }
    const button = $("preview-save-rotation");
    const rotateButton = $("preview-rotate");
    button.disabled = true;
    if (rotateButton) rotateButton.disabled = true;
    try {
      await api(`/api/assets/${asset.asset_id}/rotate`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ degrees }),
      });
      $("preview-hint").textContent = `Saved ${degrees}° rotation for ${asset.asset_name} and updated the game files.`;
      $("status-line").textContent = `Rotated ${asset.asset_name} by ${degrees}°.`;
      await selectAsset(asset.asset_id, { keepPrompt: true });
      await refresh();
    } catch (error) {
      $("preview-hint").textContent = error.message;
      applyImageRotation();
    } finally {
      if (rotateButton) rotateButton.disabled = false;
    }
  });
}

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
  state.production = bootstrap.production || null;
  state.costs = bootstrap.costs || null;
  fillWorkshopForm();
  renderProduction();
  renderCosts();
  return refresh();
}).then(() => {
  if (!$("production").hidden) return refreshProduction();
  if (!$("costs").hidden) return refreshCosts();
  return loadSurfaces();
}).catch((error) => {
  $("status-line").textContent = error.message;
});
setInterval(() => { refresh().catch(() => {}); }, 2000);
