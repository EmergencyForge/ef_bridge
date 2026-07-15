// Debug mode is defined globally in master.js as window.DEBUG
// Global state - managed by master.js
// let isTabletOpen = false; // NOW MANAGED BY MASTER.JS
// let characterData = null; // NOW MANAGED BY MASTER.JS
let IntraURL = null;
let navigationHistory = [];
let historyIndex = -1;
let currentUrl = "";

// Funktion zum Sicherstellen, dass die URL HTTPS verwendet (FiveM-Anforderung)
function ensureHttps(url) {
  if (!url) {
    if (DEBUG) console.warn("[intraTab] ensureHttps: URL is null or undefined");
    return url;
  }

  const originalUrl = url;

  // Entferne führende/trailing Leerzeichen
  url = url.trim();

  // Wenn die URL mit http:// beginnt, ersetze es durch https://
  if (url.toLowerCase().startsWith("http://")) {
    url = url.replace(/^http:\/\//i, "https://");
    if (DEBUG)
      console.warn(
        "[intraTab] ⚠️  URL converted from HTTP to HTTPS:",
        originalUrl,
        "→",
        url
      );
  }
  // Wenn die URL nicht mit einem Protokoll beginnt, füge https:// hinzu
  else if (
    !url.toLowerCase().startsWith("https://") &&
    !url.toLowerCase().startsWith("//")
  ) {
    url = "https://" + url;
    if (DEBUG)
      console.log("[intraTab] Added HTTPS prefix:", originalUrl, "→", url);
  } else {
    if (DEBUG) console.log("[intraTab] ✓ URL already secure:", url);
  }

  // Füge trailing slash hinzu, falls URL auf einen Pfad endet (verhindert HTTP-Redirects)
  if (
    url.indexOf("?") === -1 &&
    url.indexOf("#") === -1 &&
    !url.endsWith("/")
  ) {
    // Prüfe ob es wie ein Verzeichnis aussieht (kein Dateityp am Ende)
    const lastSegment = url.split("/").pop();
    if (lastSegment && !lastSegment.includes(".")) {
      url = url + "/";
      if (DEBUG) console.log("[intraTab] Added trailing slash:", url);
    }
  }

  return url;
}

window.addEventListener("message", function (event) {
  const data = event.data;

  switch (data.type) {
    case "openTablet":
      // Only handle eNOTF tablet here (index.html)
      // FireTab is handled by firetab.html directly
      if (data.tabletType === "eNOTF") {
        openTablet(data.characterData, data.url);
      }
      break;

    case "setCharacterData":
      setCharacterData(data.characterData);
      break;

    case "closeTablet":
      // Only close eNOTF tablet here
      if (!data.tabletType || data.tabletType === "eNOTF") {
        if (DEBUG)
          console.log(
            "[intraTab] closeTablet message received for:",
            data.tabletType
          );
        closeTablet();
      }
      break;
  }
});

function openFireTab(charData, url) {
  if (DEBUG) console.log("[intraTab] Redirecting to FireTab with URL:", url);
  // FireTab wird in einer separaten HTML-Datei gehandhabt
  // Diese Funktion ist für zukünftige Integrationen gedacht
}

function openTablet(charData, url) {
  // Prevent double-opening
  if (isTabletOpen) {
    if (DEBUG)
      console.log(
        "[intraTab] Tablet already opening/open, ignoring duplicate call"
      );
    return;
  }

  characterData = charData;
  isTabletOpen = true;

  if (DEBUG) console.log("[intraTab] openTablet called with URL:", url);

  if (url) {
    IntraURL = ensureHttps(url);
    if (DEBUG) console.log("[intraTab] IntraURL set to:", IntraURL);
  }

  const tabletContainer = document.getElementById("tabletContainer");
  const loadingScreen = document.getElementById("loadingScreen");
  const tabletScreen = document.getElementById("tabletScreen");

  if (tabletContainer) {
    tabletContainer.style.display = "flex";
    document.body.style.cursor = "default";
    tabletContainer.style.cursor = "default";
  }

  if (tabletScreen && tabletScreen.src && tabletScreen.src !== "") {
    if (DEBUG)
      console.log(
        "[intraTab] Restoring tablet with existing content, checking URL:",
        tabletScreen.src
      );

    // Validate existing iframe src is HTTPS
    if (tabletScreen.src.toLowerCase().startsWith("http://")) {
      const secureUrl = tabletScreen.src.replace(/^http:\/\//i, "https://");
      if (DEBUG)
        console.warn(
          "[intraTab] ⚠️  Iframe had insecure URL, fixing:",
          tabletScreen.src,
          "→",
          secureUrl
        );
      tabletScreen.src = secureUrl;
    }

    if (loadingScreen) loadingScreen.style.display = "none";
    tabletScreen.style.display = "block";
    updateNavigationButtons();
    return;
  }

  if (loadingScreen) loadingScreen.style.display = "flex";
  if (tabletScreen) tabletScreen.style.display = "none";

  navigationHistory = [];
  historyIndex = -1;
  currentUrl = "";
  updateNavigationButtons();

  if (charData && charData.firstName && charData.lastName) {
    loadIntraSystem(charData);
  } else {
    const loadingText = document.getElementById("loadingText");
    if (loadingText)
      loadingText.textContent = "Verbindung zum Server wird hergestellt...";

    fetch(`https://${GetParentResourceName()}/getCharacterData`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({}),
    })
      .then((response) => response.json())
      .then((data) => {
        if (data.firstName && data.lastName) {
          loadIntraSystem(data);
        } else {
          if (loadingText)
            loadingText.textContent =
              "Error: " + (data.error || "Konnte keine Daten abfragen");
        }
      })
      .catch((error) => {
        if (DEBUG) console.error("Error getting character data:", error);
        if (loadingText)
          loadingText.textContent = "Fehler bei der Verbindung zum Server";
      });
  }
}

function setCharacterData(charData) {
  if (DEBUG) console.log("Setting character data:", charData);
  characterData = charData;

  if (isTabletOpen && charData && charData.firstName && charData.lastName) {
    loadIntraSystem(charData);
  }
}

function loadIntraSystem(charData) {
  const loadingText = document.getElementById("loadingText");
  if (loadingText) {
    loadingText.textContent =
      "Lade System für " + charData.firstName + " " + charData.lastName + "...";
  }

  const url = ensureHttps(IntraURL);
  if (DEBUG) console.log("[intraTab] loadIntraSystem: Final URL to load:", url);

  addToHistory(url);
  currentUrl = url;
  updatePageTitle("IntraRP Verwaltungsportal");

  const iframe = document.getElementById("tabletScreen");
  const loadingScreen = document.getElementById("loadingScreen");

  if (iframe) {
    if (DEBUG) console.log("[intraTab] Setting iframe.src to:", url);

    // Set onload handler BEFORE setting src
    iframe.onload = () => {
      if (DEBUG) console.log("[intraTab] Iframe loaded successfully");
      if (loadingScreen) loadingScreen.style.display = "none";
      iframe.style.display = "block";
      updateNavigationButtons();
    };

    // Überwache iframe src Änderungen (falls Website auf HTTP redirected)
    const checkIframeSrc = () => {
      try {
        const currentSrc = iframe.src;
        if (currentSrc && currentSrc.toLowerCase().startsWith("http://")) {
          if (DEBUG)
            console.error(
              "[intraTab] 🚨 CRITICAL: Iframe redirected to HTTP, forcing HTTPS:",
              currentSrc
            );
          const secureSrc = currentSrc.replace(/^http:\/\//i, "https://");
          iframe.src = secureSrc;
        }
      } catch (e) {
        // Cross-origin Fehler ignorieren
      }
    };

    // Prüfe nach kurzer Verzögerung
    setTimeout(checkIframeSrc, 500);
    setTimeout(checkIframeSrc, 1500);

    // Fallback: Verstecke loading screen nach 3 Sekunden falls onload nicht fired
    setTimeout(() => {
      if (loadingScreen && loadingScreen.style.display !== "none") {
        if (DEBUG)
          console.warn(
            "[intraTab] Loading screen fallback timeout - hiding loading screen"
          );
        loadingScreen.style.display = "none";
        iframe.style.display = "block";
        updateNavigationButtons();
      }
    }, 3000);

    // Set src AFTER handlers are registered
    iframe.src = url;
  }
}

function closeTablet() {
  if (DEBUG) console.log("[intraTab] Closing eNOTF tablet UI");

  isTabletOpen = false;
  const tabletContainer = document.getElementById("tabletContainer");

  if (tabletContainer) {
    tabletContainer.style.display = "none";
    // Reset cursor explicitly
    document.body.style.cursor = "none";
    tabletContainer.style.cursor = "none";
  }

  fetch(`https://${GetParentResourceName()}/closeTablet`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify({}),
  }).catch((error) => {
    if (DEBUG) console.error("Error closing tablet:", error);
  });
}

function addToHistory(url) {
  if (historyIndex < navigationHistory.length - 1) {
    navigationHistory = navigationHistory.slice(0, historyIndex + 1);
  }

  navigationHistory.push(url);
  historyIndex = navigationHistory.length - 1;

  if (navigationHistory.length > 50) {
    navigationHistory = navigationHistory.slice(-50);
    historyIndex = navigationHistory.length - 1;
  }
}

function updateNavigationButtons() {
  const backBtn = document.getElementById("backBtn");

  if (backBtn) {
    if (historyIndex > 0) {
      backBtn.disabled = false;
      backBtn.style.opacity = "1";
    } else {
      backBtn.disabled = true;
      backBtn.style.opacity = "0.4";
    }
  }
}

function updatePageTitle(title) {
  const pageTitle = document.getElementById("pageTitle");
  if (pageTitle) {
    pageTitle.textContent = title;
  }
}

function goBack() {
  if (!isTabletOpen || historyIndex <= 0) {
    if (DEBUG) console.log("Cannot go back");
    return;
  }

  historyIndex--;
  const previousUrl = navigationHistory[historyIndex];

  if (previousUrl) {
    currentUrl = previousUrl;
    const iframe = document.getElementById("tabletScreen");
    const loadingScreen = document.getElementById("loadingScreen");

    if (iframe && loadingScreen) {
      loadingScreen.style.display = "flex";
      iframe.style.display = "none";
      iframe.src = previousUrl;

      setTimeout(() => {
        loadingScreen.style.display = "none";
        iframe.style.display = "block";
      }, 1000);
    }

    updateNavigationButtons();
    if (DEBUG) console.log("Navigated back to:", previousUrl);
  }
}

function goHome() {
  if (!isTabletOpen || !characterData) {
    if (DEBUG) console.log("Cannot go home");
    return;
  }

  const characterName = characterData.firstName + " " + characterData.lastName;
  const homeUrl =
    IntraURL + "?charactername=" + encodeURIComponent(characterName);

  addToHistory(homeUrl);
  currentUrl = homeUrl;

  const iframe = document.getElementById("tabletScreen");
  const loadingScreen = document.getElementById("loadingScreen");

  if (iframe && loadingScreen) {
    loadingScreen.style.display = "flex";
    iframe.style.display = "none";
    iframe.src = homeUrl;

    setTimeout(() => {
      loadingScreen.style.display = "none";
      iframe.style.display = "block";
    }, 1000);
  }

  updateNavigationButtons();
  updatePageTitle("IntraRP Verwaltungsportal");
  if (DEBUG) console.log("Navigated to home:", homeUrl);
}

function refreshPage() {
  if (!isTabletOpen || !currentUrl) {
    if (DEBUG) console.log("Cannot refresh");
    return;
  }

  const iframe = document.getElementById("tabletScreen");
  const loadingScreen = document.getElementById("loadingScreen");

  if (iframe && loadingScreen) {
    loadingScreen.style.display = "flex";
    iframe.style.display = "none";
    iframe.src = "about:blank";

    setTimeout(() => {
      iframe.src = currentUrl;
      setTimeout(() => {
        loadingScreen.style.display = "none";
        iframe.style.display = "block";
      }, 1000);
    }, 100);
  }

  if (DEBUG) console.log("Refreshed page:", currentUrl);
}

function addEventListeners() {
  // ESC handling is managed by client Lua to avoid unintended DOM-triggered closes.
  // This NUI only closes via explicit UI actions or server messages.

  document.addEventListener("contextmenu", function (e) {
    e.preventDefault();
    return false;
  });

  document.addEventListener("mousemove", function () {
    if (isTabletOpen) {
      document.body.style.cursor = "default";
    }
  });

  // Allow closing eNOTF via ESC in NUI, consistent with FireTab
  document.addEventListener("keydown", function (event) {
    if (event.key === "Escape") {
      const tabletContainer = document.getElementById("tabletContainer");
      if (tabletContainer && tabletContainer.style.display === "flex") {
        closeTablet();
      }
    }
  });
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", addEventListeners);
} else {
  addEventListeners();
}
