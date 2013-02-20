# pg-hstore

The gem is called `pg-hstore`, but you should require `pg_hstore` (sorry):

    >> require 'pg_hstore'
    => true

Dump a hash to an hstore string:

    >> hstore = PgHstore.dump(hello: %{world, you're "GREAT!"})
    => "'\"hello\" => \"world, you''re \\\"GREAT!\\\"\"'"

Load an hstore string into a hash:

    >> hash = PgHstore.load(hstore)
    => {:hello=>"world, you're \"GREAT!\""}

Dump a hash for use as a bind parameter/variable (i.e., we won't be needing single quotes):

    >> hstore = PgHstore.dump({hello: %{world, you're "GREAT!"}}, true)
    => "\"hello\" => \"world, you're \\\"GREAT!\\\"\""

Load an hstore string but don't symbolize keys:

    >> hash = PgHstore.load(hstore, false)
    => {"hello"=>"world, you're \"GREAT!\""}

## Authors

* Seamus Abshere <seamus@abshere.net>
* Greg Price http://web.mit.edu/price/
* Peter van Hardenberg <pvh@heroku.com>

## Copyright

Copyright (c) 2013 the authors. See LICENSE for details.
