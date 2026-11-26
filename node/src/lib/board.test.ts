import { test } from "node:test";
import assert from "node:assert/strict";
import { renderToStaticMarkup } from "react-dom/server";
import { HomeBoard, readHomeBoard } from "./board.ts";
import { asD1, demoCorpus, seededDb } from "./sqlite-fixture.ts";

async function renderHome(corpus = demoCorpus): Promise<string> {
  return renderToStaticMarkup(HomeBoard({ board: await readHomeBoard(asD1(seededDb(corpus))) }));
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
