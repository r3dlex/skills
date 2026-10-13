import { validateGraph } from "../../../scripts/lib/leaf/traceability.mjs";

const graph = JSON.parse(process.argv[2]);
try {
  validateGraph(graph);
  process.stdout.write("OK\n");
} catch (error) {
  const message = error instanceof Error ? error.message : String(error);
  process.stdout.write(`ERR ${message}\n`);
  process.exit(1);
}
