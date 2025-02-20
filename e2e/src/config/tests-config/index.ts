import TestSetup from "./setup";
import canary from "./environments/canary";

import { Config } from "./types";

const testEnv = process.env.TEST_ENV || "canary";

let config: Config;

switch (testEnv) {
  case "canary":
    config = canary;
    break;
  // case "sepolia":
  //   config = sepoliaConfig;
  //   break;
  // case "local":
  // default:
  //   config = localConfig;
  //   break;
}
const setup = new TestSetup(config);

export { setup as config };
