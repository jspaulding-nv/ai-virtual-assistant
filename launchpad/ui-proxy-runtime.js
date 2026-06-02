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

  function normalizeUrl(value) {
    if (typeof value !== "string") {
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

  function normalizeCss(value) {
    if (typeof value !== "string") {
      return value;
    }

    return value.replace(/url\((["']?)([^"')]+)\1\)/g, function (match, quote, url) {
      var nextUrl = normalizeUrl(url);
      return nextUrl === url ? match : "url(" + quote + nextUrl + quote + ")";
    });
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
      if ((lowerName === "src" || lowerName === "href") && typeof value === "string") {
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
        return descriptor.set.call(this, normalizeUrl(value));
      },
    });
  }

  patchUrlProperty(typeof HTMLImageElement !== "undefined" ? HTMLImageElement.prototype : null, "src");
  patchUrlProperty(typeof HTMLScriptElement !== "undefined" ? HTMLScriptElement.prototype : null, "src");
  patchUrlProperty(typeof HTMLLinkElement !== "undefined" ? HTMLLinkElement.prototype : null, "href");

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

    var elements = document.querySelectorAll("[src],[href],[style]");
    for (var i = 0; i < elements.length; i += 1) {
      ["src", "href"].forEach(function (attr) {
        if (!elements[i].hasAttribute(attr)) {
          return;
        }

        var value = elements[i].getAttribute(attr);
        var nextValue = normalizeUrl(value);
        if (nextValue !== value) {
          elements[i].setAttribute(attr, nextValue);
        }
      });

      var style = elements[i].getAttribute("style");
      var nextStyle = normalizeCss(style);
      if (nextStyle !== style) {
        elements[i].setAttribute("style", nextStyle);
      }
    }
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", patchExistingElements);
  } else {
    patchExistingElements();
  }

  new MutationObserver(function () {
    window.requestAnimationFrame(patchExistingElements);
  }).observe(document.documentElement, { childList: true, subtree: true, attributes: true });
})();
