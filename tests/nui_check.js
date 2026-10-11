// Loads the NUI scripts (firetab.js, script.js, master.js, dui.js; same
// order as master.html) with a fake DOM and checks the tablet login
// message, the session relay, tablets in hand and the input layer.
//
//   node tests/nui_check.js
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const js = (name) =>
  fs.readFileSync(path.join(__dirname, "..", "html", "js", name), "utf8");

// window objects: NUI root -> resource page -> tablet frames -> nested frames
const root = {};
root.parent = root;

function makeElement() {
  return {
    style: {},
    classList: { add() {}, remove() {} },
    addEventListener() {},
  };
}

function makeFrame(src, page) {
  const frame = makeElement();
  Object.assign(frame, { src, history: [], loadListeners: [] });
  frame.contentWindow = { parent: page };
  frame.addEventListener = (name, fn, opts) => {
    if (name === "load")
      frame.loadListeners.push({ fn, once: opts && opts.once });
  };
  frame.fireLoad = () => {
    const ls = frame.loadListeners;
    frame.loadListeners = ls.filter((l) => !l.once);
    ls.forEach((l) => l.fn());
  };
  return new Proxy(frame, {
    set(t, k, v) {
      if (k === "src") t.history.push(v);
      t[k] = v;
      return true;
    },
  });
}

// deferTimers: queue setTimeout callbacks until runTimers() is called
function load({ deferTimers = false } = {}) {
  const listeners = [];
  const logged = [];
  const fetched = [];
  const timers = [];
  const ctx = {
    console: {
      log: (...a) => logged.push(a),
      warn: (...a) => logged.push(a),
      error: (...a) => logged.push(a),
    },
    GetParentResourceName: () => "ef_bridge",
    fetch: (url, opts) => {
      fetched.push({ url, body: opts && opts.body });
      return Promise.resolve();
    },
    setTimeout: (fn) => (deferTimers ? timers.push({ fn }) : (fn(), 0)),
    clearTimeout: (id) => {
      if (id && timers[id - 1]) timers[id - 1].cancelled = true;
    },
    parent: root,
  };
  ctx.window = ctx;
  const byName = {};
  ctx.addEventListener = (name, fn) => {
    (byName[name] ||= []).push(fn);
    if (name === "message") listeners.push(fn);
  };
  const frames = {
    tabletScreen: makeFrame("https://ignis.test/enotf/overview.php", ctx),
    firetabScreen: makeFrame("https://ignis.test/einsatz/list.php", ctx),
  };
  const elements = {};
  ctx.document = {
    readyState: "complete",
    addEventListener() {},
    body: { style: {} },
    getElementById: (id) => frames[id] || (elements[id] ||= makeElement()),
  };
  vm.createContext(ctx);
  for (const name of ["firetab.js", "script.js", "master.js", "dui.js"])
    vm.runInContext(js(name), ctx, { filename: name });
  vm.runInContext("DEBUG = true", ctx);

  // SendNUIMessage arrives from the NUI root, frames post from inside
  const send = (data, source = root) =>
    listeners.forEach((fn) => fn({ data, source }));
  const fire = (name, event) => (byName[name] || []).forEach((fn) => fn(event));
  // ids stay valid for clearTimeout, so run in place instead of shifting
  let next = 0;
  const runTimers = () => {
    while (next < timers.length) {
      const t = timers[next++];
      if (!t.cancelled) t.fn();
    }
  };
  return { ctx, frames, elements, logged, fetched, send, fire, runTimers };
}

let failed = 0;
const check = (label, ok) => {
  console.log(`${ok ? "ok   " : "FAIL "}${label}`);
  if (!ok) failed++;
};

const loginUrl = "https://ignis.test/auth/tablet?token=SECRET123";

// login link from the game
{
  const { frames, logged, send } = load();
  const ft = frames.firetabScreen;
  send({ type: "tabletLogin", tabletType: "FireTab", url: loginUrl });
  check("firetab frame loads the login link", ft.src === loginUrl);
  check("enotf frame untouched", frames.tabletScreen.history.length === 0);
  ft.fireLoad(); // ignis dashboard after the redirect
  check("back to the previous page after login", ft.src === "https://ignis.test/einsatz/list.php");
  ft.fireLoad(); // the target page itself
  check("no loop on later loads", ft.history.length === 2);

  send({ type: "tabletLogin", tabletType: "eNOTF", url: loginUrl }, null);
  check("message without source (older builds) is accepted", frames.tabletScreen.src === loginUrl);
  check("token never logged", !JSON.stringify(logged).includes("SECRET123"));
}

