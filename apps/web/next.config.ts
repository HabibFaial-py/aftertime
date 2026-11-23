import type { NextConfig } from "next";

const config: NextConfig = {
  agentRules: false,
  logging: {
    incomingRequests: { ignore: [/^\/invite(?:[/?]|$)/] },
  },
};

export default config;
