import { choosePrimaryProvider, chooseVerifierProvider, chooseProviderSet, rankProviders } from "./dist/router/adaptive_router.js";

const tasks = ["dialogue", "reasoning", "code", "evidence"];

for (const task of tasks) {
  console.log("====", task, "====");
  console.log("primary:", choosePrimaryProvider(task));
  console.log("verifier:", chooseVerifierProvider(task));
  console.log("set:", JSON.stringify(chooseProviderSet(task, { complexity: 0.9, mode: "research", conflictCount: 1 }), null, 2));
  console.log("ranked:", JSON.stringify(rankProviders(task), null, 2));
}