// game messages posted from inside a tablet frame
{
  const { ctx, frames, send } = load();
  const evil = "javascript:parent.document.title='x'";
  const inFrame = frames.tabletScreen.contentWindow;
  const nested = { parent: frames.firetabScreen.contentWindow };

  send({ type: "tabletLogin", tabletType: "FireTab", url: evil }, inFrame);
  send({ type: "tabletLogin", tabletType: "FireTab", url: loginUrl }, nested);
  check("tabletLogin from a frame is ignored", frames.firetabScreen.history.length === 0);

  send({ type: "openTablet", tabletType: "eNOTF", url: "https://evil.test/", characterData: {} }, inFrame);
  send({ type: "openTablet", tabletType: "FireTab", url: "https://evil.test/", characterData: {} }, nested);
  check("openTablet from a frame is ignored",
    frames.tabletScreen.history.length === 0 && frames.firetabScreen.history.length === 0 &&
    !vm.runInContext("isTabletOpen", ctx));

  send({ type: "tabletLogin", tabletType: "FireTab", url: evil });
  send({ type: "tabletLogin", tabletType: "FireTab", url: "http://ignis.test/auth/tablet?token=x" });
  check("only https login links", frames.firetabScreen.history.length === 0);

  send({ type: "openTablet", tabletType: "eNOTF", url: "https://ignis.test/enotf/overview.php", characterData: {} });
  check("openTablet from the game still works", vm.runInContext("isTabletOpen", ctx));
}

// session relay from the ignis page inside a frame
for (const type of ["ignis_session", "intraRP_session"]) {
  const { frames, fetched, send } = load();
  send({ type, session_id: "abc" }, frames.tabletScreen.contentWindow);
  const hits = fetched.filter((c) => c.url.endsWith("/sessionIdentify"));
  check(`${type} -> sessionIdentify`, hits.length === 1 && JSON.parse(hits[0].body).session_id === "abc");
}

// tablet in hand: hidden frame, blank, reveal
{
  const { frames, elements, send } = load();
  const url = "https://ignis.test/enotf/overview.php";
  send({ type: "openTablet", tabletType: "eNOTF", url, characterData: { firstName: "A", lastName: "B" }, hidden: true });
  check("hidden open keeps the window hidden", elements.tabletContainer.style.display === "none");
  send({ type: "blankTabletFrame", tabletType: "eNOTF" });
  check("blank empties the frame", frames.tabletScreen.src === "about:blank");
  send({ type: "blankTabletFrame", tabletType: "FireTab" }, frames.tabletScreen.contentWindow);
  check("blank from a frame is ignored", frames.firetabScreen.history.length === 0);
  send({ type: "revealTablet", tabletType: "eNOTF", url });
  check("reveal shows the window", elements.tabletContainer.style.display === "flex");
  check("reveal loads the page into a blanked frame", frames.tabletScreen.src === url);
  send({ type: "blankTabletFrame", tabletType: "eNOTF" });
  send({ type: "closeTablet", tabletType: "eNOTF" });
  send({ type: "openTablet", tabletType: "eNOTF", url, characterData: { firstName: "A", lastName: "B" } });
  check("window after a blanked frame loads the page again", frames.tabletScreen.src === url);
}

// firetab.js shows its window synchronously, master.js must hide it before
// the timer runs, or the window paints for a frame
{
  const { elements, send, runTimers } = load({ deferTimers: true });
  send({ type: "openTablet", tabletType: "FireTab", url: "https://ignis.test/einsatz/list.php", characterData: { firstName: "A", lastName: "B" }, hidden: true });
  check("hidden FireTab stays hidden before the timers run", elements.firetabContainer.style.display === "none");
  runTimers();
  check("hidden FireTab stays hidden after the timers run", elements.firetabContainer.style.display === "none");
}

// a frame that still holds a page (earlier window open, fallback) only shows
// it again; a hidden open must load it fresh so the page reports its session
for (const [type, frameId, url] of [
  ["eNOTF", "tabletScreen", "https://ignis.test/enotf/overview.php"],
  ["FireTab", "firetabScreen", "https://ignis.test/einsatz/list.php"],
]) {
  const { frames, send } = load();
  const frame = frames[frameId];
  send({ type: "openTablet", tabletType: type, url, characterData: { firstName: "A", lastName: "B" } });
  check(`window ${type} open keeps the loaded page`, frame.history.length === 0);
  send({ type: "closeTablet", tabletType: type });
  send({ type: "openTablet", tabletType: type, url, characterData: { firstName: "A", lastName: "B" }, hidden: true });
  check(`hidden ${type} open loads the page fresh`, frame.history.length === 1 && frame.src === url);
}

