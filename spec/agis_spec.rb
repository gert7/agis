require 'agis'
require 'redis'
require 'database_cleaner'

$redis = Redis.new

puts $redis

DatabaseCleaner[:redis].strategy = :truncation

class Guffin < Object
  include Agis
  def id; 3; end
  
  def initialize
    super
    agis_defm0 :ident do
      "Hello"
    end
    
    agis_defm1 :dupe do |red, r|
      r * 2
    end
    
    agis_defm2 :mult do |red, r, s|
      r * s
    end
    
    agis_defm3 :mapify do |red, t, a, b|
      t[a] * b
    end
    
    agis_defm2 :sconcat do |red, a, b|
      a.to_s + " " + b.to_s
    end
    
    agis_defm2 :rhash do |red, h, k|
      h[k]
    end
    
    agis_defm1 :arr do |red, arr|
      arr[1]
    end
  end

  def ay
    return @agis_methods
  end
end

describe Agis do
  before :each do
    DatabaseCleaner[:redis].clean
  end

  it "sets an @agis_methods hash" do
    expect(Guffin.new.ay.class).to eq Hash
  end
  
  describe "#agis_defm" do
    it "defines a method with no parameters" do
      expect(Guffin.new.agis_call($redis, :ident)).to eq "Hello"
    end
    
    it "defines a method with 1 parameter" do
      expect(Guffin.new.agis_call($redis, :dupe, 4)).to eq 8
    end
    
    it "defines a method with 2 parameters" do
      expect(Guffin.new.agis_call($redis, :mult, 16, 3)).to eq 48
    end
    
    it "defines a method with 3 parameters" do
      expect(Guffin.new.agis_call($redis, :mapify, [3, 9, 11], 2, 7)).to eq 77
    end
    
    it "defines a method that accepts a string" do
      expect(Guffin.new.agis_call($redis, :sconcat, "Hello", "World!")).to eq "Hello World!"
    end
    
    it "defines a method that accepts a hash" do
      expect(Guffin.new.agis_call($redis, :rhash, {hello: "world"}, :hello)).to eq "world"
    end
    
    it "defines a method that accepts an array" do
      expect(Guffin.new.agis_call($redis, :arr, [71, 88, 33])).to eq 88
    end
  end
  
  describe "#agis_push" do
    it "pushes three method calls and recovers the last" do
      g = Guffin.new
      g.agis_push $redis, :mult, 77, 3
      g.agis_push $redis, :ident
      g.agis_push $redis, :rhash, {dingo: "dango", fringo: "frango"}, :fringo
      expect(g.agis_ncrunch $redis).to eq "frango"
    end
  end
end

