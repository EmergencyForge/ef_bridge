// Input layer for a tablet held in the hand: its page runs in a DUI, which
// only gets mouse input from the game. While active, this page catches
// buttons, wheel and keys and hands them to client/dui.lua (the cursor
// position comes from GetNuiCursorPosition there). ESC closes the tablet:
// the window's own ESC handlers only fire while their container shows.
(() => {
  let active = false;
  const buttons = ["left", "middle", "right"];

  const post = (name, body) =>
    fetch(`https://${GetParentResourceName()}/${name}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    }).catch(() => {});

  window.addEventListener("message", (e) => {
    if (!e.data || e.data.type !== "duiInput") return;
    // only the game client may switch it, never a page inside a tablet frame
    if (fromTabletFrame(e)) return;
    active = e.data.active === true;
  });
  window.addEventListener("mousedown", (e) => {
    if (active) post("duiInput", { kind: "down", button: buttons[e.button] || "left" });
  });
  window.addEventListener("mouseup", (e) => {
    if (active) post("duiInput", { kind: "up", button: buttons[e.button] || "left" });
  });
  window.addEventListener(
    "wheel",
    (e) => {
      if (active) post("duiInput", { kind: "wheel", dy: e.deltaY });
    },
    { passive: true },
  );
  window.addEventListener("keydown", (e) => {
    if (!active) return;
    e.preventDefault();
    // AltGr sets ctrl and alt together; ignis drops keys with ctrl set
    if (e.key === "Escape") closeTablet();
    else post("duiInput", { kind: "key", key: e.key, ctrl: e.ctrlKey && !e.getModifierState("AltGraph"), shift: e.shiftKey });
  });
  window.addEventListener("contextmenu", (e) => {
    if (active) e.preventDefault();
  });
})();
