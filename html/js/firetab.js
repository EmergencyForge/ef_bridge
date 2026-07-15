// Debug mode is defined globally in master.js as window.DEBUG
// Global state - managed by master.js
// let isTabletOpen = false; // NOW MANAGED BY MASTER.JS
// let characterData = null; // NOW MANAGED BY MASTER.JS
let FireTabURL = null;

// PATCH for master.html: Map global loadingScreen/loadingText to FireTab-specific elements
(function () {
  const firetabContainer = document.getElementById("firetabContainer");
  if (firetabContainer) {
    // Override document.getElementById to return FireTab-specific elements when in FireTab mode
    const originalGetElementById = document.getElementById;
    const isFireTabScript = true; // This script is firetab.js

    // Create wrapper that checks for loading elements and returns the right one
    window.__getFireTabElement = function (id) {
      if (isFireTabScript && (id === "loadingScreen" || id === "loadingText")) {
        const selector =
          id === "loadingScreen"
            ? "#firetabContainer .loading-screen"
            : "#firetabContainer .firetab-loading-text";
        return document.querySelector(selector);
      }
      return originalGetElementById.call(document, id);
    };
  }
})();

// Funktion zum Sicherstellen, dass die URL HTTPS verwendet
function ensureHttps(url) {
  if (!url) {
    if (DEBUG) console.warn("[FireTab] ensureHttps: URL is null or undefined");
    return url;
  }

  const originalUrl = url;
  url = url.trim();

  if (url.toLowerCase().startsWith("http://")) {
    url = url.replace(/^http:\/\//i, "https://");
    if (DEBUG)
      console.warn(
        "[FireTab] ⚠️  URL converted from HTTP to HTTPS:",
        originalUrl,
        "→",
        url
      );
  } else if (
    !url.toLowerCase().startsWith("https://") &&
    !url.toLowerCase().startsWith("//")
  ) {
    url = "https://" + url;
    if (DEBUG)
      console.log("[FireTab] Added HTTPS prefix:", originalUrl, "→", url);
  } else {
    if (DEBUG) console.log("[FireTab] ✓ URL already secure:", url);
  }

  if (
    url.indexOf("?") === -1 &&
    url.indexOf("#") === -1 &&
    !url.endsWith("/")
  ) {
    const lastSegment = url.split("/").pop();
    if (lastSegment && !lastSegment.includes(".")) {
      url = url + "/";
    }
  }

  return url;
}

window.addEventListener("message", function (event) {
  const data = event.data;

  switch (data.type) {
    case "openTablet":
      if (data.tabletType === "FireTab") {
        // Use the dedicated FireTab open function
        openFireTablet(data.characterData, data.url);
      }
      break;

    case "setCharacterData":
      setCharacterData(data.characterData);
      break;

    case "closeTablet":
      // Only close FireTab here
      if (!data.tabletType || data.tabletType === "FireTab") {
        if (DEBUG)
          console.log(
            "[FireTab] closeTablet message received for:",
            data.tabletType
          );
        closeTablet();
      }
      break;
  }
});

function openFireTablet(charData, url) {
  // Prevent double-opening
  if (isTabletOpen) {
    if (DEBUG)
      console.log(
        "[FireTab] Tablet already opening/open, ignoring duplicate call"
      );
    return;
  }

  characterData = charData;
  isTabletOpen = true;

  if (DEBUG) console.log("[FireTab] openFireTablet called with URL:", url);

  if (url) {
    FireTabURL = ensureHttps(url);
    if (DEBUG) console.log("[FireTab] FireTabURL set to:", FireTabURL);
  }

  const tabletContainer = document.getElementById("firetabContainer");
  // FireTab uses firetabLoadingScreen, but script looks for loadingScreen, so create an alias
  let loadingScreen = document.getElementById("firetabLoadingScreen");
  if (!loadingScreen) {
    loadingScreen = document.querySelector("#firetabContainer .loading-screen");
  }
  const tabletScreen = document.getElementById("firetabScreen");

  if (tabletContainer) {
    tabletContainer.style.display = "flex";
    document.body.style.cursor = "default";
    tabletContainer.style.cursor = "default";
  }

  if (tabletScreen && tabletScreen.src && tabletScreen.src !== "") {
    if (DEBUG) console.log("[FireTab] Restoring tablet with existing content");

    if (tabletScreen.src.toLowerCase().startsWith("http://")) {
      const secureUrl = tabletScreen.src.replace(/^http:\/\//i, "https://");
      if (DEBUG)
        console.warn(
          "[FireTab] ⚠️  Iframe had insecure URL, fixing:",
          tabletScreen.src,
          "→",
          secureUrl
        );
      tabletScreen.src = secureUrl;
    }

    if (DEBUG)
      console.log(
        "[FireTab] Hiding loading screen, showing iframe (restore path)"
      );
    if (loadingScreen) loadingScreen.style.display = "none";
    tabletScreen.style.display = "block";
    return;
  }

  if (DEBUG) {
    console.log("[FireTab] SHOWING loading screen, hiding iframe");
    if (loadingScreen) {
      console.log("[FireTab] loadingScreen element found:", loadingScreen);
      console.log(
        "[FireTab] loadingScreen current display:",
        window.getComputedStyle(loadingScreen).display
      );
    } else {
      console.error("[FireTab] loadingScreen element NOT FOUND!");
    }
  }
  if (loadingScreen) {
    loadingScreen.style.display = "flex";
    if (DEBUG)
      console.log(
        "[FireTab] loadingScreen display set to flex, new value:",
        window.getComputedStyle(loadingScreen).display
      );
  }
  if (tabletScreen) tabletScreen.style.display = "none";

  if (charData && charData.firstName && charData.lastName) {
    loadFireTab(charData);
  } else {
    const loadingText = document.getElementById("firetabLoadingText");
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
          loadFireTab(data);
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
  if (DEBUG) console.log("[FireTab] Setting character data:", charData);
  characterData = charData;

  if (isTabletOpen && charData && charData.firstName && charData.lastName) {
    loadFireTab(charData);
  }
}

function loadFireTab(charData) {
  const loadingText = document.getElementById("firetabLoadingText");
  if (loadingText) {
    loadingText.textContent =
      "Lade FireTab für " +
      charData.firstName +
      " " +
      charData.lastName +
      "...";
  }

  const url = ensureHttps(FireTabURL);
  if (DEBUG) console.log("[FireTab] loadFireTab: Final URL to load:", url);

  const iframe = document.getElementById("firetabScreen");
  const loadingScreen = document.getElementById("firetabLoadingScreen");

  if (!iframe) {
    if (DEBUG)
      console.error("[FireTab] Could not find iframe element 'firetabScreen'");
    return;
  }

  if (!loadingScreen) {
    if (DEBUG)
      console.warn(
        "[FireTab] Could not find loading screen element 'firetabLoadingScreen'"
      );
  }

  if (DEBUG) console.log("[FireTab] Setting iframe.src to:", url);

  // Set onload handler BEFORE setting src
  iframe.onload = () => {
    if (DEBUG) console.log("[FireTab] Iframe loaded successfully");
    if (loadingScreen) {
      loadingScreen.style.display = "none";
      if (DEBUG) console.log("[FireTab] Loading screen hidden via onload");
    }
    iframe.style.display = "block";
  };

  iframe.onerror = () => {
    if (DEBUG) console.error("[FireTab] Error loading iframe");
    if (loadingScreen) {
      const text = document.getElementById("firetabLoadingText");
      if (text) text.textContent = "Fehler beim Laden der FireTab";
    }
  };

  // Set src AFTER handlers are registered
  iframe.src = url;

  // Fallback timeout
  setTimeout(() => {
    if (loadingScreen && loadingScreen.style.display !== "none") {
      if (DEBUG)
        console.log("[FireTab] Timeout: forcing loading screen to hide");
      loadingScreen.style.display = "none";
      iframe.style.display = "block";
    }
  }, 3000);
}

function closeTablet() {
  if (!isTabletOpen) return;

  if (DEBUG) console.log("[FireTab] Closing FireTab tablet UI");

  isTabletOpen = false;
  const tabletContainer = document.getElementById("firetabContainer");
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

function goHome() {
  if (DEBUG) console.log("[FireTab] Navigating to home");
  const iframe = document.getElementById("firetabScreen");
  if (iframe && FireTabURL) {
    iframe.src = ensureHttps(FireTabURL);
  }
}

document.addEventListener("keydown", function (event) {
  if (event.key === "Escape") {
    const tabletContainer = document.getElementById("firetabContainer");
    if (tabletContainer && tabletContainer.style.display === "flex") {
      closeTablet();
    }
  }
});
