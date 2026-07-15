// master.js — NUI orchestration for both tablets.
// Decides which tablet container to show and relays messages between
// the game client and the tablet scripts.

// Debug mode - set to true to enable console logs
window.DEBUG = false;

let currentTablet = null;
let isTabletOpen = false;
let characterData = null;

// ==========================================
// TABLET CONTROL
// ==========================================

// eNOTF → #tabletContainer, FireTab → #firetabContainer
function showTablet(tabletType) {
  const enotf = document.getElementById("tabletContainer");
  const firetab = document.getElementById("firetabContainer");

  if (enotf) enotf.classList.remove("active");
  if (firetab) firetab.classList.remove("active");

  const normalized = (tabletType + "").toLowerCase();

  if (normalized === "enotf") {
    if (enotf) enotf.classList.add("active");
    currentTablet = "enotf";
  } else if (normalized === "firetab") {
    if (firetab) firetab.classList.add("active");
    currentTablet = "firetab";
  }

  isTabletOpen = true;
  if (DEBUG) console.log(`[Master] Showing ${currentTablet} tablet`);
}

function hideAllTablets() {
  const enotf = document.getElementById("tabletContainer");
  const firetab = document.getElementById("firetabContainer");

  if (enotf) {
    enotf.classList.remove("active");
    enotf.style.display = "none";
  }
  if (firetab) {
    firetab.classList.remove("active");
    firetab.style.display = "none";
  }

  currentTablet = null;
  isTabletOpen = false;
}

function closeTablet() {
  if (DEBUG) console.log("[Master] closeTablet() called");
  const closingType = currentTablet;
  hideAllTablets();

  document.body.style.cursor = "none";

  // dynamic resource name so the NUI callback hits the right resource
  fetch(`https://${GetParentResourceName()}/closeTablet`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ tabletType: closingType }),
  }).catch((err) => {
    if (DEBUG) console.log("[Master] Fetch error:", err);
  });
}

// The header buttons call these; dispatch to whichever tablet is open
function goHome() {
  if (currentTablet === "enotf" && typeof window.goHomeENOTF === "function") {
    window.goHomeENOTF();
  } else if (
    currentTablet === "firetab" &&
    typeof window.goHomeFireTab === "function"
  ) {
    window.goHomeFireTab();
  }
}

function goBack() {
  if (currentTablet === "enotf" && typeof window.goBackENOTF === "function") {
    window.goBackENOTF();
  }
}

// ==========================================
// NUI MESSAGE LISTENER
// ==========================================

window.addEventListener("message", function (event) {
  const data = event.data;

  if (!data) return;

  if (DEBUG) console.log("[Master] NUI message received:", data);

  if (data.type === "openTablet") {
    const tabletType = data.tabletType; // "eNOTF" or "FireTab"
    const charData = data.characterData;
    const url = data.url;

    const normalized = (tabletType + "").toLowerCase();

    if (normalized === "firetab") {
      showTablet("firetab");

      // give the DOM a moment before firetab.js touches the elements
      setTimeout(() => {
        if (
          window.openFireTablet &&
          typeof window.openFireTablet === "function"
        ) {
          window.openFireTablet(charData, url);
        } else {
          if (DEBUG)
            console.error("[Master] openFireTablet function not found!");
        }
      }, 10);
    } else if (normalized === "enotf") {
      showTablet("enotf");
      if (window.openTablet && typeof window.openTablet === "function") {
        window.openTablet(charData, url);
      }
    }
  }

  else if (data.type === "closeTablet") {
    const reqType = (data.tabletType || "").toLowerCase();
    const curType = (currentTablet || "").toLowerCase();

    // only close when the type matches (or none was given)
    if (!reqType || !curType || reqType === curType) {
      closeTablet();
    } else if (DEBUG) {
      console.log(
        `[Master] closeTablet message for ${reqType}, ignored; current=${curType}`,
      );
    }
  }
});

// ==========================================
// SESSION IDENTIFICATION
// ==========================================

// The PHP page inside the iframe posts its session_id up to us; forward
// it to the game client so the server can identify the character.
window.addEventListener("message", function (event) {
  const data = event.data;
  if (!data || !data.type) return;

  if (data.type === "intraRP_session" && data.session_id) {
    if (DEBUG) console.log("[Master] Received PHP session_id via postMessage");

    fetch(`https://${GetParentResourceName()}/sessionIdentify`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ session_id: data.session_id }),
    }).catch((err) => {
      if (DEBUG) console.log("[Master] sessionIdentify fetch error:", err);
    });
  }
});

// ESC handling lives in the client Lua so the DOM can't trigger
// accidental closes; the NUI only closes via explicit messages or the
// UI controls.
