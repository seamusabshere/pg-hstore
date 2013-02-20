require './lib/pg_hstore'

describe "hstores from hashes" do
  it "should translate into a sequel literal" do
    h = PgHstore::dump :a => "b", :foo => "bar"
    h.should == %{$$"a"=>"b","foo"=>"bar"$$}
  end

  it "should set a value correctly" do
    h = PgHstore::parse (
      %{"ip"=>"17.34.44.22", "service_available?"=>"false"})
    h[:service_available?].should == "false"
  end

  it "should store an empty string" do
    hstore = PgHstore::dump :nothing => ""
    hstore.should == %{$$"nothing"=>""$$}
  end

  it "should support single quotes in strings" do
    hstore = PgHstore::dump :journey => "don't stop believin'"
    hstore.should == %q{$$"journey"=>"don't stop believin'"$$}
  end

  it "should support double quotes in strings" do
    hstore = PgHstore::dump :journey => 'He said he was "ready"'
    hstore.should == %q{$$"journey"=>"He said he was \"ready\""$$}
  end

  it "should escape \ garbage in strings" do
    hstore = PgHstore::dump :line_noise => %q[perl -p -e 's/\$\{([^}]+)\}/] #'
    hstore.should == %q[$$"line_noise"=>"perl -p -e 's/\\\\$\\\\{([^}]+)\\\\}/"$$]
  end

  it "should parse an empty string" do
    hstore = PgHstore.parse(
      %{"ip"=>"", "service_available?"=>"false"})

    hstore[:ip].should == ""
    hstore[:ip].should_not == nil
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
    uri = URI.parse "postgres://#{`whoami`.strip}:@0.0.0.0:5432/pg_hstore_test"
    config = {
      host: uri.host,
      port: uri.port,
      dbname: File.basename(uri.path),
      user: uri.user,
      password: uri.password,
    }
    conn = PG::Connection.new config
    conn.exec "CREATE EXTENSION IF NOT EXISTS hstore"
    # conn.exec "SET standard_conforming_strings=on"
    NASTY.each do |data|
      rs = conn.exec %{SELECT $1::hstore AS hstore}, [PgHstore.dump(data, true)]
      PgHstore.load(rs[0]['hstore']).should == data
      rs = conn.exec %{SELECT #{PgHstore.dump(data)}::hstore AS hstore}
      PgHstore.load(rs[0]['hstore']).should == data
    end
  end

  # https://github.com/engageis/activerecord-postgres-hstore/issues/78
  it "should pass @teeparham's tests" do
    PgHstore.dump({"a" => "\"a\""}, true).should == %q("a"=>"\"a\"")
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

