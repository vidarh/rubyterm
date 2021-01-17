require 'mkmf'

create_header
find_library('X11','XClearWindow')
create_makefile 'term'
