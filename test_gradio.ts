import { client } from "npm:@gradio/client";

async function run() {
  console.log("Connecting to Gradio space...");
  const app = await client("briaai/BRIA-RMBG-1.4");
  console.log("Connected!");
  // we would send an image Blob
}
run().catch(console.error);
