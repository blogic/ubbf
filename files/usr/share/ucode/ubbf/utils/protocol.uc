'use strict';

import { stat } from 'fs';

// Firmware images ship exactly one of obuspa (USP) or cwmpd (CWMP), so
// binary presence is a faithful signal for the active management protocol.
// This lives apart from datamodel.uc because ubbf-device needs the answer
// without building the data model.
export const ACTIVE_PROTOCOL = stat('/usr/sbin/cwmpd') ? 'cwmp' : 'usp';

export const CWMP_MODE = ACTIVE_PROTOCOL == 'cwmp';
