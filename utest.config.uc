// utest configuration of the ucode host tests; tests/run.sh runs them in a
// private mount namespace. UBBF_HOST_BUILD names the host build of
// src/ucode-mod-ubbf with ubbf.so and the other native modules.
const build = getenv('UBBF_HOST_BUILD');

return {
	pattern: '*.uc',
	jobs: 1,
	timeout: 120,
	lib_paths: [ 'tests/lib', 'files/usr/share/ucode', 'modules/pty/files/usr/share/ucode', ...(build ? [ build ] : []) ],
	mocks: {
		ubus: null,
		uci: null
	}
};
