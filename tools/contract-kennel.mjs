// Starts Kennel's test server for tools/contract-test.sh and prints where it listens.
import { pathToFileURL } from "node:url";
import { join } from "node:path";

const kennel = process.argv[2];
const { startKennel, SETUP_TOKEN } = await import(pathToFileURL(join(kennel, "dist/test/support/kennel.js")).href);
const running = await startKennel();
console.log(`setup token: ${SETUP_TOKEN}`);
console.log(`kennel: ${running.base}`);
const stop = async () => {
  await running.close();
  process.exit(0);
};
process.on("SIGTERM", stop);
process.on("SIGINT", stop);
