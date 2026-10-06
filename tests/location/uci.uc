const values = {
	'cwmp.acs.url': 'http://acs.example:7547/',
	'obuspa.acs.endpoint_id': 'proto::uacs'
};

return {
	cursor: () => ({
		get: (config, section, option) => values[`${config}.${section}.${option}`]
	})
};
