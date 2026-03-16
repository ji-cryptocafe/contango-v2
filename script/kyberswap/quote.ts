/**
 * KyberSwap Aggregator — Quote & Build ExecutionParams
 *
 * Usage:
 *   npx ts-node script/kyberswap/quote.ts \
 *     --chain ethereum \
 *     --tokenIn 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2 \
 *     --tokenOut 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0 \
 *     --amountIn 1000000000000000000 \
 *     --sender 0xYourContangoAddress \
 *     --slippage 50
 *
 * Output: JSON with router, spender, swapAmount, swapBytes for ExecutionParams
 */

interface RouteResponse {
  code: number;
  message: string;
  data: {
    routeSummary: Record<string, unknown>;
    routerAddress: string;
  };
}

interface BuildResponse {
  code: number;
  message: string;
  data: {
    amountIn: string;
    amountOut: string;
    routerAddress: string;
    data: string; // encoded swap calldata
  };
}

interface ExecutionParams {
  router: string;
  spender: string;
  swapAmount: string;
  swapBytes: string;
  flashLoanProvider: string;
}

const KYBERSWAP_API = "https://aggregator-api.kyberswap.com";

const CHAIN_MAP: Record<string, string> = {
  ethereum: "ethereum",
  mainnet: "ethereum",
  arbitrum: "arbitrum",
  optimism: "optimism",
  polygon: "polygon",
  base: "base",
  bsc: "bsc",
  avalanche: "avalanche",
  linea: "linea",
  scroll: "scroll",
};

async function getRoute(
  chain: string,
  tokenIn: string,
  tokenOut: string,
  amountIn: string
): Promise<RouteResponse> {
  const chainSlug = CHAIN_MAP[chain.toLowerCase()] || chain;
  const url = `${KYBERSWAP_API}/${chainSlug}/api/v1/routes?tokenIn=${tokenIn}&tokenOut=${tokenOut}&amountIn=${amountIn}`;

  const res = await fetch(url, {
    headers: { "Accept": "application/json" },
  });

  if (!res.ok) {
    throw new Error(`Route query failed: ${res.status} ${res.statusText}`);
  }

  return res.json() as Promise<RouteResponse>;
}

async function buildRoute(
  chain: string,
  routeSummary: Record<string, unknown>,
  sender: string,
  recipient: string,
  slippageTolerance: number
): Promise<BuildResponse> {
  const chainSlug = CHAIN_MAP[chain.toLowerCase()] || chain;
  const url = `${KYBERSWAP_API}/${chainSlug}/api/v1/route/build`;

  const res = await fetch(url, {
    method: "POST",
    headers: {
      "Accept": "application/json",
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      routeSummary,
      sender,
      recipient,
      slippageTolerance,
    }),
  });

  if (!res.ok) {
    throw new Error(`Route build failed: ${res.status} ${res.statusText}`);
  }

  return res.json() as Promise<BuildResponse>;
}

async function buildExecutionParams(opts: {
  chain: string;
  tokenIn: string;
  tokenOut: string;
  amountIn: string;
  sender: string;
  recipient?: string;
  slippage?: number;
  flashLoanProvider?: string;
}): Promise<ExecutionParams> {
  // Step 1: Get route
  const routeRes = await getRoute(opts.chain, opts.tokenIn, opts.tokenOut, opts.amountIn);

  if (routeRes.code !== 0) {
    throw new Error(`Route error: ${routeRes.message}`);
  }

  const { routeSummary, routerAddress } = routeRes.data;

  // Step 2: Build encoded swap data
  const buildRes = await buildRoute(
    opts.chain,
    routeSummary,
    opts.sender,
    opts.recipient || opts.sender,
    opts.slippage || 50 // default 0.5% = 50 bps
  );

  if (buildRes.code !== 0) {
    throw new Error(`Build error: ${buildRes.message}`);
  }

  // Step 3: Construct ExecutionParams
  return {
    router: routerAddress,
    spender: routerAddress, // KyberSwap uses router as spender
    swapAmount: opts.amountIn,
    swapBytes: buildRes.data.data,
    flashLoanProvider: opts.flashLoanProvider || "0x0000000000000000000000000000000000000000",
  };
}

// CLI entry point
async function main() {
  const args = process.argv.slice(2);
  const opts: Record<string, string> = {};

  for (let i = 0; i < args.length; i += 2) {
    const key = args[i].replace(/^--/, "");
    opts[key] = args[i + 1];
  }

  if (!opts.chain || !opts.tokenIn || !opts.tokenOut || !opts.amountIn || !opts.sender) {
    console.error("Required: --chain --tokenIn --tokenOut --amountIn --sender");
    console.error("Optional: --recipient --slippage --flashLoanProvider");
    process.exit(1);
  }

  const params = await buildExecutionParams({
    chain: opts.chain,
    tokenIn: opts.tokenIn,
    tokenOut: opts.tokenOut,
    amountIn: opts.amountIn,
    sender: opts.sender,
    recipient: opts.recipient,
    slippage: opts.slippage ? parseInt(opts.slippage) : undefined,
    flashLoanProvider: opts.flashLoanProvider,
  });

  console.log(JSON.stringify(params, null, 2));
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});

export { buildExecutionParams, getRoute, buildRoute };
