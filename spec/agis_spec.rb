require 'agis'
require 'redis'
require 'database_cleaner'

$redis = Redis.new

puts $redis

DatabaseCleaner[:redis].strategy = :truncation

class Guffin < Object
  attr_accessor :tryvar, :stopvar
  include Agis
  def id; 3; end
  
  def exm(a)
    return "Yes return " + a
  end
  
  def initialize
    super
    stopvar = 0
    
    agis_defm0 :ident do
      "Hello"
    end
    
    agis_defm1 :dupe do |r|
      r * 2
    end
    
    agis_defm2 :mult do |r, s|
      r * s
    end
    
    agis_defm3 :mapify do |t, a, b|
      t[a] * b
    end
    
    agis_defm2 :sconcat do |a, b|
      a.to_s + " " + b.to_s
    end
    
    agis_defm2 :rhash do |h, k|
      h[k]
    end
    
    agis_defm1 :arr do |arr|
      arr[1]
    end
    
    agis_defm1 :boolme do |bool|
      bool ? "Hello" : "Nope"
    end
    
    agis_defm1 :echo do |txt|
      txt
    end
    
    agis_defm0 :testll do 
      self.agis_push($redis, :echo, "FAILURE")
      "SUCCESS"
    end
    
    agis_defm1 :redo do |n|
      if(n < 1)
        agis_recall(:redo, n + 1)
      else
        "A SUCCESS"
      end
    end
    
    agis_defm0 :nexceptor do
      stopvar += 1
      raise StandardError unless stopvar = 2
      "hey ho this will return"
    end
    
    agis_defm0 :exceptor do
      stopvar += 1
      raise StandardError
    end
    
    agis_defm1 :setvar do |v|
      self.tryvar = v
    end
    
    agis_defm1 :exm
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
      expect(Guffin.new.agis_call($redis, :rhash, {"hello" => "world"}, :hello)).to eq "world"
    end
    
    it "defines a method that accepts an array" do
      expect(Guffin.new.agis_call($redis, :arr, [71, 88, 33])).to eq 88
    end
    
    it "defines a method that accepts a true" do
      expect(Guffin.new.agis_call($redis, :boolme, true)).to eq "Hello"
    end
    
    it "defines a method that accepts a false" do
      expect(Guffin.new.agis_call($redis, :boolme, false)).to eq "Nope"
    end
    
    it "calls 1 parameter on a 2-parameter method" do
      expect(Guffin.new.agis_call($redis, :sconcat, "Hello")).to eq "Hello "
    end
    
    it "defines a method of an actual class method" do
      expect(Guffin.new.agis_call($redis, :exm, "world")).to eq "Yes return world"
    end
  end
  
  describe "#agis_call" do
    it "captures an exception and fails to finish the call" do
      expect { Guffin.new.agis_call($redis, :exceptor) }.to raise_error(Agis::AgisRetryAttemptsExceeded)
    end
    
    it "assures the setvar probe works" do
      g = Guffin.new
      g.agis_call($redis, :setvar, "Variable set")
      expect(g.tryvar).to eq "Variable set"
    end
    
    it "retrying raising exception, ignores it because it's ancient" do
      g = Guffin.new
      $redis.rpush g.agis_mailbox, "m:nexceptor"
      $redis.rpush g.agis_mailbox, "n:"
      $redis.rpush g.agis_mailbox, "n:"
      $redis.rpush g.agis_mailbox, "n:"
      $redis.rpush g.agis_mailbox, "r:whatever this is a dud return"
      g.agis_call($redis, :setvar, "trial")
      expect(g.tryvar).to eq "trial"
    end
  end
  
  describe "#agis_recall" do
    it "retries a method call" do
      expect(Guffin.new.agis_call($redis, :redo, 0)).to eq "A SUCCESS"
    end
  end
end

