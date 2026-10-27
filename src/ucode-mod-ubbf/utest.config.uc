// utest configuration of test_ubbf_mod.uc. It loads the real native modules
// of the host build named by UBBF_HOST_BUILD, without the stand-ins of
// tests/lib.
const build = getenv('UBBF_HOST_BUILD');

return {
	jobs: 1,
	timeout: 120,
	lib_paths: build ? [ build ] : []
};
