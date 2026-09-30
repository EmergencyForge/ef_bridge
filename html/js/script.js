// eNOTF tablet UI. Global state (DEBUG, isTabletOpen, characterData)
// lives in master.js.
let IntraURL = null;
let navigationHistory = [];
let historyIndex = -1;
let currentUrl = "";

// NUI iframes refuse plain HTTP, so normalize every URL to HTTPS
function ensureHttps(url) {
  if (!url) {
    if (DEBUG) console.warn("[ignisTab] ensureHttps: URL is null or undefined");
    return url;
  }

  const originalUrl = url;
  url = url.trim();

  if (url.toLowerCase().startsWith("http://")) {
    url = url.replace(/^http:\/\//i, "https://");
    if (DEBUG)
      console.warn("[ignisTab] URL converted from HTTP to HTTPS:", originalUrl, "→", url);
  } else if (
    !url.toLowerCase().startsWith("https://") &&
    !url.toLowerCase().startsWith("//")
  ) {
    url = "https://" + url;
    if (DEBUG)
      console.log("[ignisTab] Added HTTPS prefix:", originalUrl, "→", url);
  }

  // add a trailing slash to directory-looking paths to avoid HTTP redirects
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
  if (fromTabletFrame(event)) return; // see master.js

  switch (data.type) {
    case "openTablet":
      // FireTab is handled by firetab.js
      if (data.tabletType === "eNOTF") {
        openTablet(data.characterData, data.url);
      }
      break;

    case "setCharacterData":
      setCharacterData(data.characterData);
      break;

    // closeTablet messages are handled by master.js
  }
});

function openTablet(charData, url) {
  if (isTabletOpen) {
    if (DEBUG)
      console.log("[ignisTab] Tablet already opening/open, ignoring duplicate call");
    return;
  }

  characterData = charData;
  isTabletOpen = true;

  if (url) {
    IntraURL = ensureHttps(url);
  }

  const tabletContainer = document.getElementById("tabletContainer");
  const loadingScreen = document.getElementById("loadingScreen");
  const tabletScreen = document.getElementById("tabletScreen");

  if (tabletContainer) {
    tabletContainer.style.display = "flex";
    document.body.style.cursor = "default";
    tabletContainer.style.cursor = "default";
  }

  // reopening with content still loaded: just show it again
  if (tabletScreen && tabletScreen.src && tabletScreen.src !== "") {
    if (tabletScreen.src.toLowerCase().startsWith("http://")) {
      tabletScreen.src = tabletScreen.src.replace(/^http:\/\//i, "https://");
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
    // no character data passed along, ask the client for it
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

  addToHistory(url);
  currentUrl = url;
  updatePageTitle("ignis Verwaltungsportal");

  const iframe = document.getElementById("tabletScreen");
  const loadingScreen = document.getElementById("loadingScreen");

  if (iframe) {
    // handlers first, then src
    iframe.onload = () => {
      if (loadingScreen) loadingScreen.style.display = "none";
      iframe.style.display = "block";
      updateNavigationButtons();
    };

    // some installs redirect to HTTP; force it back to HTTPS
    const checkIframeSrc = () => {
      try {
        const currentSrc = iframe.src;
        if (currentSrc && currentSrc.toLowerCase().startsWith("http://")) {
          iframe.src = currentSrc.replace(/^http:\/\//i, "https://");
        }
      } catch (e) {
        // cross-origin, nothing we can do
      }
    };

    setTimeout(checkIframeSrc, 500);
    setTimeout(checkIframeSrc, 1500);

    // hide the loading screen after 3s even if onload never fires
    setTimeout(() => {
      if (loadingScreen && loadingScreen.style.display !== "none") {
        loadingScreen.style.display = "none";
        iframe.style.display = "block";
        updateNavigationButtons();
      }
    }, 3000);

    iframe.src = url;
  }
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

function goBackENOTF() {
  if (!isTabletOpen || historyIndex <= 0) {
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
  }
}

function goHomeENOTF() {
  if (!isTabletOpen || !characterData) {
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
  updatePageTitle("ignis Verwaltungsportal");
}

function addEventListeners() {
  document.addEventListener("contextmenu", function (e) {
    e.preventDefault();
    return false;
  });

  document.addEventListener("mousemove", function () {
    if (isTabletOpen) {
      document.body.style.cursor = "default";
    }
  });

  // ESC also closes from within the NUI, matching FireTab
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
