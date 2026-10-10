// Loads the NUI scripts (firetab.js, script.js, master.js, same order as
// master.html) with a fake DOM and checks the tablet login message and
// the session relay.
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

function load() {
  const listeners = [];
  const logged = [];
  const fetched = [];
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
    setTimeout: (fn) => fn(),
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
  return { ctx, frames, elements, logged, fetched, send, fire };
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

// input layer
{
  const { frames, fetched, send, fire } = load();
  const key = (k) => ({ key: k, ctrlKey: false, shiftKey: false, preventDefault() {} });
  fire("keydown", key("a"));
  check("no input while inactive", fetched.length === 0);
  send({ type: "duiInput", active: true }, frames.tabletScreen.contentWindow);
  fire("keydown", key("a"));
  check("activation from a frame is ignored", fetched.length === 0);
  send({ type: "duiInput", active: true });
  fire("keydown", key("a"));
  fire("mousedown", { button: 2 });
  fire("keydown", key("Escape"));
  const input = fetched.filter((c) => c.url.endsWith("/duiInput")).map((c) => JSON.parse(c.body));
  check("key forwarded", input.some((b) => b.kind === "key" && b.key === "a"));
  check("right click forwarded", input.some((b) => b.kind === "down" && b.button === "right"));
  check("ESC closes the tablet", fetched.some((c) => c.url.endsWith("/closeTablet")));
}

console.log(failed === 0 ? "all checks passed" : `${failed} check(s) failed`);
process.exit(failed ? 1 : 0);
