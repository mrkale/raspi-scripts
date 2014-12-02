Library for production scripts
=====
The script is supposed to be loaded to working (production) scripts as a library. It can be considere
as a framework for those scripts. It contains common configuration parameters and common functions
definitions.

Name
=====
**scripts_lib.sh** - library of functions and configurations

Synopsis
=====
    source "$(dirname $0)/scripts_lib.sh"


Description
=====
Script should be loaded at the very begining of a working script.

- Script is supposed to be located in the same folder as a working script.
- It is recommended to create symbolic links to all working scripts and the library script as well
and put them all into the same folder.
- Symbolic links may have extension ommited.

License
=====
This script is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.
