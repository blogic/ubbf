return {
	call: (object, method, args) => (object == 'gps' && method == 'info') ? global.GPS_REPLY : null
};
