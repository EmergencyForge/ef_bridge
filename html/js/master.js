// ==========================================
// MASTER.JS - NUI Orchestrierung für mehrere Tablets
// ==========================================

// Debug mode - set to false to disable all console logs
window.DEBUG = false;

let currentTablet = null;
let isTabletOpen = false;
let characterData = null;

if (DEBUG) console.log("[Master] Loading master.js...");

// ==========================================
// TABLET CONTROL FUNCTIONS
// ==========================================

/**
 * Zeigt ein Tablet an und versteckt andere
 * eNOTF → #tabletContainer
 * FireTab → #firetabContainer
 */
function showTablet(tabletType) {
  const enotf = document.getElementById("tabletContainer");
  const firetab = document.getElementById("firetabContainer");

  // Verstecke alle erst
  if (enotf) enotf.classList.remove("active");
  if (firetab) firetab.classList.remove("active");

  // Zeige das richtige
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
  if (DEBUG) console.log("[Master] All tablets hidden");
}

function closeTablet() {
  if (DEBUG) console.log("[Master] closeTablet() called");
  hideAllTablets();

  // Reset cursor explicitly
  document.body.style.cursor = "none";

  // Notify server
  // Use dynamic resource name to ensure correct NUI callback routing
  fetch(`https://${GetParentResourceName()}/closeTablet`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ tabletType: currentTablet }),
  }).catch((err) => {
    if (DEBUG) console.log("[Master] Fetch error:", err);
  });
}

function goHome() {
  if (DEBUG) console.log("[Master] goHome() called for:", currentTablet);
}

function goBack() {
  if (DEBUG) console.log("[Master] goBack() called for:", currentTablet);

  // Get the correct iframe based on current tablet
  const iframe =
    currentTablet === "enotf"
      ? document.getElementById("tabletScreen")
      : document.getElementById("firetabScreen");

  if (iframe && iframe.contentWindow) {
    try {
      iframe.contentWindow.history.back();
      if (DEBUG) console.log("[Master] Navigated back in iframe history");
    } catch (e) {
      if (DEBUG) console.error("[Master] Error navigating back:", e);
    }
  }
}

// ==========================================
// NUI MESSAGE LISTENER
// ==========================================

window.addEventListener("message", function (event) {
  const data = event.data;

  if (!data) return;

  if (DEBUG) console.log("[Master] NUI message received:", data);

  // Handle openTablet message from server
  if (data.type === "openTablet") {
    const tabletType = data.tabletType; // "eNOTF" or "FireTab"
    const charData = data.characterData;
    const url = data.url;

    const normalized = (tabletType + "").toLowerCase();

    if (normalized === "firetab") {
      // FireTab - use firetab.js function
      if (DEBUG) console.log("[Master] Showing FireTab container");
      showTablet("firetab");

      // Wait a tiny bit for DOM to update before calling openFireTablet
      setTimeout(() => {
        if (
          window.openFireTablet &&
          typeof window.openFireTablet === "function"
        ) {
          if (DEBUG) console.log("[Master] Calling openFireTablet");
          window.openFireTablet(charData, url);
        } else {
          if (DEBUG)
            console.error("[Master] openFireTablet function not found!");
        }
      }, 10);
    } else if (normalized === "enotf") {
      // eNOTF - use script.js function
      showTablet("enotf");
      if (window.openTablet && typeof window.openTablet === "function") {
        if (DEBUG) console.log("[Master] Calling openTablet for enotf");
        window.openTablet(charData, url);
      }
    }
  }

  // Handle close messages
  else if (data.type === "closeTablet") {
    const reqType = (data.tabletType || "").toLowerCase();
    const curType = (currentTablet || "").toLowerCase();

    // Only close if type matches current tablet or no type provided
    if (!reqType || !curType || reqType === curType) {
      if (DEBUG)
        console.log(
          `[Master] closeTablet message for ${reqType || "any"}, closing.`,
        );
      closeTablet();
    } else {
      if (DEBUG)
        console.log(
          `[Master] closeTablet message for ${reqType}, ignored; current=${curType}`,
        );
    }
  }
});

// ==========================================
// SESSION IDENTIFICATION (postMessage from PHP iframe)
// ==========================================

// Listen for postMessage from the PHP iframe (_head.php sends session_id)
window.addEventListener("message", function (event) {
  const data = event.data;
  if (!data || !data.type) return;

  if (data.type === "intraRP_session" && data.session_id) {
    if (DEBUG) console.log("[Master] Received PHP session_id via postMessage:", data.session_id);

    // Forward session_id to FiveM client via NUI callback
    fetch(`https://${GetParentResourceName()}/sessionIdentify`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ session_id: data.session_id }),
    }).catch((err) => {
      if (DEBUG) console.log("[Master] sessionIdentify fetch error:", err);
    });
  }
});

// Note: ESC handling is managed in client Lua to prevent unintended
// auto-close events from the DOM. NUI will only close via explicit
// messages or UI controls.

if (DEBUG) console.log("[Master] Initialization complete");
