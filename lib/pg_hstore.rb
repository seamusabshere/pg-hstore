module PgHstore
  SINGLE_QUOTE = "'"
  DOUBLE_QUOTE = '"'
  DOLLAR_QUOTE = '$$' # TODO not infallible
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
      DOLLAR_QUOTE + memo + DOLLAR_QUOTE
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
end

