// Renders the PNG/ICO app icons from public/icon.svg and public/favicon.svg.
// Run after editing either SVG:  cd frontend && node scripts/make-icons.mjs
// Uses the Chromium that Playwright already installs for the e2e tests; no extra dependencies.
import { chromium } from "@playwright/test";
import { readFile, writeFile, copyFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";

const pub = (f) => fileURLToPath(new URL(`../public/${f}`, import.meta.url));
const ENV_BG = "#071640"; // night top band: behind icons that can't be transparent

const browser = await chromium.launch();
const page = await browser.newPage();

/** Rasterise an SVG at size×size. `inset` shrinks the art onto a solid background (maskable / apple-touch). */
async function render(svgFile, size, { background = null, inset = 0 } = {}) {
  const svg = await readFile(pub(svgFile), "utf8");
  const art = size - 2 * inset;
  await page.setViewportSize({ width: size, height: size });
  await page.setContent(
    `<body style="margin:0;background:${background ?? "transparent"}">` +
      `<img style="display:block;margin:${inset}px;width:${art}px;height:${art}px" src="data:image/svg+xml;base64,${Buffer.from(svg).toString("base64")}"></body>`,
  );
  await page.locator("img").evaluate((img) => img.decode());
  return page.screenshot({ omitBackground: !background, clip: { x: 0, y: 0, width: size, height: size } });
}

/** An .ico holding PNG images (supported by every current browser and OS). */
function ico(pngs) {
  const header = Buffer.alloc(6 + 16 * pngs.length);
  header.writeUInt16LE(0, 0); header.writeUInt16LE(1, 2); header.writeUInt16LE(pngs.length, 4);
  let offset = header.length;
  pngs.forEach(({ size, png }, i) => {
    const e = 6 + 16 * i;
    header.writeUInt8(size >= 256 ? 0 : size, e); header.writeUInt8(size >= 256 ? 0 : size, e + 1);
    header.writeUInt16LE(1, e + 4); header.writeUInt16LE(32, e + 6);
    header.writeUInt32LE(png.length, e + 8); header.writeUInt32LE(offset, e + 12);
    offset += png.length;
  });
  return Buffer.concat([header, ...pngs.map((p) => p.png)]);
}

const icoPngs = [];
for (const size of [16, 32, 48]) icoPngs.push({ size, png: await render("favicon.svg", size) });
await writeFile(pub("favicon.ico"), ico(icoPngs));
await writeFile(pub("icon-192.png"), await render("icon.svg", 192));
await writeFile(pub("icon-512.png"), await render("icon.svg", 512));
// iOS adds its own rounding and ignores transparency: full-bleed art on the night colour
await writeFile(pub("apple-touch-icon.png"), await render("icon.svg", 180, { background: ENV_BG }));
// Android masks to a circle or squircle: keep the tile inside the 80% safe zone
await writeFile(pub("icon-maskable-512.png"), await render("icon.svg", 512, { background: ENV_BG, inset: 56 }));
await copyFile(pub("icon-512.png"), fileURLToPath(new URL("../../docs/assets/icon.png", import.meta.url)));

await browser.close();
console.log("icons written to frontend/public and docs/assets/icon.png");
