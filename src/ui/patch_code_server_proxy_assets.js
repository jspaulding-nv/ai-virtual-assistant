const fs = require("fs");
const path = require("path");

const roots = ["/app", "/opt", "/usr/share/nginx/html", "/usr/src/app"].filter((root) =>
  fs.existsSync(root)
);
const extensions = new Set([".html", ".js", ".mjs", ".json", ".css"]);

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

function rewriteAbsoluteSameOriginPaths(source) {
  let next = source;

  // The code-server /proxy/<port>/ endpoint strips the proxy prefix before
  // forwarding to the app. Root-relative browser requests skip the proxy, so
  // make Next.js static assets and same-origin API calls relative instead.
  next = next.replace(/(["'`])\/_next\//g, "$1./_next/");
  next = next.replace(/(\\["'`])\/_next\//g, "$1./_next/");
  next = next.replace(/(url\()\/_next\//g, "$1./_next/");

  next = next.replace(/(["'`])\/api(?=\/|["'`?])/g, "$1./api");
  next = next.replace(/(\\["'`])\/api(?=\/|["'`?])/g, "$1./api");

  next = next.replace(/(["'`])\/favicon\.ico/g, "$1./favicon.ico");
  next = next.replace(/(\\["'`])\/favicon\.ico/g, "$1./favicon.ico");

  return next;
}

let patchedFiles = 0;
let replacementCount = 0;

for (const root of roots) {
  walk(root, (filePath) => {
    if (!extensions.has(path.extname(filePath))) {
      return;
    }

    let source;
    try {
      source = fs.readFileSync(filePath, "utf8");
    } catch {
      return;
    }

    const next = rewriteAbsoluteSameOriginPaths(source);
    if (next === source) {
      return;
    }

    const matches = source.match(/\/_next\/|\/api(?=\/|["'`?])|\/favicon\.ico/g);
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
