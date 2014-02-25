require 'spec_helper'

describe "hstores from hashes" do
  it "should set a value correctly" do
    h = PgHstore::parse (
      %{"ip"=>"17.34.44.22", "service_available?"=>"false"})
    h['service_available?'].should == "false"
  end

  it "should parse an empty string" do
    hstore = PgHstore.parse(
      %{"ip"=>"", "service_available?"=>"false"})
    hstore['ip'].should == ""
  end

  it "should parse NULL as a value" do
    hstore = PgHstore.parse(%{"x"=>NULL})
    hstore.should == {'x' => nil}
  end

  DATA = [
    ["should translate into a sequel literal",
     {'a' => "b", 'foo' => "bar"},
     '"a"=>"b","foo"=>"bar"',
     %{E'"a"=>"b","foo"=>"bar"'}
    ],
    ["should store an empty string",
     {'nothing' => ""},
     '"nothing"=>""',
     %{E'"nothing"=>""'}
    ],
    ["should render nil as NULL",
     {'x' => nil},
     '"x"=>NULL',
     %{E'"x"=>NULL'}
    ],
    ["should support single quotes in strings",
     {'journey' => "don't stop believin'"},
     %q{"journey"=>"don't stop believin'"},
     %q{E'"journey"=>"don\'t stop believin\'"'}
    ],
    ["should support double quotes in strings",
     {'journey' => 'He said he was "ready"'},
     %q{"journey"=>"He said he was \"ready\""},
     %q{E'"journey"=>"He said he was \\\"ready\\\""'}
    ],
    ["should escape \\ garbage in strings",
     {'line_noise' => %q[perl -p -e 's/\$\{([^}]+)\}/]}, #'
     %q["line_noise"=>"perl -p -e 's/\\\\$\\\\{([^}]+)\\\\}/"],
     %q[E'"line_noise"=>"perl -p -e \'s/\\\\\\\\$\\\\\\\\{([^}]+)\\\\\\\\}/"']
    ],
  ]

  DATA.each do |name, hash, encoded, string_constant|
    it name do
      PgHstore.dump(hash, true).should == encoded
      PgHstore.dump(hash).should == string_constant
    end
  end

  NASTY = [
    { 'journey' => 'He said he was ready' },
    { 'a' => '\\' },
    { 'b' => '\\\\' },
    { 'b1' => '\\"' },
    { 'b2' => '\\"\\' },
    { 'c' => '\\\\\\' },
    { 'd' => '\\"\\""\\' },
    { 'd1' => '\"\"\\""\\' },
    { 'e' => "''" },
    { 'e' => "\\'\\''\\" },
    { 'e1' => "\\'\\''\"" },
    { 'f' => '\\\"\\""\\' },
    { 'g' => "\\\'\\''\\" },
    { 'h' => "$$; SELECT 'lol=>lol' AS hstore; --"},
    { 'z' => "');SELECT 'lol=>lol' AS hstore;--"},
    { 'n1' => 1 },
    { 'n2' => 1.5 },
    { 'n3' => 2e3 },
    { 'n4' => 2.3e4 },
  ]

  it "should be able to parse its own output" do
    NASTY.each do |data|
      typed = data
      untyped = data.inject({}) { |memo, (k, v)| memo[k] = v.to_s; memo } # all strings
      3.times do
        hstore = PgHstore.dump(data, true)
        PgHstore.load(hstore).should == untyped
        PgHstore.load_loose(hstore).should == typed
      end
    end
  end

  it "should produce stuff that postgres really likes" do
    require 'pg'
    require 'uri'
    default_uri = "postgres://#{`whoami`.strip}:@0.0.0.0:5432/pg_hstore_test"
    uri = URI.parse (ENV['PG_HSTORE_TEST_DB_URI'] || default_uri)
    config = {
      host: uri.host,
      port: uri.port,
      dbname: File.basename(uri.path),
      user: uri.user,
      password: uri.password,
    }
    conn = PG::Connection.new config
    # conn.exec "CREATE EXTENSION IF NOT EXISTS hstore"
    # conn.exec "SET standard_conforming_strings=on"
    NASTY.each do |data|
      data = data.inject({}) { |memo, (k, v)| memo[k] = v.to_s; memo } # all strings
      rs = conn.exec %{SELECT $1::hstore AS hstore}, [PgHstore.dump(data, true)]
      PgHstore.load(rs[0]['hstore']).should == data
      rs = conn.exec %{SELECT #{PgHstore.dump(data)}::hstore AS hstore}
      PgHstore.load(rs[0]['hstore']).should == data
    end
    DATA.each do |name, hash, encoded, string_constant|
      # Already tested PgHstore.dump produces what we expect for these,
      # so test that what we expect is acceptable to PostgreSQL.
      ret = conn.exec(%{SELECT $1::hstore AS hstore}, [encoded])[0]['hstore']
      ret.should == encoded.gsub(',', ', ')
      PgHstore.load(ret).should == hash
      ret = conn.exec(%{SELECT #{string_constant}::hstore AS hstore})[0]['hstore']
      ret.should == encoded.gsub(',', ', ')
      PgHstore.load(ret).should == hash
    end
  end

  it "should be able to parse hstore strings without ''" do
    data = { 'journey' => 'He said he was ready' }
    literal = PgHstore::dump(data, true)
    parsed = PgHstore.parse(literal)
    parsed.should == data
  end

  it "should be stable over iteration" do
    dump = PgHstore::dump({'journey' => 'He said he was "ready"'}, true)
    parse = PgHstore::parse dump

    original = dump

    10.times do
      parsed = PgHstore::parse(dump)
      dump = PgHstore::dump(parsed, true)
      dump.should == original
    end
  end

  it "should symbolize keys if requested" do
    h = PgHstore::parse(%{"ip"=>"17.34.44.22", "service_available?"=>"false"}, true)
    h[:service_available?].should == "false"
  end

  # http://git.postgresql.org/gitweb/?p=postgresql.git;a=blob_plain;f=contrib/hstore/expected/hstore.out;hb=HEAD

  # select hstore_to_json('"a key" =>1, b => t, c => null, d=> 12345, e => 012345, f=> 1.234, g=> 2.345e+4');
  #                                          hstore_to_json                                          
  # -------------------------------------------------------------------------------------------------
  #  {"b": "t", "c": null, "d": "12345", "e": "012345", "f": "1.234", "g": "2.345e+4", "a key": "1"}
  # (1 row)
  it "a" do
    PgHstore.load('"a key" =>1, b => t, c => null, d=> 12345, e => 012345, f=> 1.234, g=> 2.345e+4').should == MultiJson.load('{"b": "t", "c": null, "d": "12345", "e": "012345", "f": "1.234", "g": "2.345e+4", "a key": "1"}')
  end

  it "a1" do
    PgHstore.load('"a key" =>"1", b => "t", c => "null", d=> "12345", e => "012345", f=> "1.234", g=> "2.345e+4"').should == MultiJson.load('{"b": "t", "c": "null", "d": "12345", "e": "012345", "f": "1.234", "g": "2.345e+4", "a key": "1"}')
  end

  # select hstore_to_json_loose('"a key" =>1, b => t, c => null, d=> 12345, e => 012345, f=> 1.234, g=> 2.345e+4');
  #                                    hstore_to_json_loose                                   
  # ------------------------------------------------------------------------------------------
  #  {"b": true, "c": null, "d": 12345, "e": "012345", "f": 1.234, "g": 2.345e+4, "a key": 1}
  # (1 row)
  it "b" do
    PgHstore.load_loose('"a key" =>1, b => t, c => null, d=> 12345, e => 012345, f=> 1.234, g=> 2.345e+4').should == MultiJson.load('{"b": true, "c": null, "d": 12345, "e": "012345", "f": 1.234, "g": 2.345e+4, "a key": 1}')
  end

  it "b1" do
    PgHstore.load_loose('"a key" =>"1", b => "t", c => "null", d=> "12345", e => "012345", f=> "1.234", g=> "2.345e+4"').should == MultiJson.load('{"b": true, "c": null, "d": 12345, "e": "012345", "f": 1.234, "g": 2.345e+4, "a key": 1}')
  end

end

