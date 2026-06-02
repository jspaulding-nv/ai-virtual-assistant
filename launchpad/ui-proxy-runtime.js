;(function () {
  if (typeof window === "undefined" || window.__aivaLaunchPadHeadProxyRuntime) {
    return;
  }
  window.__aivaLaunchPadHeadProxyRuntime = true;

  var match = window.location.pathname.match(/^(.*\/(?:coder\/)?proxy\/\d+\/)/);
  var proxyPrefix = match ? match[1] : "";
  if (!proxyPrefix) {
    return;
  }

  var PRODUCT_IMAGE_ATTR = "data-aiva-suppressed-product-image";
  var PRODUCT_ICON_ATTR = "data-aiva-product-icon";
  var PRODUCT_PLACEHOLDER =
    "data:image/svg+xml;charset=utf-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%221%22%20height%3D%221%22%2F%3E";
  var PRODUCT_WORDS =
    /nvidia|geforce|rtx|shield|remote|tee|shirt|polo|jacket|vest|hoodie|jogger|pants|beanie|knit|cotton|lululemon|nike|north face|marine layer|mouse|mousepad|computer|care|kit|jetson|developer|gpu|graphics|mug|cup|coffee|ceramic|cooler|laptop|sleeve|case|bag/i;
  var iconPatchScheduled = false;
  var iconRules = [
    { pattern: /geforce|rtx|gpu|graphics/i, icon: "fa-microchip", label: "GPU" },
    { pattern: /jetson|developer|nano/i, icon: "fa-microchip", label: "Device" },
    { pattern: /laptop|sleeve|case|bag|timbuk2/i, icon: "fa-laptop", label: "Laptop accessory" },
    { pattern: /cooler|igloo|cold|insulation|seadrift/i, icon: "fa-snowflake", label: "Cooler" },
    { pattern: /jogger|pants|lululemon|activewear/i, icon: "fa-person-running", label: "Activewear" },
    { pattern: /beanie|knit|cap|hat/i, icon: "fa-hat-wizard", label: "Headwear" },
    { pattern: /mug|cup|coffee|ceramic|drink|beverage/i, icon: "fa-mug-hot", label: "Mug" },
    {
      pattern:
        /tee|shirt|apparel|unisex|hoodie|jacket|vest|polo|full zip|cotton|polyester|rayon|north face|marine layer|nike/i,
      icon: "fa-shirt",
      label: "Apparel",
    },
    { pattern: /mouse|mousepad|keyboard/i, icon: "fa-computer-mouse", label: "Accessory" },
    { pattern: /shield|remote|tv|controller/i, icon: "fa-gamepad", label: "Device" },
    { pattern: /care|kit|clean|sticker|webcam/i, icon: "fa-screwdriver-wrench", label: "Kit" },
  ];

  function isExternalProductImageUrl(value) {
    return /^https?:\/\/(?:www\.)?gear\.nvidia\.com\/GetImage\.ashx/i.test(String(value || ""));
  }

  function normalizeUrl(value) {
    if (typeof value !== "string") {
      return value;
    }

    if (isExternalProductImageUrl(value)) {
      return PRODUCT_PLACEHOLDER;
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

  function normalizeSrcset(value) {
    if (typeof value !== "string") {
      return value;
    }

    if (/gear\.nvidia\.com\/GetImage\.ashx/i.test(value)) {
      return "";
    }

    return value
      .split(",")
      .map(function (candidate) {
        var trimmed = candidate.trim();
        if (!trimmed) {
          return candidate;
        }

        var parts = trimmed.split(/\s+/);
        parts[0] = normalizeUrl(parts[0]);
        return parts.join(" ");
      })
      .join(", ");
  }

  function normalizeCss(value) {
    if (typeof value !== "string") {
      return value;
    }

    return value.replace(/url\((["']?)([^"')]+)\1\)/g, function (cssMatch, quote, url) {
      var nextUrl = normalizeUrl(url);
      return nextUrl === url ? cssMatch : "url(" + quote + nextUrl + quote + ")";
    });
  }

  function markSuppressedProductImage(element) {
    if (!element || !element.tagName || element.tagName.toUpperCase() !== "IMG") {
      return;
    }

    element.setAttribute(PRODUCT_IMAGE_ATTR, "true");
    scheduleProductIconPatch();
  }

  function scheduleProductIconPatch() {
    if (iconPatchScheduled) {
      return;
    }

    iconPatchScheduled = true;
    window.requestAnimationFrame(function () {
      iconPatchScheduled = false;
      replaceSuppressedProductImages();
    });
  }

  function ensureProductIconStyles() {
    if (!document.head) {
      return;
    }

    if (!document.getElementById("aiva-fontawesome-product-icons")) {
      var link = document.createElement("link");
      link.id = "aiva-fontawesome-product-icons";
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
        "width:88px;min-width:88px;height:88px;border-radius:8px;position:relative;" +
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

  function replaceSuppressedProductImages() {
    if (!document.documentElement) {
      return;
    }

    var images = document.querySelectorAll(
      "img[" + PRODUCT_IMAGE_ATTR + "]:not([" + PRODUCT_ICON_ATTR + "])"
    );
    for (var i = 0; i < images.length; i += 1) {
      var image = images[i];
      var text = textForImage(image);
      if (!PRODUCT_WORDS.test(text) && !isExternalProductImageUrl(image.getAttribute("src"))) {
        continue;
      }

      ensureProductIconStyles();
      var icon = iconForText(text);
      var wrapper = document.createElement("span");
      var glyph = document.createElement("i");

      wrapper.className = "aiva-product-icon-fallback";
      wrapper.setAttribute("role", "img");
      wrapper.setAttribute("aria-label", icon.label);
      wrapper.setAttribute("data-label", icon.label);
      wrapper.setAttribute(PRODUCT_ICON_ATTR, "true");

      glyph.className = "fa-solid " + icon.icon;
      glyph.setAttribute("aria-hidden", "true");
      wrapper.appendChild(glyph);

      image.setAttribute(PRODUCT_ICON_ATTR, "true");
      image.replaceWith(wrapper);
    }
  }

  if (typeof window.fetch === "function") {
    var originalFetch = window.fetch;
    window.fetch = function (input, init) {
      if (typeof input === "string") {
        return originalFetch.call(this, normalizeUrl(input), init);
      }

      if (typeof URL !== "undefined" && input instanceof URL) {
        var normalizedUrl = normalizeUrl(input.href);
        if (normalizedUrl !== input.href) {
          return originalFetch.call(this, normalizedUrl, init);
        }
      }

      if (input && typeof input.url === "string") {
        var nextUrl = normalizeUrl(input.url);
        if (nextUrl !== input.url && typeof Request !== "undefined") {
          return originalFetch.call(this, new Request(nextUrl, input), init);
        }
      }

      return originalFetch.call(this, input, init);
    };
  }

  if (window.XMLHttpRequest && XMLHttpRequest.prototype.open) {
    var originalOpen = XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open = function (method, url) {
      if (typeof url === "string" || (typeof URL !== "undefined" && url instanceof URL)) {
        arguments[1] = normalizeUrl(String(url));
      }
      return originalOpen.apply(this, arguments);
    };
  }

  if (window.Element && Element.prototype.setAttribute) {
    var originalSetAttribute = Element.prototype.setAttribute;
    Element.prototype.setAttribute = function (name, value) {
      var lowerName = String(name || "").toLowerCase();

      if (lowerName === "srcset" && typeof value === "string") {
        if (/gear\.nvidia\.com\/GetImage\.ashx/i.test(value)) {
          markSuppressedProductImage(this);
        }
        return originalSetAttribute.call(this, name, normalizeSrcset(value));
      }

      if ((lowerName === "src" || lowerName === "href") && typeof value === "string") {
        if (isExternalProductImageUrl(value)) {
          markSuppressedProductImage(this);
        }
        return originalSetAttribute.call(this, name, normalizeUrl(value));
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
        if (isExternalProductImageUrl(value)) {
          markSuppressedProductImage(this);
        }
        return descriptor.set.call(this, normalizeUrl(value));
      },
    });
  }

  function patchSrcsetProperty(proto) {
    if (!proto) {
      return;
    }

    var descriptor = Object.getOwnPropertyDescriptor(proto, "srcset");
    if (!descriptor || typeof descriptor.set !== "function" || typeof descriptor.get !== "function") {
      return;
    }

    Object.defineProperty(proto, "srcset", {
      configurable: descriptor.configurable,
      enumerable: descriptor.enumerable,
      get: descriptor.get,
      set: function (value) {
        if (/gear\.nvidia\.com\/GetImage\.ashx/i.test(String(value || ""))) {
          markSuppressedProductImage(this);
        }
        return descriptor.set.call(this, normalizeSrcset(value));
      },
    });
  }

  patchUrlProperty(typeof HTMLImageElement !== "undefined" ? HTMLImageElement.prototype : null, "src");
  patchUrlProperty(typeof HTMLScriptElement !== "undefined" ? HTMLScriptElement.prototype : null, "src");
  patchUrlProperty(typeof HTMLLinkElement !== "undefined" ? HTMLLinkElement.prototype : null, "href");
  patchUrlProperty(
    typeof HTMLAnchorElement !== "undefined" ? HTMLAnchorElement.prototype : null,
    "href"
  );
  patchSrcsetProperty(typeof HTMLImageElement !== "undefined" ? HTMLImageElement.prototype : null);
  patchSrcsetProperty(typeof HTMLSourceElement !== "undefined" ? HTMLSourceElement.prototype : null);

  if (window.CSSStyleDeclaration && CSSStyleDeclaration.prototype.setProperty) {
    var originalSetProperty = CSSStyleDeclaration.prototype.setProperty;
    CSSStyleDeclaration.prototype.setProperty = function (propertyName, value, priority) {
      return originalSetProperty.call(this, propertyName, normalizeCss(value), priority);
    };
  }

  function patchExistingElements() {
    if (!document.documentElement) {
      return;
    }

    var elements = document.querySelectorAll("[src],[href],[srcset],[style]");
    for (var i = 0; i < elements.length; i += 1) {
      ["src", "href"].forEach(function (attr) {
        if (!elements[i].hasAttribute(attr)) {
          return;
        }

        var value = elements[i].getAttribute(attr);
        if (isExternalProductImageUrl(value)) {
          markSuppressedProductImage(elements[i]);
        }

        var nextValue = normalizeUrl(value);
        if (nextValue !== value) {
          elements[i].setAttribute(attr, nextValue);
        }
      });

      if (elements[i].hasAttribute("srcset")) {
        var srcset = elements[i].getAttribute("srcset");
        if (/gear\.nvidia\.com\/GetImage\.ashx/i.test(srcset)) {
          markSuppressedProductImage(elements[i]);
        }

        var nextSrcset = normalizeSrcset(srcset);
        if (nextSrcset !== srcset) {
          elements[i].setAttribute("srcset", nextSrcset);
        }
      }

      var style = elements[i].getAttribute("style");
      var nextStyle = normalizeCss(style);
      if (nextStyle !== style) {
        elements[i].setAttribute("style", nextStyle);
      }
    }

    replaceSuppressedProductImages();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", patchExistingElements);
  } else {
    patchExistingElements();
  }

  new MutationObserver(function () {
    window.requestAnimationFrame(patchExistingElements);
  }).observe(document.documentElement, {
    childList: true,
    subtree: true,
    attributes: true,
    attributeFilter: ["src", "href", "srcset", "style"],
  });
})();
