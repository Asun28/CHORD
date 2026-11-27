import { defineConfig } from "vite";
import vinext from "vinext";
import { cloudflare } from "@cloudflare/vite-plugin";

export default defineConfig({
  // No CORS middleware in vite dev or vite preview (preview inherits server.cors): the node sends no
  // Access-Control-Allow-Origin header (T1-NODE-VIEW-GATE acceptance 5).
  server: { cors: false },
  plugins: [
    // vinext's config hook sets server.cors to an allow-localhost policy, which would replace the value
    // above; this hook runs after it (enforce: "post") and sets server.cors back to false.
    { name: "chord:no-cors", enforce: "post", config: () => ({ server: { cors: false } }) },
    vinext(),
    cloudflare({
      viteEnvironment: {
        name: "rsc",
        childEnvironments: ["ssr"],
      },
    }),
  ],
});
