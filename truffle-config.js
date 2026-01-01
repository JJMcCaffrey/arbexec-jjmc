module.exports = {
  networks: {
    development: {
      host: "127.0.0.1",
      port: 8545,
      network_id: "*",
    },
    sepolia: {
      provider: () => new HDWalletProvider(process.env.PRIVATE_KEY, process.env.SEPOLIA_RPC_URL),
      network_id: 11155111,
    },
  },
  compilers: {
    solc: {
      version: "0.8.20",
      settings: {
        optimizer: {
          enabled: true,
          runs: 200,
        },
        viaIR: true, // ← Fixes stack too deep
      },
    },
  },
};