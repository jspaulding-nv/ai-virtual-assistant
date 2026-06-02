
;(function () {
  if (typeof window === "undefined" || window.__aivaProductIconFallback) {
    return;
  }
  window.__aivaProductIconFallback = true;
  console.info("AIVA product icon fallback loaded");

  var FA_CSS_ID = "aiva-fontawesome-product-icons";
  var PATCHED_ATTR = "data-aiva-product-icon";
  var WATCHED_ATTR = "data-aiva-product-icon-watched";
  var DISABLED_TAG_ATTR = "data-aiva-disabled-tag";
  var LINK_CACHE_BUSTER_ATTR = "data-aiva-launchpad-cache-buster";
  var TAG_TEXT =
    /^(agent blueprint|blueprint|customer service|retrieval-augmented generation|contact center)$/i;
  var MODEL_LABELS = [
    {
      pattern: /LLAMA[\s._-]*3[\s._-]*1[\s._-]*70B[\s._-]*INSTRUCT/gi,
      label: "NEMOTRON-3-NANO-30B-A3B",
    },
    {
      pattern: /NV[\s._-]*RERANKQA[\s._-]*MISTRAL[\s._-]*4B[\s._-]*V3/gi,
      label: "LLAMA-NEMOTRON-RERANK-1B-V2",
    },
    {
      pattern: /NV[\s._-]*EMBEDQA[\s._-]*E5[\s._-]*V5/gi,
      label: "LLAMA-NEMOTRON-EMBED-1B-V2",
    },
  ];
  var PRODUCT_WORDS =
    /nvidia|geforce|rtx|shield|remote|tee|shirt|polo|jacket|vest|hoodie|jogger|pants|beanie|knit|cotton|lululemon|nike|north face|marine layer|mouse|mousepad|computer|care|kit|jetson|developer|gpu|graphics|mug|cup|coffee|ceramic|cooler|laptop|sleeve|case|bag/i;
  var proxyPrefix = getCodeServerProxyPrefix();

  var iconRules = [
    { pattern: /geforce|rtx|gpu|graphics/i, icon: "fa-microchip", label: "GPU" },
    { pattern: /jetson|developer|nano/i, icon: "fa-microchip", label: "Device" },
    { pattern: /laptop|sleeve|case|bag|timbuk2/i, icon: "fa-laptop", label: "Laptop accessory" },
    { pattern: /cooler|igloo|cold|insulation|seadrift/i, icon: "fa-snowflake", label: "Cooler" },
    { pattern: /jogger|pants|lululemon|activewear/i, icon: "fa-person-running", label: "Activewear" },
    { pattern: /beanie|knit|cap|hat/i, icon: "fa-hat-wizard", label: "Headwear" },
    { pattern: /mug|cup|coffee|ceramic|drink|beverage/i, icon: "fa-mug-hot", label: "Mug" },
    { pattern: /tee|shirt|apparel|unisex|hoodie|jacket|vest|polo|full zip|cotton|polyester|rayon|north face|marine layer|nike/i, icon: "fa-shirt", label: "Apparel" },
    { pattern: /mouse|mousepad|keyboard/i, icon: "fa-computer-mouse", label: "Accessory" },
    { pattern: /shield|remote|tv|controller/i, icon: "fa-gamepad", label: "Device" },
    { pattern: /care|kit|clean|sticker|webcam/i, icon: "fa-screwdriver-wrench", label: "Kit" },
  ];

  function getCodeServerProxyPrefix() {
    var match = window.location.pathname.match(/^(.*\/(?:coder\/)?proxy\/\d+\/)/);
    return match ? match[1] : "";
  }

  function normalizeProxyAssetUrl(value) {
    if (!proxyPrefix || typeof value !== "string") {
      return value;
    }

    var nextValue = value.replace(
      /^https:\/\/assets\.ngc\.nvidia\.com\/products\//,
      "/artifacts/products/"
    );

    if (nextValue.indexOf(window.location.origin + "/") === 0) {
      nextValue = nextValue.slice(window.location.origin.length);
    }

    if (/^\/(?:_next|artifacts|api)\//.test(nextValue) || nextValue === "/temp_image.jpg") {
      return proxyPrefix + nextValue.replace(/^\//, "");
    }

    return value;
  }

  function patchProxyAssetRuntime() {
    if (!proxyPrefix || window.__aivaLaunchPadProxyRuntime) {
      return;
    }
    window.__aivaLaunchPadProxyRuntime = true;

    patchFetch();
    patchXhr();
    patchSetAttribute();
    patchUrlProperty(
      typeof HTMLImageElement !== "undefined" ? HTMLImageElement.prototype : null,
      "src"
    );
    patchUrlProperty(
      typeof HTMLScriptElement !== "undefined" ? HTMLScriptElement.prototype : null,
      "src"
    );
    patchUrlProperty(
      typeof HTMLLinkElement !== "undefined" ? HTMLLinkElement.prototype : null,
      "href"
    );
  }

  function patchFetch() {
    if (typeof window.fetch !== "function") {
      return;
    }

    var originalFetch = window.fetch;
    window.fetch = function (input, init) {
      if (typeof input === "string") {
        return originalFetch.call(this, normalizeProxyAssetUrl(input), init);
      }

      if (input && typeof input.url === "string") {
        var nextUrl = normalizeProxyAssetUrl(input.url);
        if (nextUrl !== input.url && typeof Request !== "undefined") {
          return originalFetch.call(this, new Request(nextUrl, input), init);
        }
      }

      return originalFetch.call(this, input, init);
    };
  }

  function patchXhr() {
    if (!window.XMLHttpRequest || !XMLHttpRequest.prototype.open) {
      return;
    }

    var originalOpen = XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open = function (method, url) {
      if (typeof url === "string") {
        arguments[1] = normalizeProxyAssetUrl(url);
      }
      return originalOpen.apply(this, arguments);
    };
  }

  function patchSetAttribute() {
    var originalSetAttribute = Element.prototype.setAttribute;
    Element.prototype.setAttribute = function (name, value) {
      var lowerName = String(name || "").toLowerCase();
      if ((lowerName === "src" || lowerName === "href") && typeof value === "string") {
        return originalSetAttribute.call(this, name, normalizeProxyAssetUrl(value));
      }
      return originalSetAttribute.apply(this, arguments);
    };
  }

  function patchUrlProperty(proto, propertyName) {
    if (!proto) {
      return;
    }

    var descriptor = Object.getOwnPropertyDescriptor(proto, propertyName);
    if (!descriptor || typeof descriptor.set !== "function" || typeof descriptor.get !== "function") {
      return;
    }

    Object.defineProperty(proto, propertyName, {
      configurable: descriptor.configurable,
      enumerable: descriptor.enumerable,
      get: descriptor.get,
      set: function (value) {
        return descriptor.set.call(this, normalizeProxyAssetUrl(value));
      },
    });
  }

  function patchProxyAssetElements() {
    if (!proxyPrefix || !document.body) {
      return;
    }

    var elements = document.querySelectorAll("[src],[href]");
    for (var i = 0; i < elements.length; i += 1) {
      ["src", "href"].forEach(function (attr) {
        if (!elements[i].hasAttribute(attr)) {
          return;
        }

        var value = elements[i].getAttribute(attr);
        var nextValue = normalizeProxyAssetUrl(value);
        if (nextValue !== value) {
          elements[i].setAttribute(attr, nextValue);
        }
      });
    }

    var cssLinks = document.querySelectorAll('link[rel="stylesheet"][href*="/_next/static/css/"]');
    for (var j = 0; j < cssLinks.length; j += 1) {
      if (cssLinks[j].hasAttribute(LINK_CACHE_BUSTER_ATTR)) {
        continue;
      }

      cssLinks[j].setAttribute(LINK_CACHE_BUSTER_ATTR, "true");
      cssLinks[j].href =
        cssLinks[j].href + (cssLinks[j].href.indexOf("?") === -1 ? "?" : "&") + "aivaProxy=1";
    }
  }

  function ensureStyles() {
    if (!document.getElementById(FA_CSS_ID)) {
      var link = document.createElement("link");
      link.id = FA_CSS_ID;
      link.rel = "stylesheet";
      link.href = "https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.2/css/all.min.css";
      link.crossOrigin = "anonymous";
      document.head.appendChild(link);
    }

    if (!document.getElementById("aiva-product-icon-style")) {
      var style = document.createElement("style");
      style.id = "aiva-product-icon-style";
      style.textContent =
        ".aiva-product-icon-fallback{" +
        "box-sizing:border-box;display:inline-flex!important;align-items:center;justify-content:center;" +
        "width:88px;min-width:88px;height:88px;border-radius:8px;" +
        "border:1px solid rgba(118,185,0,.38);background:rgba(118,185,0,.08);" +
        "color:#76b900;font-size:34px;line-height:1;margin:0 18px 0 0;vertical-align:middle;" +
        "}" +
        ".aiva-product-icon-fallback .fa-solid{font-size:34px;line-height:1;}" +
        ".aiva-product-icon-fallback::after{content:attr(data-label);position:absolute;opacity:0;pointer-events:none;}";
      document.head.appendChild(style);
    }
  }

  function textForImage(img) {
    var bits = [img.getAttribute("alt") || "", img.getAttribute("title") || ""];
    var parent = img.closest("article,li,[role='listitem'],[class*='card'],[class*='Card'],div");
    if (parent) {
      bits.push(parent.textContent || "");
    }
    return bits.join(" ");
  }

  function iconForText(text) {
    for (var i = 0; i < iconRules.length; i += 1) {
      if (iconRules[i].pattern.test(text)) {
        return iconRules[i];
      }
    }
    return { icon: "fa-box-open", label: "Product" };
  }

  function patchModelLabels() {
    if (!document.body) {
      return;
    }

    var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
    var node;

    while ((node = walker.nextNode())) {
      var value = node.nodeValue;
      var nextValue = replaceModelText(value);

      if (nextValue !== value) {
        node.nodeValue = nextValue;
      }
    }

    var candidates = document.querySelectorAll("span,p,div,strong,b");
    for (var i = 0; i < candidates.length; i += 1) {
      if (candidates[i].children.length > 0) {
        continue;
      }

      var text = candidates[i].textContent;
      var nextText = replaceModelText(text);
      if (nextText !== text) {
        candidates[i].textContent = nextText;
      }
    }
  }

  function disableHeaderTagLinks() {
    var links = document.querySelectorAll("a[href]");

    for (var i = 0; i < links.length; i += 1) {
      var text = (links[i].textContent || "").trim();
      if (!TAG_TEXT.test(text)) {
        continue;
      }

      replaceTagLinkWithText(links[i]);
    }
  }

  function replaceTagLinkWithText(link) {
    if (link.hasAttribute(DISABLED_TAG_ATTR)) {
      return;
    }

    var chip = document.createElement("span");
    var attributes = link.attributes;

    for (var i = 0; i < attributes.length; i += 1) {
      var name = attributes[i].name;
      if (name === "href" || name === "target" || name === "rel") {
        continue;
      }
      chip.setAttribute(name, attributes[i].value);
    }

    chip.setAttribute(DISABLED_TAG_ATTR, "true");
    chip.setAttribute("role", "text");
    chip.setAttribute("aria-disabled", "true");
    chip.style.cursor = "default";
    chip.style.pointerEvents = "none";
    chip.innerHTML = link.innerHTML;

    link.replaceWith(chip);
  }

  function preventHeaderTagNavigation(event) {
    var target = event.target && event.target.closest ? event.target.closest("a") : null;
    if (!target || !TAG_TEXT.test((target.textContent || "").trim())) {
      return;
    }

    event.preventDefault();
    event.stopPropagation();
    event.stopImmediatePropagation();
  }

  function replaceModelText(value) {
    var nextValue = value;

    MODEL_LABELS.forEach(function (replacement) {
      nextValue = nextValue.replace(replacement.pattern, replacement.label);
    });

    return nextValue;
  }

  function isBrokenProductImage(img) {
    if (!img || img.tagName !== "IMG" || img.hasAttribute(PATCHED_ATTR)) {
      return false;
    }

    var src = img.getAttribute("src") || "";
    var text = textForImage(img);
    var isGearStoreImage = /gear\.nvidia\.com\/GetImage/i.test(src);
    if (!isGearStoreImage && !PRODUCT_WORDS.test(text)) {
      return false;
    }

    return !src || (img.complete && img.naturalWidth === 0);
  }

  function replaceImage(img) {
    if (!isBrokenProductImage(img)) {
      return;
    }

    ensureStyles();
    var text = textForImage(img);
    var icon = iconForText(text);
    var wrapper = document.createElement("span");
    var glyph = document.createElement("i");

    wrapper.className = "aiva-product-icon-fallback";
    wrapper.setAttribute("role", "img");
    wrapper.setAttribute("aria-label", icon.label);
    wrapper.setAttribute("data-label", icon.label);
    wrapper.setAttribute(PATCHED_ATTR, "true");

    glyph.className = "fa-solid " + icon.icon;
    glyph.setAttribute("aria-hidden", "true");
    wrapper.appendChild(glyph);

    img.setAttribute(PATCHED_ATTR, "true");
    img.replaceWith(wrapper);
  }

  function patchAll() {
    patchProxyAssetRuntime();
    patchProxyAssetElements();
    patchModelLabels();
    disableHeaderTagLinks();

    var images = document.querySelectorAll("img:not([" + PATCHED_ATTR + "])");
    for (var i = 0; i < images.length; i += 1) {
      replaceImage(images[i]);
      if (!images[i].hasAttribute(PATCHED_ATTR) && !images[i].hasAttribute(WATCHED_ATTR)) {
        images[i].setAttribute(WATCHED_ATTR, "true");
        images[i].addEventListener("error", function (event) {
          replaceImage(event.currentTarget);
        });
      }
    }
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", patchAll);
  } else {
    patchAll();
  }

  document.addEventListener("click", preventHeaderTagNavigation, true);

  new MutationObserver(function () {
    window.requestAnimationFrame(patchAll);
  }).observe(document.documentElement, { childList: true, subtree: true });
})();
