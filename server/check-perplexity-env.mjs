import fs from "fs";
import path from "path";

function parseDotEnv(raw) {
  const out = {};
  for (const line of raw.split(/\r?\n/g)) {
    const s = line.trim();
    if (!s || s.startsWith("#")) continue;
    const eq = s.indexOf("=");
    if (eq <= 0) continue;
    const k = s.slice(0, eq).trim();
    const v = s.slice(eq + 1).trim();
    out[k] = v;
  }
  return out;
}

const rootEnv = path.join(process.cwd(), "..", ".env");
const serverEnv = path.join(process.cwd(), ".env");

const a = fs.existsSync(rootEnv) ? parseDotEnv(fs.readFileSync(rootEnv, "utf8")) : {};
const b = fs.existsSync(serverEnv) ? parseDotEnv(fs.readFileSync(serverEnv, "utf8")) : {};

const value = b.PERPLEXITY_API_KEY || a.PERPLEXITY_API_KEY || "";
console.log({
  rootEnv,
  serverEnv,
  hasRootKey: !!a.PERPLEXITY_API_KEY,
  hasServerKey: !!b.PERPLEXITY_API_KEY,
  finalLoadedKeyPreview: value ? value.slice(0, 12) + "..." : ""
});
