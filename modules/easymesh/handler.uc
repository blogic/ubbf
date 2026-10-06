'use strict';

// Out-of-tree module. `ubbf_module` is the scope datamodel.uc includes this
// file with, and it is visible only while the include runs, so anything the
// handlers use later has to be bound at the top of each file. See
// docs/ARCHITECTURE.md.
//
// The domain is split over the files below. Each one adds its entries to
// ubbf_module and shares the functions that a later file needs through em,
// so the order of the includes matters.

let em = {};

include('./ieee1905.uc', { em });
include('./objectdata.uc', { em });
include('./operations.uc', { em });
include('./x_ubbf_easymesh.uc', { em });
include('./dataelements.uc', { em });
