import { readdirSync, statSync } from "node:fs";
import { join } from "node:path";

const assetDir = join(process.cwd(), "dist", "assets");
const jsFiles = readdirSync(assetDir)
  .filter((name) => name.endsWith(".js"))
  .map((name) => {
    const filePath = join(assetDir, name);
    return {
      name,
      sizeBytes: statSync(filePath).size,
    };
  })
  .sort((left, right) => right.sizeBytes - left.sizeBytes);

const totalBytes = jsFiles.reduce((sum, file) => sum + file.sizeBytes, 0);
const maxChunkBytes = Number.parseInt(process.env.MAX_CHUNK_JS_KB ?? "360", 10) * 1024;
const maxEntryBytes = Number.parseInt(process.env.MAX_ENTRY_JS_KB ?? "260", 10) * 1024;
const maxTotalBytes = Number.parseInt(process.env.MAX_TOTAL_JS_KB ?? "1100", 10) * 1024;
const entryChunk = jsFiles.find((file) => file.name.startsWith("index-"));

const failures = [];

if (totalBytes > maxTotalBytes) {
  failures.push(
    `Total JavaScript output ${Math.round(totalBytes / 1024)}KB exceeds ${Math.round(maxTotalBytes / 1024)}KB.`,
  );
}

if (jsFiles[0] && jsFiles[0].sizeBytes > maxChunkBytes) {
  failures.push(
    `Largest JavaScript chunk ${jsFiles[0].name} is ${Math.round(jsFiles[0].sizeBytes / 1024)}KB, exceeding ${Math.round(maxChunkBytes / 1024)}KB.`,
  );
}

if (entryChunk && entryChunk.sizeBytes > maxEntryBytes) {
  failures.push(
    `Entry chunk ${entryChunk.name} is ${Math.round(entryChunk.sizeBytes / 1024)}KB, exceeding ${Math.round(maxEntryBytes / 1024)}KB.`,
  );
}

console.log("Bundle summary:");
for (const file of jsFiles.slice(0, 10)) {
  console.log(`- ${file.name}: ${Math.round((file.sizeBytes / 1024) * 100) / 100}KB`);
}
console.log(`- total: ${Math.round((totalBytes / 1024) * 100) / 100}KB`);

if (failures.length > 0) {
  console.error("\nBundle budget check failed:");
  for (const failure of failures) {
    console.error(`- ${failure}`);
  }
  process.exit(1);
}

console.log("\nBundle budget check passed.");
