module PgHstore
  SINGLE_QUOTE = "'"
  DOUBLE_QUOTE = '"'
  HASHROCKET = '=>'
  COMMA = ','

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

  # set for_parameter = true if you're using the output for a bind variable
  def PgHstore.dump(hash, for_parameter = false)
    memo = hash.map do |k, v|
      if v.nil?
        v = "NULL"
      else
        v = DOUBLE_QUOTE + escape(v) + DOUBLE_QUOTE
      end
      k = DOUBLE_QUOTE + escape(k) + DOUBLE_QUOTE
      [k, v].join HASHROCKET
    end.join COMMA
    if for_parameter
      memo
    else
      as_postgresql_string_constant(memo)
    end
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

  ESCAPED_CHAR = /\\(.)/
  def PgHstore.unescape(literal)
    literal.gsub ESCAPED_CHAR, '\1'
  end
  
  NON_ESCAPE_SLASH = '\\'
  ESCAPED_SLASH = '\\\\'
  ESCAPED_DOUBLE_QUOTE = '\"'
  def PgHstore.escape(string)
    string.to_s.gsub(NON_ESCAPE_SLASH) {ESCAPED_SLASH}.gsub DOUBLE_QUOTE, ESCAPED_DOUBLE_QUOTE
  end

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
    interior = string.to_s.gsub('\\') {'\\\\'}.gsub('\'') {'\\\''}
    "E'" + interior + "'"
  end
end
