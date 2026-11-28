import { test } from "node:test";
import assert from "node:assert/strict";
import { renderToStaticMarkup } from "react-dom/server";
import { env } from "./app-loader.ts";
import { HomeBoard, readHomeBoard } from "./board.ts";
import { asD1, demoCorpus, seededDb } from "./sqlite-fixture.ts";

const { default: HomePage } = await import("../app/page.tsx");

async function renderHome(corpus = demoCorpus): Promise<string> {
  return renderToStaticMarkup(HomeBoard({ board: await readHomeBoard(asD1(seededDb(corpus))) }));
}

// GET / : the page module, reading the seeded corpus through the DB binding.
async function renderPage(corpus = demoCorpus): Promise<string> {
  env.DB = asD1(seededDb(corpus));
  return renderToStaticMarkup(await HomePage());
}

test("home board shows the home hub name", async () => {
  assert.ok((await renderHome()).includes("St Brigid&#x27;s Hall, Ferncliff"));
});

test("home board labels the fictional corpus", async () => {
  assert.ok((await renderHome()).includes("Fictional demo data"));
});

test("a corpus not flagged fictional is not labelled fictional", async () => {
  assert.ok(!(await renderHome({ ...demoCorpus, fictional: false })).includes("Fictional demo data"));
});

test("home board shows the home hub when it is not the first hub", async () => {
  const html = await renderHome({ ...demoCorpus, home_hub_id: "hub-quillwick" });
  assert.ok(html.includes("Quillwick Bowling Club") && !html.includes("St Brigid"));
});

test("the home page renders the home hub name from the DB binding", async () => {
  assert.ok((await renderPage()).includes("St Brigid&#x27;s Hall, Ferncliff"));
});

test("the home page shows the visible Fictional demo data label", async () => {
  assert.ok((await renderPage()).includes("Fictional demo data"));
});

test("the home page reads the hub from the DB binding, not a fixed name", async () => {
  const html = await renderPage({ ...demoCorpus, home_hub_id: "hub-quillwick" });
  assert.ok(html.includes("Quillwick Bowling Club") && !html.includes("St Brigid"));
});

test("a cursor that names no real instant is refused with not found", async () => {
  env.DB = asD1(seededDb());
  await assert.rejects(HomePage({ searchParams: Promise.resolve({ at: "2026-02-30T10:00:00Z" }) }), /NEXT_HTTP_ERROR_FALLBACK;404|NEXT_NOT_FOUND/);
});

test("a hub without coordinates shows the store error banner and no posture", async () => {
  const html = await renderPage({ ...demoCorpus, hubs: demoCorpus.hubs.map(({ lat: _lat, lon: _lon, ...hub }) => hub) as never });
  assert.deepEqual([html.includes("Store error"), html.includes("data-posture")], [true, false]);
});
