require './lib/pg_hstore'

describe "hstores from hashes" do
  it "should set a value correctly" do
    h = PgHstore::parse (
      %{"ip"=>"17.34.44.22", "service_available?"=>"false"})
    h[:service_available?].should == "false"
  end

  it "should parse an empty string" do
    hstore = PgHstore.parse(
      %{"ip"=>"", "service_available?"=>"false"})
    hstore[:ip].should == ""
  end

  DATA = [
    ["should translate into a sequel literal",
     {:a => "b", :foo => "bar"},
     '"a"=>"b","foo"=>"bar"',
     %{$$"a"=>"b","foo"=>"bar"$$} #"
    ],
    ["should store an empty string",
     {:nothing => ""},
     '"nothing"=>""',
     %{$$"nothing"=>""$$} #"
    ],
    ["should support single quotes in strings",
     {:journey => "don't stop believin'"},
     %q{"journey"=>"don't stop believin'"},
     %q{$$"journey"=>"don't stop believin'"$$} #"
    ],
    ["should support double quotes in strings",
     {:journey => 'He said he was "ready"'},
     %q{"journey"=>"He said he was \"ready\""},
     %q{$$"journey"=>"He said he was \"ready\""$$} #"
    ],
    ["should escape \\ garbage in strings",
     {:line_noise => %q[perl -p -e 's/\$\{([^}]+)\}/]}, #'
     %q["line_noise"=>"perl -p -e 's/\\\\$\\\\{([^}]+)\\\\}/"],
     %q[$$"line_noise"=>"perl -p -e 's/\\\\$\\\\{([^}]+)\\\\}/"$$] #'
    ],
  ]

  DATA.each do |name, hash, encoded, string_constant|
    it name do
      PgHstore.dump(hash, true).should == encoded
      PgHstore.dump(hash).should == string_constant
    end
  end

  NASTY = [
    { :journey => 'He said he was ready' },
    { :a => '\\' },
    { :b => '\\\\' },
    { :b1 => '\\"' },
    { :b2 => '\\"\\' },
    { :c => '\\\\\\' },
    { :d => '\\"\\""\\' },
    { :d1 => '\"\"\\""\\' },
    { :e => "''" },
    { :e => "\\'\\''\\" },
    { :e1 => "\\'\\''\"" },
    { :f => '\\\"\\""\\' },
    { :g => "\\\'\\''\\" },
    { :z => "');DROP SCHEMA public;--"},
  ]

  it "should be able to parse its own output" do
    NASTY.each do |data|
      original = data
      3.times do
        hstore = PgHstore::dump data
        data = PgHstore::parse(hstore)
        data.should == original
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
    data = { :journey => 'He said he was ready' }
    literal = PgHstore::dump data
    parsed = PgHstore.parse(literal[2..-3])
    parsed.should == data
  end

  it "should be stable over iteration" do
    dump = PgHstore::dump :journey => 'He said he was "ready"'
    parse = PgHstore::parse dump

    original = dump

    10.times do
      parsed = PgHstore::parse(dump)
      dump = PgHstore::dump(parsed)
      dump.should == original
    end
  end
end

