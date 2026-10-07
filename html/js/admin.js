// admin.js: the ef_bridge admin panel (/efbridge).
//
// Renders the settings the server sends (schema + values), collects
// changes and sends them back. The server checks the ACE and every value
// again, this page only makes editing comfortable. Values from the server
// go in as text (textContent, value), never as HTML.

(function () {
  const STATUS_GROUP = "Status";
  const IMPORT_GROUP = "Import";

  let schema = [];
  let state = {};
  let status = {};
  let current = STATUS_GROUP;
  let changes = {};
  let resets = new Set();
  let errors = {};
  let importText = "";
  let importResult = null;

  const $ = (id) => document.getElementById(id);

  function el(tag, attrs, ...children) {
    const node = document.createElement(tag);
    for (const [k, v] of Object.entries(attrs || {})) {
      if (v === false || v === null || v === undefined) continue;
      if (k === "class") node.className = v;
      else if (k === "text") node.textContent = v;
      else if (k.startsWith("on")) node.addEventListener(k.slice(2), v);
      else node.setAttribute(k, v === true ? "" : v);
    }
    for (const child of children) {
      if (child === null || child === undefined || child === false) continue;
      node.append(child instanceof Node ? child : document.createTextNode(child));
    }
    return node;
  }

  function post(name, body) {
    return fetch(`https://${GetParentResourceName()}/${name}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body || {}),
    }).catch(() => {});
  }

  function groups() {
    const list = [STATUS_GROUP];
    for (const entry of schema) {
      if (!list.includes(entry.group)) list.push(entry.group);
    }
    list.push(IMPORT_GROUP);
    return list;
  }

  function pending() {
    return Object.keys(changes).length + resets.size;
  }

  // what the field shows: a pending change, else the live value
  function shown(entry) {
    if (Object.prototype.hasOwnProperty.call(changes, entry.key)) return changes[entry.key];
    const s = state[entry.key] || {};
    if (resets.has(entry.key)) return s.default;
    return s.value;
  }

  function same(a, b) {
    return JSON.stringify(a) === JSON.stringify(b);
  }

  function setValue(entry, value) {
    const s = state[entry.key] || {};
    resets.delete(entry.key);
    delete errors[entry.key];
    if (same(value, s.value)) delete changes[entry.key];
    else changes[entry.key] = value;
    renderFooter();
    renderNav();
  }

  // ==========================================
  // FIELDS
  // ==========================================

  function control(entry) {
    const value = shown(entry);
    const id = "efb-" + entry.key.replace(/\W/g, "-");

    if (entry.type === "boolean") {
      const input = el("input", { type: "checkbox", id, class: "efb-switch__input" });
      input.checked = value === true;
      input.addEventListener("change", () => setValue(entry, input.checked));
      return { id, node: el("label", { class: "efb-switch", for: id }, input, el("span", { class: "efb-switch__track", "aria-hidden": "true" })) };
    }

    if (entry.type === "select") {
      const select = el("select", { id, class: "efb-input" });
      for (const option of entry.options || []) {
        const o = el("option", { value: option, text: option });
        if (option === value) o.selected = true;
        select.append(o);
      }
      select.addEventListener("change", () => setValue(entry, select.value));
      return { id, node: select };
    }

    if (entry.type === "list") {
      const area = el("textarea", { id, class: "efb-input efb-input--list", rows: 3, spellcheck: "false" });
      area.value = Array.isArray(value) ? value.join("\n") : "";
      area.addEventListener("input", () => {
        const items = area.value.split(/\r?\n|,/).map((s) => s.trim()).filter(Boolean);
        setValue(entry, items);
      });
      return { id, node: area };
    }

    if (entry.type === "number" || entry.type === "float") {
      const input = el("input", { id, type: "number", class: "efb-input efb-input--number", step: entry.type === "float" ? "any" : 1, min: entry.min === false ? null : entry.min, max: entry.max === false ? null : entry.max });
      input.value = value === false || value === undefined || value === null ? "" : String(value);
      input.addEventListener("input", () => setValue(entry, input.value === "" ? null : Number(input.value)));
      return { id, node: input };
    }

    if (entry.type === "secret") {
      // never filled: the server only says whether a key is set
      const isSet = (state[entry.key] || {}).value === true;
      const input = el("input", { id, type: "password", class: "efb-input", spellcheck: "false", autocomplete: "new-password", placeholder: isSet ? "gesetzt – zum Ändern neuen Schlüssel eingeben" : "noch kein Schlüssel" });
      if (typeof changes[entry.key] === "string") input.value = changes[entry.key];
      input.addEventListener("input", () => {
        delete errors[entry.key];
        resets.delete(entry.key);
        if (input.value.trim() === "") delete changes[entry.key];
        else changes[entry.key] = input.value.trim();
        renderFooter();
        renderNav();
      });
      return { id, node: input };
    }

    const input = el("input", { id, type: "text", class: "efb-input", spellcheck: "false", autocomplete: "off", placeholder: entry.type === "url" ? "https://" : null });
    input.value = typeof value === "string" ? value : "";
    input.addEventListener("input", () => setValue(entry, entry.optional && input.value.trim() === "" ? false : input.value));
    return { id, node: input };
  }

  function field(entry) {
    const s = state[entry.key] || {};
    const { id, node } = control(entry);
    const tags = el("span", { class: "efb-field__tags" });

    if (entry.type === "secret") {
      tags.append(el("span", { class: "efb-chip " + (s.value ? "efb-chip--ok" : "efb-chip--off"), text: resets.has(entry.key) ? "wird gelöscht" : s.value ? "gesetzt" : "nicht gesetzt" }));
    }
    if (entry.restart) tags.append(el("span", { class: "efb-tag efb-tag--warn", text: "nach Neustart" }));
    if (entry.scope === "server") tags.append(el("span", { class: "efb-tag", text: "nur Server" }));
    if (Object.prototype.hasOwnProperty.call(changes, entry.key) || resets.has(entry.key)) {
      tags.append(el("span", { class: "efb-tag efb-tag--pending", text: "ungespeichert" }));
    } else if (s.changed) {
      tags.append(
        el("button", {
          type: "button",
          class: "efb-link",
          text: entry.type === "secret" ? "Schlüssel löschen" : "Auf Standard zurücksetzen",
          onclick: () => {
            delete changes[entry.key];
            resets.add(entry.key);
            renderContent();
            renderFooter();
          },
        }),
      );
    }

    return el(
      "div",
      { class: "efb-field" + (errors[entry.key] ? " efb-field--error" : "") },
      el("div", { class: "efb-field__head" }, el("label", { class: "efb-field__label", for: id, text: entry.label }), tags),
      node,
      entry.help ? el("p", { class: "efb-field__help", text: entry.help }) : null,
      s.changed && !resets.has(entry.key) && entry.type !== "secret" ? el("p", { class: "efb-field__help", text: "Standard: " + describe(entry, s.default) }) : null,
      errors[entry.key] ? el("p", { class: "efb-field__error", role: "alert", text: errors[entry.key] }) : null,
    );
  }

  function describe(entry, value) {
    if (entry.type === "boolean") return value === true ? "an" : "aus";
    if (value === false || value === null || value === undefined || value === "") return "leer";
    if (Array.isArray(value)) return value.length ? value.join(", ") : "leer";
    return String(value);
  }

  // ==========================================
  // STATUS
  // ==========================================

  // off: a switched-off module is no error, so it gets a grey chip
  function chip(ok, yes, no, off) {
    const tone = ok ? "efb-chip--ok" : off ? "efb-chip--off" : "efb-chip--bad";
    return el("span", { class: "efb-chip " + tone, text: ok ? yes : no });
  }

  function action(name, label) {
    return el("button", {
      type: "button",
      class: "efb-btn efb-btn--secondary",
      text: label,
      onclick: (e) => {
        e.currentTarget.disabled = true;
        post("adminAction", { action: name });
      },
      "data-action": name,
    });
  }

  function row(label, value) {
    return el("div", { class: "efb-status__row" }, el("span", { class: "efb-status__label", text: label }), el("span", { class: "efb-status__value" }, value));
  }

  function statusView() {
    const lex = status.lex || {};
    const last = lex.last;
    const view = el("div", { class: "efb-status" });

    view.append(
      el(
        "section",
        { class: "efb-card" },
        el("h3", { text: "Allgemein" }),
        row("Version", status.version || "?"),
        row("Ressource", status.resource || "?"),
        row("Framework", status.framework ? chip(true, status.framework, "") : chip(false, "", "keins gefunden")),
        row("Datenbank", chip(status.database, "verbunden", "keine (oxmysql)")),
      ),
      el(
        "section",
        { class: "efb-card" },
        el("h3", { text: "ignis" }),
        row("API-Schlüssel", chip(status.ignisKeySet, "gesetzt", "fehlt (unter ignis eintragen)")),
        row("EMD-Sync", chip(status.emd, "an", "aus", true)),
        row("eNOTF-Abrechnung", chip(status.billing, "an", "aus", true)),
        el("div", { class: "efb-card__actions" }, action("testIgnis", "Verbindung testen"), status.emd ? action("emdSync", "EMD jetzt abgleichen") : null),
      ),
      el(
        "section",
        { class: "efb-card" },
        el("h3", { text: "Lex" }),
        row("Abgleich", chip(lex.enabled, "an", "aus", true)),
        row("API-Schlüssel", chip(lex.keySet, "gesetzt", "fehlt (unter Lex eintragen)")),
        row("Letzter vollständiger Abgleich", lex.running ? "läuft gerade …" : last ? `${last.at} (${last.seconds} s)` : "noch keiner"),
        last ? row("Personen", `${last.persons.seen} gesehen, ${last.persons.created} neu, ${last.persons.updated} geändert, ${last.persons.skipped} übersprungen`) : null,
        last ? row("Fahrzeuge", `${last.vehicles.seen} gesehen, ${last.vehicles.created} neu, ${last.vehicles.updated} geändert, ${last.retired} abgemeldet`) : null,
        lex.lastLive ? row("Zuletzt beim Einloggen", `${lex.lastLive.at}, ${lex.lastLive.characters} Charakter(e)`) : null,
        lex.lastError ? el("p", { class: "efb-field__error", text: `${lex.lastError.at}: ${lex.lastError.message}` }) : null,
        el("div", { class: "efb-card__actions" }, action("testLex", "Verbindung testen"), lex.enabled && lex.keySet ? action("lexSync", "Jetzt vollständig abgleichen") : null),
      ),
      el("p", { class: "efb-hint", text: "Alle Einstellungen liegen auf dem Server, config-Dateien gibt es nicht mehr. Änderungen gelten sofort, außer bei Einträgen mit „nach Neustart“ (restart ef_bridge). API-Schlüssel lassen sich setzen und löschen, aber nicht mehr anzeigen." }),
    );
    return view;
  }

  // ==========================================
  // RENDER
  // ==========================================

  function renderNav() {
    const nav = $("efbNav");
    nav.replaceChildren();
    for (const group of groups()) {
      const dirty = schema.some((e) => e.group === group && (Object.prototype.hasOwnProperty.call(changes, e.key) || resets.has(e.key)));
      const bad = schema.some((e) => e.group === group && errors[e.key]);
      nav.append(
        el(
          "button",
          {
            type: "button",
            class: "efb-nav__item" + (group === current ? " is-active" : ""),
            "aria-current": group === current ? "page" : null,
            onclick: () => {
              current = group;
              renderNav();
              renderContent();
            },
          },
          group,
          bad ? el("span", { class: "efb-dot efb-dot--bad", "aria-label": "Fehler" }) : dirty ? el("span", { class: "efb-dot", "aria-label": "ungespeichert" }) : null,
        ),
      );
    }
  }

  function renderContent() {
    const content = $("efbContent");
    content.replaceChildren(el("h2", { class: "efb-content__title", text: current }));
    if (current === STATUS_GROUP) {
      content.append(statusView());
      return;
    }
    if (current === IMPORT_GROUP) {
      content.append(importView());
      return;
    }
    const entries = schema.filter((e) => e.group === current);
    for (const entry of entries.filter((e) => !e.advanced)) {
      content.append(field(entry));
    }
    const advanced = entries.filter((e) => e.advanced);
    if (advanced.length) {
      const box = el("details", { class: "efb-advanced" }, el("summary", { text: "Erweitert" }));
      if (advanced.some((e) => errors[e.key] || Object.prototype.hasOwnProperty.call(changes, e.key))) box.open = true;
      for (const entry of advanced) box.append(field(entry));
      content.append(box);
    }
  }

  // ==========================================
  // IMPORT
  // ==========================================

  function importView() {
    const view = el("div", { class: "efb-import" });
    const area = el("textarea", { class: "efb-input efb-input--list efb-import__text", rows: 10, spellcheck: "false", placeholder: "Inhalt einer config.lua, config_server.lua oder settings-export.json hier einfügen" });
    area.value = importText;
    area.addEventListener("input", () => {
      importText = area.value;
      importResult = null;
    });

    const send = (apply, fromFolder) => {
      post("adminImport", { text: fromFolder ? "" : importText, apply });
    };

    view.append(
      el("p", { class: "efb-field__help", text: "Übernimmt Einstellungen aus alten config-Dateien von ignisTab oder ef_bridge und aus Exporten (efbridge export). Erst kommt eine Vorschau, übernommen wird erst nach „Übernehmen“. Liegen die Dateien im Ordner der Ressource, liest „Aus dem Ordner lesen“ sie direkt." }),
      area,
      el(
        "div",
        { class: "efb-card__actions" },
        el("button", { type: "button", class: "efb-btn efb-btn--secondary", text: "Vorschau", onclick: () => send(false, false) }),
        el("button", { type: "button", class: "efb-btn efb-btn--ghost", text: "Aus dem Ordner lesen", onclick: () => { importText = ""; send(false, true); } }),
      ),
    );

    const r = importResult;
    if (!r) return view;

    if (r.found === 0) {
      view.append(el("p", { class: "efb-field__error", text: "Nichts gefunden: weder eingefügter Text noch config-Dateien im Ordner." }));
      return view;
    }
    for (const problem of r.problems || []) view.append(el("p", { class: "efb-field__error", text: problem }));
    for (const note of r.notes || []) view.append(el("p", { class: "efb-field__help", text: "Altes Format: " + note }));

    if ((r.applied || []).length) {
      view.append(el("p", { class: "efb-import__done", text: `${r.applied.length} Einstellung(en) übernommen.` + (r.restart ? " Einiges davon gilt nach restart ef_bridge." : "") }));
    } else if ((r.preview || []).length) {
      const table = el("table", { class: "efb-import__table" }, el("thead", {}, el("tr", {}, el("th", { text: "Einstellung" }), el("th", { text: "jetzt" }), el("th", { text: "danach" }))));
      const body = el("tbody");
      for (const item of r.preview) {
        body.append(el("tr", {}, el("td", {}, el("span", { text: `${item.group} › ${item.label}` })), el("td", { text: item.from }), el("td", { text: item.to })));
      }
      table.append(body);
      view.append(table, el("div", { class: "efb-card__actions" }, el("button", { type: "button", class: "efb-btn efb-btn--primary", text: `${r.preview.length} übernehmen`, onclick: () => send(true, importText === "") })));
    } else {
      view.append(el("p", { class: "efb-field__help", text: "Alles schon so eingestellt, es gibt nichts zu übernehmen." }));
    }
    for (const err of r.errors || []) view.append(el("p", { class: "efb-field__error", text: `${err.label}: ${err.message}` }));
    return view;
  }

  function imported(data) {
    importResult = data;
    if (data.state) state = data.state;
    if (data.status) status = data.status;
    if ((data.applied || []).length) toast("Import übernommen.", true);
    current = IMPORT_GROUP;
    render();
  }

  function renderFooter() {
    const n = pending();
    $("efbPending").textContent = n === 0 ? "Keine ungespeicherten Änderungen" : n === 1 ? "1 ungespeicherte Änderung" : `${n} ungespeicherte Änderungen`;
    $("efbSave").disabled = n === 0;
    $("efbDiscard").disabled = n === 0;
  }

  function render() {
    renderNav();
    renderContent();
    renderFooter();
  }

  function toast(message, ok) {
    const box = $("efbToast");
    box.textContent = message;
    box.className = "efb-toast " + (ok ? "efb-toast--ok" : "efb-toast--bad");
    box.hidden = false;
    clearTimeout(toast.timer);
    toast.timer = setTimeout(() => (box.hidden = true), 6000);
  }

  // ==========================================
  // OPEN / SAVE / CLOSE
  // ==========================================

  function open(data) {
    schema = Array.isArray(data.schema) ? data.schema : [];
    state = data.state || {};
    status = data.status || {};
    changes = {};
    resets = new Set();
    errors = {};
    if (!groups().includes(current)) current = STATUS_GROUP;
    $("efbVersion").textContent = status.version ? "Version " + status.version : "";
    $("adminPanel").hidden = false;
    render();
  }

  function close() {
    if (pending() > 0 && !window.confirm("Ungespeicherte Änderungen verwerfen?")) return;
    $("adminPanel").hidden = true;
    post("adminClose");
  }

  function save() {
    if (pending() === 0) return;
    $("efbSave").disabled = true;
    post("adminSave", { changes, resets: Array.from(resets) });
  }

  function saved(data) {
    state = data.state || state;
    status = data.status || status;
    errors = data.errors || {};
    for (const key of data.applied || []) {
      delete changes[key];
      resets.delete(key);
    }
    const failed = Object.keys(errors).length;
    if (failed > 0) {
      toast(failed === 1 ? "Eine Einstellung wurde nicht übernommen, siehe Markierung." : `${failed} Einstellungen wurden nicht übernommen, siehe Markierung.`, false);
      const firstBad = schema.find((e) => errors[e.key]);
      if (firstBad) current = firstBad.group;
    } else if (data.restart) {
      toast("Gespeichert. Einiges davon gilt erst nach restart ef_bridge.", true);
    } else {
      toast("Gespeichert, gilt ab sofort.", true);
    }
    render();
  }

  function result(data) {
    status = data.status || status;
    toast(data.message || (data.ok ? "Erledigt." : "Fehlgeschlagen."), data.ok);
    if (current === STATUS_GROUP) renderContent();
  }

  function init() {
    if (!$("adminPanel")) return;
    $("efbClose").addEventListener("click", close);
    $("efbSave").addEventListener("click", save);
    $("efbDiscard").addEventListener("click", () => {
      changes = {};
      resets = new Set();
      errors = {};
      render();
    });
    $("efbRefresh").addEventListener("click", () => {
      if (pending() > 0 && !window.confirm("Ungespeicherte Änderungen verwerfen und neu laden?")) return;
      post("adminRefresh");
    });
    document.addEventListener("keydown", (e) => {
      if (e.key === "Escape" && !$("adminPanel").hidden) close();
    });
  }

  window.addEventListener("message", (event) => {
    const msg = event.data;
    if (!msg || typeof msg.type !== "string" || !msg.type.startsWith("admin")) return;
    // the tablet frames may post messages too, only the game client counts
    if (typeof fromTabletFrame === "function" && fromTabletFrame(event)) return;

    if (msg.type === "adminOpen") open(msg.data || {});
    else if (msg.type === "adminSaved") saved(msg.data || {});
    else if (msg.type === "adminResult") result(msg.data || {});
    else if (msg.type === "adminImported") imported(msg.data || {});
    else if (msg.type === "adminClose") $("adminPanel").hidden = true;
  });

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", init);
  else init();
})();
