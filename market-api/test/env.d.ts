declare module 'cloudflare:test' {
	interface Env {
		MARKET_VERSION?: string;
		MARKET_UPDATED_AT?: string;
	}
	interface ProvidedEnv extends Env {}
}
