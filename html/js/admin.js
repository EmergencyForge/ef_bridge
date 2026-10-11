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

  // Short text and icon per section. Groups the server adds later still
  // work, they just show the plain dot.
  const GROUP_INFO = {
    Status: { icon: "pulse", text: "Verbindungen, Abgleiche und Version auf einen Blick." },
    Allgemein: { icon: "sliders", text: "Framework, Konsolenausgaben und die Animation mit dem Tablet." },
    ignis: { icon: "ignis", text: "Adresse, API-Schlüssel und Anmeldung über ignis." },
    "eNOTF-Tablet": { icon: "tablet", text: "Freischaltung, Berechtigungen, Befehl, Taste und das Modell in der Hand." },
    FireTab: { icon: "tabletWide", text: "Freischaltung, Berechtigungen, Befehl, Taste und das Modell in der Hand." },
    "EMD-Sync": { icon: "sync", text: "Gleicht Einsatzdaten, Status und Lagemeldungen von emergencydispatch mit ignis ab." },
    "eNOTF-Abrechnung": { icon: "receipt", text: "Holt freigegebene eNOTF-Protokolle aus ignis, damit der Server Patienten abrechnen kann." },
    Lex: { icon: "scale", text: "Überträgt Charaktere als Personen und ihre Fahrzeuge nach Lex." },
    Import: { icon: "import", text: "Übernimmt Einstellungen aus alten config-Dateien und Exporten." },
  };

  const ICONS = {
    dot: '<circle cx="12" cy="12" r="3"/>',
    pulse: '<path d="M3 12h4l2.5-6 5 12 2.5-6H21"/>',
    sliders: '<path d="M4 6h9M17 6h3M4 12h3M11 12h9M4 18h11M19 18h1"/><circle cx="15" cy="6" r="2"/><circle cx="9" cy="12" r="2"/><circle cx="17" cy="18" r="2"/>',
    tablet: '<rect x="5" y="2.5" width="14" height="19" rx="2.5"/><path d="M11 18h2"/>',
    tabletWide: '<rect x="2.5" y="5" width="19" height="14" rx="2.5"/><path d="M18 11v2"/>',
    sync: '<path d="M20 11a8 8 0 0 0-14.2-4.6L4 8"/><path d="M4 4v4h4"/><path d="M4 13a8 8 0 0 0 14.2 4.6L20 16"/><path d="M20 20v-4h-4"/>',
    receipt: '<path d="M6 3h12v18l-3-2-3 2-3-2-3 2z"/><path d="M9 8h6M9 12h6M9 16h3"/>',
    scale: '<path d="M12 4v16M8 20h8M5 7h14"/><path d="M5 7l-3 7a3 3 0 0 0 6 0z"/><path d="M19 7l-3 7a3 3 0 0 0 6 0z"/>',
    import: '<path d="M12 3v12M7 10l5 5 5-5"/><path d="M4 17v2a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-2"/>',
    server: '<rect x="3" y="4" width="18" height="7" rx="2"/><rect x="3" y="13" width="18" height="7" rx="2"/><path d="M7 7.5h.01M7 16.5h.01"/>',
    close: '<path d="M6 6l12 12M18 6L6 18"/>',
    refresh: '<path d="M20 12a8 8 0 1 1-2.34-5.66L20 8"/><path d="M20 3v5h-5"/>',
    check: '<circle cx="12" cy="12" r="9"/><path d="M8 12.5l2.7 2.7L16 9.8"/>',
    alert: '<circle cx="12" cy="12" r="9"/><path d="M12 7.5v5.5M12 16.5v.01"/>',
    info: '<circle cx="12" cy="12" r="9"/><path d="M12 11v5.5M12 7.5v.01"/>',
  };
  // the mark from ignis assets/img/ignis-mark.svg
  const IGNIS_MARK = "M24 0H96V72L72 96H0V24ZM36 80H52V44L36 60ZM40 24L50 34L60 24L50 14Z";

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

  // Only fixed markup from ICONS goes through innerHTML here, never
  // anything the server sent.
  function icon(name, extra) {
    const span = el("span", { class: (name === "ignis" ? "efb-icon efb-icon--fill" : "efb-icon") + (extra ? " " + extra : ""), "aria-hidden": "true" });
    span.innerHTML =
      name === "ignis"
        ? `<svg viewBox="0 0 96 96" fill="currentColor"><path fill-rule="evenodd" d="${IGNIS_MARK}"/></svg>`
        : `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round">${ICONS[name] || ICONS.dot}</svg>`;
    return span;
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
      const label = el("span", { class: "efb-switch__state", text: input.checked ? "An" : "Aus" });
      input.addEventListener("change", () => {
        label.textContent = input.checked ? "An" : "Aus";
        setValue(entry, input.checked);
      });
      return { id, node: el("label", { class: "efb-switch", for: id }, input, el("span", { class: "efb-switch__track", "aria-hidden": "true" }), label) };
    }

    if (entry.type === "select") {
      const select = el("select", { id, class: "efb-input" });
      for (const option of entry.options || []) {
        const o = el("option", { value: option, text: (entry.labels && entry.labels[option]) || option });
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
      const input = el("input", { id, type: "password", class: "efb-input", spellcheck: "false", autocomplete: "new-password", placeholder: isSet ? "gesetzt, zum Ändern neuen Schlüssel eingeben" : "noch kein Schlüssel" });
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
      tags.append(el("span", { class: "efb-chip efb-chip--dot" + (s.value ? " efb-chip--ok" : ""), text: resets.has(entry.key) ? "wird gelöscht" : s.value ? "gesetzt" : "nicht gesetzt" }));
    }
    if (entry.restart) tags.append(el("span", { class: "efb-chip efb-chip--warn", text: "nach Neustart" }));
    if (entry.scope === "server") tags.append(el("span", { class: "efb-chip efb-chip--category", text: "nur Server" }));
    if (Object.prototype.hasOwnProperty.call(changes, entry.key) || resets.has(entry.key)) {
      tags.append(el("span", { class: "efb-chip efb-chip--primary", text: "ungespeichert" }));
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
      el(
        "div",
        { class: "efb-field__meta" },
        el("div", { class: "efb-field__head" }, el("label", { class: "efb-field__label", for: id, text: entry.label }), tags),
        entry.help ? el("p", { class: "efb-field__help", text: entry.help }) : null,
        s.changed && !resets.has(entry.key) && entry.type !== "secret" ? el("p", { class: "efb-field__help", text: "Standard: " + describe(entry, s.default) }) : null,
      ),
      el(
        "div",
        { class: "efb-field__control" },
        node,
        errors[entry.key] ? el("p", { class: "efb-field__error", role: "alert" }, icon("alert"), el("span", { text: errors[entry.key] })) : null,
      ),
    );
  }

  function describe(entry, value) {
    if (entry.type === "boolean") return value === true ? "an" : "aus";
    if (value === false || value === null || value === undefined || value === "") return "leer";
    if (Array.isArray(value)) return value.length ? value.join(", ") : "leer";
    if (entry.labels && entry.labels[value]) return entry.labels[value];
    return String(value);
  }

  // ==========================================
  // STATUS
  // ==========================================

  // off: a switched-off module is no error, so it gets a grey chip
  function chip(ok, yes, no, off) {
    const tone = ok ? " efb-chip--ok" : off ? "" : " efb-chip--danger";
    return el("span", { class: "efb-chip efb-chip--dot" + tone, text: ok ? yes : no });
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

  function card(iconName, title, rows, actions) {
    const buttons = actions.filter(Boolean);
    return el(
      "section",
      { class: "efb-card" },
      el("div", { class: "efb-card__header" }, el("h2", { class: "efb-card__title" }, icon(iconName), title)),
      el("div", { class: "efb-card__body" }, ...rows),
      buttons.length ? el("div", { class: "efb-card__footer" }, ...buttons) : null,
    );
  }

  function row(label, value) {
    return el("div", { class: "efb-status__row" }, el("span", { class: "efb-status__label", text: label }), el("span", { class: "efb-status__value" }, value));
  }

  function statusView() {
    const lex = status.lex || {};
    const last = lex.last;
    const view = el("div", { class: "efb-status" });

    view.append(
      card(
        "server",
        "Allgemein",
        [
          row("Version", status.version || "?"),
          row("Ressource", status.resource || "?"),
          row("Framework", status.framework ? chip(true, status.framework, "") : chip(false, "", "keins gefunden")),
          row("Datenbank", chip(status.database, "verbunden", "keine (oxmysql)")),
        ],
        [],
      ),
      card(
        "ignis",
        "ignis",
        [
          row("API-Schlüssel", chip(status.ignisKeySet, "gesetzt", "fehlt (unter ignis eintragen)")),
          row("EMD-Sync", chip(status.emd, "an", "aus", true)),
          row("eNOTF-Abrechnung", chip(status.billing, "an", "aus", true)),
        ],
        [action("testIgnis", "Verbindung testen"), status.emd ? action("emdSync", "EMD jetzt abgleichen") : null],
      ),
      card(
        "scale",
        "Lex",
        [
          row("Abgleich", chip(lex.enabled, "an", "aus", true)),
          row("API-Schlüssel", chip(lex.keySet, "gesetzt", "fehlt (unter Lex eintragen)")),
          row("Letzter vollständiger Abgleich", lex.running ? "läuft gerade …" : last ? `${last.at} (${last.seconds} s)` : "noch keiner"),
          last ? row("Personen", `${last.persons.seen} gesehen, ${last.persons.created} neu, ${last.persons.updated} geändert, ${last.persons.skipped} übersprungen`) : null,
          last ? row("Fahrzeuge", `${last.vehicles.seen} gesehen, ${last.vehicles.created} neu, ${last.vehicles.updated} geändert, ${last.retired} abgemeldet`) : null,
          lex.lastLive ? row("Zuletzt beim Einloggen", `${lex.lastLive.at}, ${lex.lastLive.characters} Charakter(e)`) : null,
          lex.lastError ? el("p", { class: "efb-field__error" }, icon("alert"), el("span", { text: `${lex.lastError.at}: ${lex.lastError.message}` })) : null,
        ],
        [action("testLex", "Verbindung testen"), lex.enabled && lex.keySet ? action("lexSync", "Jetzt vollständig abgleichen") : null],
      ),
      el("div", { class: "efb-alert", role: "note" }, icon("info", "efb-alert__icon"), el("span", { class: "efb-alert__body", text: "Alle Einstellungen liegen auf dem Server, config-Dateien gibt es nicht mehr. Änderungen gelten sofort, außer bei Einträgen mit „nach Neustart“ (restart ef_bridge). API-Schlüssel lassen sich setzen und löschen, aber nicht mehr anzeigen." })),
    );
    return view;
  }

  // ==========================================
  // RENDER
  // ==========================================

  // the sidebar heading a group sits under, also the breadcrumb's first step
  function section(group) {
    return group === STATUS_GROUP ? "Übersicht" : group === IMPORT_GROUP ? "Werkzeuge" : "Einstellungen";
  }

  function renderNav() {
    const nav = $("efbNav");
    nav.replaceChildren();
    let heading = null;
    for (const group of groups()) {
      if (section(group) !== heading) {
        heading = section(group);
        nav.append(el("div", { class: "efb-sidebar__group", text: heading }));
      }
      const dirty = schema.some((e) => e.group === group && (Object.prototype.hasOwnProperty.call(changes, e.key) || resets.has(e.key)));
      const bad = schema.some((e) => e.group === group && errors[e.key]);
      nav.append(
        el(
          "button",
          {
            type: "button",
            class: "efb-sidebar__link",
            "aria-current": group === current ? "page" : null,
            "data-tooltip": group,
            onclick: () => {
              current = group;
              renderNav();
              renderContent();
            },
          },
          icon((GROUP_INFO[group] || {}).icon),
          el("span", { class: "efb-sidebar__label", text: group }),
          bad ? el("span", { class: "efb-dot efb-dot--bad", role: "img", "aria-label": "Fehler" }) : dirty ? el("span", { class: "efb-dot", role: "img", "aria-label": "ungespeichert" }) : null,
        ),
      );
    }
  }

  // breadcrumb and page header of the current group
  function pageHeader(actions) {
    const info = GROUP_INFO[current] || {};
    return [
      el("nav", { class: "efb-breadcrumb", "aria-label": "Pfad" }, el("span", { class: "efb-breadcrumb__item", text: section(current) }), el("span", { class: "efb-breadcrumb__item", "aria-current": "page", text: current })),
      el(
        "header",
        { class: "efb-page-header" },
        el("div", { class: "efb-page-header__copy" }, el("h1", { class: "efb-page-header__title", text: current }), info.text ? el("p", { class: "efb-page-header__description", text: info.text }) : null),
        actions ? el("div", { class: "efb-page-header__actions" }, actions) : null,
      ),
    ];
  }

  function settingsView() {
    const entries = schema.filter((e) => e.group === current);
    const basic = entries.filter((e) => !e.advanced);
    const advanced = entries.filter((e) => e.advanced);
    const cards = [];
    if (basic.length) cards.push(el("section", { class: "efb-card" }, el("div", { class: "efb-card__body efb-card__body--flush" }, ...basic.map(field))));
    if (advanced.length) {
      const box = el(
        "details",
        { class: "efb-card" },
        el("summary", { class: "efb-card__header" }, el("h2", { class: "efb-card__title" }, "Erweitert", el("span", { class: "efb-card__subtitle", text: advanced.length === 1 ? "1 Einstellung" : `${advanced.length} Einstellungen` }))),
        el("div", { class: "efb-card__body efb-card__body--flush" }, ...advanced.map(field)),
      );
      if (advanced.some((e) => errors[e.key] || Object.prototype.hasOwnProperty.call(changes, e.key))) box.open = true;
      cards.push(box);
    }
    return cards;
  }

  function renderContent() {
    const nodes = current === STATUS_GROUP ? [...pageHeader(), statusView()] : current === IMPORT_GROUP ? importView() : [...pageHeader(), ...settingsView()];
    $("efbContent").replaceChildren(...nodes);
  }

  // ==========================================
  // IMPORT
  // ==========================================

  // Page header (reading the folder needs no input, so it sits up there),
  // the paste card and, after a preview, the result card.
  function importView() {
    const area = el("textarea", { class: "efb-input efb-input--list efb-import__text", rows: 10, spellcheck: "false", placeholder: "Inhalt einer config.lua, config_server.lua oder settings-export.json hier einfügen" });
    area.value = importText;
    area.addEventListener("input", () => {
      importText = area.value;
      importResult = null;
    });

    const send = (apply, fromFolder) => {
      post("adminImport", { text: fromFolder ? "" : importText, apply });
    };

    const nodes = [
      ...pageHeader(el("button", { type: "button", class: "efb-btn efb-btn--secondary", text: "Aus dem Ordner lesen", onclick: () => { importText = ""; send(false, true); } })),
      el(
        "section",
        { class: "efb-card" },
        el(
          "div",
          { class: "efb-card__body efb-import" },
          el("p", { class: "efb-card__text", text: "Übernimmt Einstellungen aus alten config-Dateien von ignisTab oder ef_bridge und aus Exporten (efbridge export). Erst kommt eine Vorschau, übernommen wird erst nach „Übernehmen“. Liegen die Dateien im Ordner der Ressource, liest „Aus dem Ordner lesen“ sie direkt." }),
          area,
        ),
        el("div", { class: "efb-card__footer" }, el("button", { type: "button", class: "efb-btn efb-btn--secondary", text: "Vorschau", onclick: () => send(false, false) })),
      ),
    ];

    const r = importResult;
    if (!r) return nodes;
    const body = el("div", { class: "efb-card__body efb-import" });
    const view = el("section", { class: "efb-card" }, body);
    nodes.push(view);

    if (r.found === 0) {
      body.append(el("p", { class: "efb-field__error" }, icon("alert"), el("span", { text: "Nichts gefunden: weder eingefügter Text noch config-Dateien im Ordner." })));
      return nodes;
    }
    for (const problem of r.problems || []) body.append(el("p", { class: "efb-field__error" }, icon("alert"), el("span", { text: problem })));
    for (const note of r.notes || []) body.append(el("p", { class: "efb-field__help", text: "Altes Format: " + note }));

    if ((r.applied || []).length) {
      body.append(el("p", { class: "efb-import__done", text: `${r.applied.length} Einstellung(en) übernommen.` + (r.restart ? " Einiges davon gilt nach restart ef_bridge." : "") }));
    } else if ((r.preview || []).length) {
      const table = el("table", { class: "efb-import__table" }, el("thead", {}, el("tr", {}, el("th", { text: "Einstellung" }), el("th", { text: "jetzt" }), el("th", { text: "danach" }))));
      const rows = el("tbody");
      for (const item of r.preview) {
        rows.append(el("tr", {}, el("td", {}, el("span", { text: `${item.group} › ${item.label}` })), el("td", { text: item.from }), el("td", { text: item.to })));
      }
      table.append(rows);
      body.append(table);
      view.append(el("div", { class: "efb-card__footer" }, el("button", { type: "button", class: "efb-btn efb-btn--primary", text: `${r.preview.length} übernehmen`, onclick: () => send(true, importText === "") })));
    } else {
      body.append(el("p", { class: "efb-field__help", text: "Alles schon so eingestellt, es gibt nichts zu übernehmen." }));
    }
    for (const err of r.errors || []) body.append(el("p", { class: "efb-field__error" }, icon("alert"), el("span", { text: `${err.label}: ${err.message}` })));
    return nodes;
  }

  function imported(data) {
    importResult = data;
    if (data.state) state = data.state;
    if (data.status) status = data.status;
    if ((data.applied || []).length) toast("Import übernommen.", true);
    current = IMPORT_GROUP;
    render();
  }

  // topbar chips and the version under the sidebar; Lex, EMD and the
  // database are on the status page
  function renderHeader() {
    $("efbVersion").textContent = status.version ? "Version " + status.version : "";
    $("efbVersion").hidden = !status.version;
    $("efbChips").replaceChildren(chip(status.framework, status.framework, "kein Framework"), chip(status.ignisKeySet, "ignis", "ignis ohne Schlüssel"));
  }

  function renderFooter() {
    const n = pending();
    $("efbPending").textContent = n === 0 ? "Keine ungespeicherten Änderungen" : n === 1 ? "1 ungespeicherte Änderung" : `${n} ungespeicherte Änderungen`;
    $("efbPending").classList.toggle("is-dirty", n > 0);
    $("efbSave").disabled = n === 0;
    $("efbDiscard").disabled = n === 0;
  }

  function render() {
    renderHeader();
    renderNav();
    renderContent();
    renderFooter();
  }

  function toast(message, ok) {
    const box = $("efbToast");
    box.replaceChildren(icon(ok ? "check" : "alert"), el("span", { text: message }));
    box.className = "efb-toast " + (ok ? "efb-toast--ok" : "efb-toast--bad");
    box.hidden = false;
    clearTimeout(toast.timer);
    toast.timer = setTimeout(() => (box.hidden = true), 6000);
  }

  // ==========================================
  // SIDEBAR
  // ==========================================

  // Collapsed or open, kept like ignis keeps ignis.sidebar. CEF may refuse
  // localStorage (even reading the property can throw), the panel works
  // without it.
  const SIDEBAR_KEY = "efb.sidebar";
  const NARROW = "(max-width: 900px)";

  function storedCollapsed() {
    try {
      return localStorage.getItem(SIDEBAR_KEY) === "collapsed";
    } catch (e) {
      return false;
    }
  }

  function narrow() {
    return window.matchMedia(NARROW).matches;
  }

  function setCollapsed(collapsed) {
    $("adminPanel").classList.toggle("is-collapsed", collapsed);
    $("efbToggle").setAttribute("aria-expanded", collapsed ? "false" : "true");
  }

  // narrow screens collapse on their own, that is no choice to remember
  function applySidebar() {
    setCollapsed(narrow() || storedCollapsed());
  }

  function toggleSidebar() {
    const collapsed = !$("adminPanel").classList.contains("is-collapsed");
    setCollapsed(collapsed);
    if (narrow()) return;
    try {
      localStorage.setItem(SIDEBAR_KEY, collapsed ? "collapsed" : "open");
    } catch (e) {
      // no storage: the next open starts with the sidebar open
    }
  }

  function typing(target) {
    return !!target && (/^(INPUT|TEXTAREA|SELECT)$/.test(target.tagName) || target.isContentEditable === true);
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
    applySidebar();
    answer(false);
    $("adminPanel").hidden = false;
    render();
  }

  // Asks before unsaved changes get lost. onYes runs for the destructive
  // choice; Zurück, ESC or a click beside the dialog keep everything.
  let onConfirm = null;

  function confirmDiscard(okLabel, onYes) {
    const n = pending();
    if (n === 0) return onYes();
    $("efbConfirmTitle").textContent = n === 1 ? "1 ungespeicherte Änderung" : n + " ungespeicherte Änderungen";
    $("efbConfirmText").textContent = "Sie gehen verloren, wenn du jetzt weitermachst. Zum Behalten erst speichern.";
    $("efbConfirmOk").textContent = okLabel;
    onConfirm = onYes;
    $("efbConfirm").hidden = false;
    $("efbConfirmCancel").focus();
  }

  function answer(yes) {
    const run = onConfirm;
    onConfirm = null;
    $("efbConfirm").hidden = true;
    if (yes && run) run();
  }

  function close() {
    confirmDiscard("Verwerfen und schließen", () => {
      changes = {};
      resets = new Set();
      $("adminPanel").hidden = true;
      post("adminClose");
    });
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
    renderHeader();
    if (current === STATUS_GROUP) renderContent();
  }

  function init() {
    if (!$("adminPanel")) return;
    $("efbClose").replaceChildren(icon("close"));
    $("efbRefresh").replaceChildren(icon("refresh"), el("span", { text: "Neu laden" }));
    $("efbClose").addEventListener("click", close);
    $("efbSave").addEventListener("click", save);
    $("efbDiscard").addEventListener("click", () => {
      changes = {};
      resets = new Set();
      errors = {};
      render();
    });
    $("efbRefresh").addEventListener("click", () => {
      confirmDiscard("Verwerfen und neu laden", () => post("adminRefresh"));
    });
    $("efbConfirmOk").addEventListener("click", () => answer(true));
    $("efbConfirmCancel").addEventListener("click", () => answer(false));
    $("efbConfirm").addEventListener("click", (e) => {
      if (e.target === $("efbConfirm")) answer(false);
    });
    $("efbToggle").addEventListener("click", toggleSidebar);
    window.matchMedia(NARROW).addEventListener("change", applySidebar);
    applySidebar();
    document.addEventListener("keydown", (e) => {
      if ($("adminPanel").hidden) return;
      // the open question takes ESC; nothing else reacts meanwhile
      if (!$("efbConfirm").hidden) {
        if (e.key === "Escape") answer(false);
        return;
      }
      if (e.key === "Escape") close();
      else if (e.key === "[" && !typing(e.target)) {
        e.preventDefault();
        toggleSidebar();
      }
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
    else if (msg.type === "adminClose") {
      answer(false);
      $("adminPanel").hidden = true;
    }
  });

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", init);
  else init();
})();
