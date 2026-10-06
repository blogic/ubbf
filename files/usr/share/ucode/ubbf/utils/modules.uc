'use strict';

// Names of the out-of-tree modules whose handler registered, filled by
// external_modules_register() in datamodel.uc. A core handler cannot load
// a module file, so it reads this table to report whether a module that
// adds to its object is present. It is complete before the first get runs.
export const modules_registered = {};
