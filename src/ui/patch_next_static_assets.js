const crypto = require("crypto");
const fs = require("fs");
const path = require("path");

const fallbackPath = "/tmp/product_icon_fallback.js";
const fallbackSource = fs.readFileSync(fallbackPath, "utf8");
const hash = crypto.createHash("sha256").update(fallbackSource).digest("hex").slice(0, 12);
const fallbackChunk = `static/chunks/aiva-product-icon-fallback-${hash}.js`;
const roots = ["/app", "/opt", "/usr/share/nginx/html", "/usr/src/app"].filter((root) =>
  fs.existsSync(root)
);

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

function findNextDirs(root) {
  const dirs = [];
  walk(root, (filePath) => {
    if (filePath.endsWith(path.join(".next", "build-manifest.json"))) {
      dirs.push(path.dirname(filePath));
    }
  });
  return [...new Set(dirs)];
}

function appendToChunkArrays(value) {
  if (Array.isArray(value)) {
    const hasNextChunk = value.some(
      (item) => typeof item === "string" && item.startsWith("static/chunks/")
    );
    if (hasNextChunk && !value.includes(fallbackChunk)) {
      value.push(fallbackChunk);
    }
    return;
  }

  if (!value || typeof value !== "object") {
    return;
  }

  for (const child of Object.values(value)) {
    appendToChunkArrays(child);
  }
}

function patchJsonManifest(filePath) {
  const manifest = JSON.parse(fs.readFileSync(filePath, "utf8"));
  appendToChunkArrays(manifest);
  fs.writeFileSync(filePath, JSON.stringify(manifest));
}

function patchJsManifest(filePath) {
  let source = fs.readFileSync(filePath, "utf8");
  if (source.includes(fallbackChunk)) {
    return;
  }

  source = source.replace(
    /((?:static\/chunks\/[^"'`]+?\.js)(?=["'`]))/,
    `$1","${fallbackChunk}`
  );
  fs.writeFileSync(filePath, source);
}

let nextDirCount = 0;
for (const root of roots) {
  for (const nextDir of findNextDirs(root)) {
    nextDirCount += 1;
    const staticChunkDir = path.join(nextDir, "static", "chunks");
    fs.mkdirSync(staticChunkDir, { recursive: true });
    fs.writeFileSync(path.join(staticChunkDir, path.basename(fallbackChunk)), fallbackSource);

    walk(nextDir, (filePath) => {
      if (/manifest.*\.json$/.test(path.basename(filePath))) {
        try {
          patchJsonManifest(filePath);
        } catch (error) {
          // Some manifests are not build asset manifests. Leave them alone.
        }
      } else if (/manifest.*\.js$/.test(path.basename(filePath))) {
        patchJsManifest(filePath);
      }
    });
  }
}

if (nextDirCount === 0) {
  throw new Error("Unable to find a Next.js .next directory to patch.");
}

console.log(`Patched ${nextDirCount} Next.js build(s) with ${fallbackChunk}`);
