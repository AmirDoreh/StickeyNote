import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtemp, writeFile, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { readWorkspace, writeWorkspace, workspaceManifest } from "../../Web/cloud-archive.js";

const root = fileURLToPath(new URL("../../", import.meta.url));
const temp = await mkdtemp(join(tmpdir(), "stickey-cloud-wire-"));
try {
    const archive = { version: 1, modifiedAt: 1790000000000, groups: [], notes: [{
        id: "00000000-0000-4000-8000-000000000001", kind: "text", createdAt: 1790000000000,
        updatedAt: 1790000000001, color: "butter", font: "system", fontSize: 18, isPinned: false, history: [],
        content: { title: "Unicode 🌏", text: "café 漢字 🌏\n".repeat(100_000), items: [], strokes: [] }
    }] };
    const records = new Map();
    const database = {
        async saveRecords(values) { values.forEach(value => records.set(value.recordName, value)); return { records: values }; },
        async fetchRecords(names) { return { records: names.map(name => records.get(name)) }; }
    };
    const manifest = await writeWorkspace(archive, null, "javascript-fixture", database);
    const input = join(temp, "javascript.json");
    const output = join(temp, "swift.json");
    await writeFile(input, JSON.stringify({ manifest: workspaceManifest(manifest), archive: JSON.stringify(archive),
        chunks: [...records.values()].filter(r => r.recordType === "StickeyWorkspaceChunk")
            .map(r => ({ recordName: r.recordName, archive: r.fields.archive.value })) }));
    const binary = join(temp, "cloud-wire");
    execFileSync("swiftc", ["-disable-sandbox", "-parse-as-library", "-module-cache-path", join(tmpdir(), "stickey-clang-cache"),
        "Sources/StickeyNote/Integrations/CloudArchiveTransport.swift", "Tests/CloudInterop/CloudWireFixture.swift", "-o", binary], { cwd: root, stdio: "inherit" });
    execFileSync(binary, [input, output], { stdio: "inherit" });
    const fixture = JSON.parse(await readFile(output, "utf8"));
    records.clear();
    fixture.chunks.forEach(chunk => records.set(chunk.recordName, { recordName: chunk.recordName, fields: { archive: { value: chunk.archive } } }));
    const decoded = await readWorkspace({ fields: { archive: { value: JSON.stringify(fixture.manifest) } } }, database);
    assert.deepEqual(decoded, archive);
    console.log("JavaScript decoded Swift archive; native/browser chunk wire format matches in both directions.");
} finally { await rm(temp, { recursive: true, force: true }); }
