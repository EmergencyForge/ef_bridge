// FireTab tablet UI. Global state (DEBUG, isTabletOpen, characterData)
// lives in master.js.
let FireTabURL = null;

// NUI iframes refuse plain HTTP, so normalize every URL to HTTPS
function ensureHttpsFireTab(url) {
  if (!url) {
    if (DEBUG) console.warn("[FireTab] ensureHttps: URL is null or undefined");
    return url;
  }

  const originalUrl = url;
  url = url.trim();

  if (url.toLowerCase().startsWith("http://")) {
    url = url.replace(/^http:\/\//i, "https://");
    if (DEBUG)
      console.warn("[FireTab] URL converted from HTTP to HTTPS:", originalUrl, "→", url);
  } else if (
    !url.toLowerCase().startsWith("https://") &&
    !url.toLowerCase().startsWith("//")
  ) {
    url = "https://" + url;
    if (DEBUG)
      console.log("[FireTab] Added HTTPS prefix:", originalUrl, "→", url);
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
      if (data.tabletType === "FireTab") {
        openFireTablet(data.characterData, data.url);
      }
      break;

    case "setCharacterData":
      setFireTabCharacterData(data.characterData);
      break;

    // closeTablet messages are handled by master.js
  }
});

function openFireTablet(charData, url) {
  if (isTabletOpen) {
    if (DEBUG)
      console.log("[FireTab] Tablet already opening/open, ignoring duplicate call");
    return;
  }

  characterData = charData;
  isTabletOpen = true;

  if (url) {
    FireTabURL = ensureHttpsFireTab(url);
  }

  const tabletContainer = document.getElementById("firetabContainer");
  const loadingScreen = document.getElementById("firetabLoadingScreen");
  const tabletScreen = document.getElementById("firetabScreen");

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
    return;
  }

  if (loadingScreen) loadingScreen.style.display = "flex";
  if (tabletScreen) tabletScreen.style.display = "none";

  if (charData && charData.firstName && charData.lastName) {
    loadFireTab(charData);
  } else {
    // no character data passed along, ask the client for it
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

function setFireTabCharacterData(charData) {
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

  const url = ensureHttpsFireTab(FireTabURL);

  const iframe = document.getElementById("firetabScreen");
  const loadingScreen = document.getElementById("firetabLoadingScreen");

  if (!iframe) {
    if (DEBUG)
      console.error("[FireTab] Could not find iframe element 'firetabScreen'");
    return;
  }

  // handlers first, then src
  iframe.onload = () => {
    if (loadingScreen) loadingScreen.style.display = "none";
    iframe.style.display = "block";
  };

  iframe.onerror = () => {
    if (loadingText) loadingText.textContent = "Fehler beim Laden der FireTab";
  };

  iframe.src = url;

  // hide the loading screen after 3s even if onload never fires
  setTimeout(() => {
    if (loadingScreen && loadingScreen.style.display !== "none") {
      loadingScreen.style.display = "none";
      iframe.style.display = "block";
    }
  }, 3000);
}

// Home button target while FireTab is open (dispatched via master.js)
function goHomeFireTab() {
  const iframe = document.getElementById("firetabScreen");
  if (iframe && FireTabURL) {
    iframe.src = ensureHttpsFireTab(FireTabURL);
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
