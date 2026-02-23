declare module 'cloudflare:test' {
	interface Env {
		DB: any;
		MARKET_VERSION?: string;
		MARKET_UPDATED_AT?: string;
		CORS_ALLOWED_ORIGINS?: string;
		SUPPLIER_REGISTRY_ADDRESS_MAINNET?: string;
		SUPPLIER_REGISTRY_ADDRESS_SEPOLIA?: string;
		PAYMENT_HUB_ADDRESS_MAINNET?: string;
		PAYMENT_HUB_ADDRESS_SEPOLIA?: string;
		USDC_ADDRESS_MAINNET?: string;
		USDC_ADDRESS_SEPOLIA?: string;
		DEFAULT_CHAIN_ENV?: string;
	}
	interface ProvidedEnv extends Env {}
}
