declare module 'cloudflare:test' {
	interface Env {
		DB: any;
		MARKET_VERSION?: string;
		MARKET_UPDATED_AT?: string;
	}
	interface ProvidedEnv extends Env {}
}
