const fs = require("fs");
const path = require("path");

const roots = ["/app", "/opt", "/usr/share/nginx/html", "/usr/src/app"].filter((root) =>
  fs.existsSync(root)
);
const extensions = new Set([".html", ".js", ".mjs", ".css"]);

function isPatchableClientAsset(filePath) {
  const normalized = path.normalize(filePath);

  if (normalized.includes(`${path.sep}.next${path.sep}server${path.sep}`)) {
    return false;
  }

  if (normalized.includes(`${path.sep}.next${path.sep}cache${path.sep}`)) {
    return false;
  }

  return (
    normalized.includes(`${path.sep}.next${path.sep}static${path.sep}`) ||
    normalized.includes(`${path.sep}_next${path.sep}static${path.sep}`) ||
    (path.extname(normalized) === ".html" && !normalized.includes(`${path.sep}.next${path.sep}`))
  );
}

function walk(dir, visitor) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      if (entry.name === "node_modules") {
        continue;
      }
      walk(fullPath, visitor);
    } else {
      visitor(fullPath);
    }
  }
}

function isNextStaticCss(filePath) {
  const normalized = path.normalize(filePath);
  return (
    path.extname(normalized) === ".css" &&
    (normalized.includes(`${path.sep}.next${path.sep}static${path.sep}css${path.sep}`) ||
      normalized.includes(`${path.sep}_next${path.sep}static${path.sep}css${path.sep}`))
  );
}

function rewriteCssAssetPaths(source) {
  let next = source;

  next = next.replace(/url\((["']?)\/_next\/static\/media\//g, "url($1../media/");
  next = next.replace(/url\((["']?)\.\/_next\/static\/media\//g, "url($1../media/");
  next = next.replace(/url\((["']?)_next\/static\/media\//g, "url($1../media/");

  return next;
}

function rewriteAbsoluteSameOriginPaths(source, filePath) {
  if (isNextStaticCss(filePath)) {
    return rewriteCssAssetPaths(source);
  }

  let next = source;

  // The code-server /proxy/<port>/ endpoint strips the proxy prefix before
  // forwarding to the app. Root-relative browser asset requests skip the proxy,
  // so make browser-facing Next.js static paths relative instead.
  next = next.replace(/(["'`])\/_next\//g, "$1./_next/");
  next = next.replace(/(\\["'`])\/_next\//g, "$1./_next/");
  next = next.replace(/\\\/_next\//g, ".\\/_next/");
  next = next.replace(/(url\()\/_next\//g, "$1./_next/");

  next = next.replace(/(["'`])\/favicon\.ico/g, "$1./favicon.ico");
  next = next.replace(/(\\["'`])\/favicon\.ico/g, "$1./favicon.ico");
  next = next.replace(/\\\/favicon\.ico/g, ".\\/favicon.ico");

  next = next.replace(/(["'`])\/artifacts\//g, "$1./artifacts/");
  next = next.replace(/(\\["'`])\/artifacts\//g, "$1./artifacts/");
  next = next.replace(/\\\/artifacts\//g, ".\\/artifacts/");

  next = next.replace(/(["'`])\/temp_image\.jpg/g, "$1./temp_image.jpg");
  next = next.replace(/(\\["'`])\/temp_image\.jpg/g, "$1./temp_image.jpg");
  next = next.replace(/\\\/temp_image\.jpg/g, ".\\/temp_image.jpg");

  return next;
}

let patchedFiles = 0;
let replacementCount = 0;

for (const root of roots) {
  walk(root, (filePath) => {
    if (!extensions.has(path.extname(filePath))) {
      return;
    }

    if (!isPatchableClientAsset(filePath)) {
      return;
    }

    let source;
    try {
      source = fs.readFileSync(filePath, "utf8");
    } catch {
      return;
    }

    const next = rewriteAbsoluteSameOriginPaths(source, filePath);
    if (next === source) {
      return;
    }

    const matches = source.match(/\/_next\/|\/favicon\.ico|\/artifacts\/|\/temp_image\.jpg/g);
    replacementCount += matches ? matches.length : 1;
    fs.writeFileSync(filePath, next);
    patchedFiles += 1;
  });
}

if (patchedFiles === 0) {
  throw new Error("Unable to find Next.js assets to make code-server proxy-aware.");
}

console.log(
  `Patched ${patchedFiles} files and ${replacementCount} URLs for code-server proxy support.`
);
