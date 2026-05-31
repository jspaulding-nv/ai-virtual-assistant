
;(function () {
  if (typeof window === "undefined" || window.__aivaProductIconFallback) {
    return;
  }
  window.__aivaProductIconFallback = true;
  console.info("AIVA product icon fallback loaded");

  var FA_CSS_ID = "aiva-fontawesome-product-icons";
  var PATCHED_ATTR = "data-aiva-product-icon";
  var WATCHED_ATTR = "data-aiva-product-icon-watched";
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

      links[i].removeAttribute("href");
      links[i].removeAttribute("target");
      links[i].removeAttribute("rel");
      links[i].setAttribute("role", "text");
      links[i].setAttribute("aria-disabled", "true");
      links[i].style.cursor = "default";
    }
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

  new MutationObserver(function () {
    window.requestAnimationFrame(patchAll);
  }).observe(document.documentElement, { childList: true, subtree: true });
})();