// a blank while the login link still loads must not bring the page back
{
  const { frames, send } = load();
  send({ type: "tabletLogin", tabletType: "eNOTF", url: loginUrl });
  send({ type: "blankTabletFrame", tabletType: "eNOTF" });
  frames.tabletScreen.fireLoad();
  check("blank survives a pending login", frames.tabletScreen.src === "about:blank");
}

// input layer
{
  const { frames, fetched, send, fire } = load();
  const key = (k, extra = {}) => ({ key: k, ctrlKey: false, shiftKey: false, getModifierState: () => false, preventDefault() {}, ...extra });
  fire("keydown", key("a"));
  check("no input while inactive", fetched.length === 0);
  send({ type: "duiInput", active: true }, frames.tabletScreen.contentWindow);
  fire("keydown", key("a"));
  check("activation from a frame is ignored", fetched.length === 0);
  send({ type: "duiInput", active: true });
  fire("keydown", key("a"));
  fire("mousedown", { button: 2 });
  // AltGr on a German layout sets ctrl and alt; ignis drops keys with ctrl
  fire("keydown", key("@", { ctrlKey: true, getModifierState: (m) => m === "AltGraph" }));
  fire("keydown", key("c", { ctrlKey: true }));
  fire("keydown", key("Escape"));
  const input = fetched.filter((c) => c.url.endsWith("/duiInput")).map((c) => JSON.parse(c.body));
  check("key forwarded", input.some((b) => b.kind === "key" && b.key === "a"));
  check("right click forwarded", input.some((b) => b.kind === "down" && b.button === "right"));
  check("AltGr character goes without ctrl", input.some((b) => b.kind === "key" && b.key === "@" && b.ctrl === false));
  check("ctrl shortcut keeps ctrl", input.some((b) => b.kind === "key" && b.key === "c" && b.ctrl === true));
  check("ESC closes the tablet", fetched.some((c) => c.url.endsWith("/closeTablet")));

  // back/forward buttons are often push-to-talk, they must not turn into clicks
  const posts = () => fetched.filter((c) => c.url.endsWith("/duiInput")).length;
  const before = posts();
  for (const button of [3, 4]) {
    fire("mousedown", { button });
    fire("mouseup", { button });
  }
  check("side mouse buttons post nothing", posts() === before);
  fire("mouseup", { button: 0 });
  check("left release still forwarded", posts() === before + 1);
}

// a loaded frame lets the DUI start; the login link tells it to reload
{
  const { frames, fetched, send } = load();
  const posted = (name) => fetched.filter((c) => c.url.endsWith("/" + name)).map((c) => JSON.parse(c.body));
  frames.tabletScreen.fireLoad();
  check("frame load is reported with its tablet", posted("tabletFrameLoaded").some((b) => b.tabletType === "eNOTF"));
  send({ type: "blankTabletFrame", tabletType: "eNOTF" });
  const before = posted("tabletFrameLoaded").length;
  frames.tabletScreen.fireLoad();
  check("a blanked frame's load is not reported", posted("tabletFrameLoaded").length === before);
  send({ type: "tabletLogin", tabletType: "FireTab", url: loginUrl });
  frames.firetabScreen.fireLoad();
  check("login link loaded: reported for the DUI", posted("tabletLoginDone").some((b) => b.tabletType === "FireTab"));
}

// window: the page stays loaded for KeepMinutes after closing, then the frame empties
{
  const { frames, send, runTimers } = load({ deferTimers: true });
  const url = "https://ignis.test/enotf/overview.php";
  const open = () => send({ type: "openTablet", tabletType: "eNOTF", url, characterData: { firstName: "A", lastName: "B" } });
  open();
  runTimers();
  send({ type: "closeTablet", tabletType: "eNOTF", keepMinutes: 15 });
  check("closed window keeps its page at first", frames.tabletScreen.src === url);
  runTimers();
  check("after the keep time the frame empties", frames.tabletScreen.src === "about:blank");
  open();
  runTimers();
  send({ type: "closeTablet", tabletType: "eNOTF", keepMinutes: 15 });
  open();
  runTimers();
  check("reopening in time cancels the release", frames.tabletScreen.src === url);
}

console.log(failed === 0 ? "all checks passed" : `${failed} check(s) failed`);
process.exit(failed ? 1 : 0);
