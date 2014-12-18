# NAME

App::mimi - Migrations for small home projects

# DESCRIPTION

You want to look at `script/mimi` documentation instead. This is just an
implementation.

# METHODS

## `new`

Creates new object. Duh.

## `fix`

Fixes last error migration by changing its status to `success`.

## `migrate`

Finds the last migration number and runs all provided files with greater number.

## `set`

Manually set the last migration.

## `setup`

Creates migration table.

# AUTHOR

Viacheslav Tykhanovskyi, `viacheslav.t@gmail.com`

# COPYRIGHT AND LICENSE

Copyright (C) 2014, Viacheslav Tykhanovskyi

This program is free software, you can redistribute it and/or modify it under
the terms of the Artistic License version 2.0.

This program is distributed in the hope that it will be useful, but without any
warranty; without even the implied warranty of merchantability or fitness for
a particular purpose.
