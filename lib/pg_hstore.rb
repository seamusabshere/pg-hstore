module PgHstore
  SINGLE_QUOTE = "'"
  E_SINGLE_QUOTE = "E'"
  DOUBLE_QUOTE = '"'
  HASHROCKET = '=>'
  COMMA = ','
  SLASH = '\\'

  ESCAPED_CHAR = /\\(.)/
  ESCAPED_SINGLE_QUOTE = '\\\''
  ESCAPED_DOUBLE_QUOTE = '\\"'
  ESCAPED_SLASH = '\\\\'

  QUOTED_LITERAL = /"[^"\\]*(?:\\.[^"\\]*)*"/
  UNQUOTED_LITERAL = /[^\s=,][^\s=,\\]*(?:\\.[^\s=,\\]*|=[^,>])*/
  LITERAL = /(#{QUOTED_LITERAL}|#{UNQUOTED_LITERAL})/
  PAIR = /#{LITERAL}\s*=>\s*#{LITERAL}/
  NULL = /\ANULL\z/i
  
  # set symbolize_keys = false if you want string keys
  # thanks to https://github.com/engageis/activerecord-postgres-hstore for regexps!
  def PgHstore.load(hstore, symbolize_keys = true)
    hstore.scan(PAIR).inject({}) do |memo, (k, v)|
      k = unescape unquote(k, DOUBLE_QUOTE)
      k = k.to_sym if symbolize_keys
      v = (v =~ NULL) ? nil : unescape(unquote(v, DOUBLE_QUOTE))
      memo[k] = v
      memo
    end
  end

  # Serialize a hash to be sent to PostgreSQL as an hstore value.
  #
  # By default, returns a (Postgre)SQL string constant suitable for
  # interpolating directly into a query.  With raw_string = true,
  # returns the plain string value suitable for use as a bind variable.
  def PgHstore.dump(hash, raw_string = false)
    # Per http://www.postgresql.org/docs/9.2/static/hstore.html :
    #
    #   The text representation of an hstore, used for input and
    #   output, includes zero or more 'key => value' pairs separated
    #   by commas. [...] Whitespace between pairs or around the =>
    #   sign is ignored.  Double-quote keys and values [... see
    #   escape_nonnull_for_hstore ...]
    #
    #   A value (but not a key) can be an SQL NULL.  Double-quote the
    #   NULL to treat it as the ordinary string "NULL".
    hstore = hash.map do |k, v|
      hstore_k = escape_nonnull_for_hstore(k)
      hstore_v = (v.nil?) ? "NULL" : escape_nonnull_for_hstore(v)
      [hstore_k, hstore_v].join(HASHROCKET)
    end.join(COMMA)
    raw_string ? hstore : as_postgresql_string_constant(hstore)
  end

  class << self
    # deprecated; use PgHstore.load
    alias parse load
  end

  private

  def PgHstore.unquote(string, quote_char)
    if string.start_with? quote_char
      l = quote_char.length
      string[l..(-1-l)]
    else
      string
    end
  end

  def PgHstore.unescape(literal)
    literal.gsub ESCAPED_CHAR, '\1'
  end

  # Escape a value as a string to use as an hstore key or value.
  #
  # Per http://www.postgresql.org/docs/9.2/static/hstore.html :
  #
  #   Double-quote keys and values that include [stuff]. To include a
  #   double quote or a backslash in a key or value, escape it with a
  #   backslash.
  #
  # You got it, boss.
  def PgHstore.escape_nonnull_for_hstore(string)
    interior = string.to_s.dup
    interior.gsub!(SLASH) {ESCAPED_SLASH}
    interior.gsub!(DOUBLE_QUOTE, ESCAPED_DOUBLE_QUOTE)
    DOUBLE_QUOTE + interior + DOUBLE_QUOTE
  end

  # Escape a string as a string constant to be used in a SQL query
  # to PostgreSQL.
  #
  # Ideally we would use plain SQL string constants, which are very simple:
  #   http://www.postgresql.org/docs/9.2/static/sql-syntax-lexical.html#SQL-SYNTAX-STRINGS
  # Unfortunately PostgreSQL treats these differently depending on the
  # variable standard_conforming_strings, which defaulted to off until 9.1.
  # It doesn't seem possible to generate them correctly for both cases at
  # once, and trying to know the value of that variable and dispatch on it
  # would be awful.
  #
  # Instead, use the slightly more cumbersome "escape" string constants:
  #   http://www.postgresql.org/docs/9.2/static/sql-syntax-lexical.html#SQL-SYNTAX-STRINGS-ESCAPE
  # They're a little uglier and they're PostgreSQL-specific, but nobody has
  # to see them and this whole module is PostgreSQL-specific.  And, crucially,
  # their behavior doesn't vary.  Not allowing injection attacks: priceless.
  # We don't use any of the fancy escapes, just neuter any backslashes and quotes.
  def PgHstore.as_postgresql_string_constant(string)
    interior = string.to_s.dup
    interior.gsub!(SLASH) {ESCAPED_SLASH}
    interior.gsub!(SINGLE_QUOTE) {ESCAPED_SINGLE_QUOTE}
    E_SINGLE_QUOTE + interior + SINGLE_QUOTE
  end
end
