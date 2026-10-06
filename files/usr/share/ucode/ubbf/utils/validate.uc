'use strict';

/**
 * Validates the path of a configuration file passed in by a ubus caller.
 *
 * @param {*} path - Candidate path
 * @returns {string|null} A short reason when the path is unacceptable,
 *                        null when it is fine
 */
export function config_path_check(path) {
	if (type(path) != 'string' || path == '' || substr(path, 0, 1) != '/')
		return 'file path must be absolute';

	for (let part in split(path, '/'))
		if (part == '.' || part == '..')
			return 'file path must not contain . or ..';

	return null;
};
