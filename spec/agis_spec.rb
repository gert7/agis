require 'agis'
require 'redis'
require 'database_cleaner'

$redis = Redis.new

puts $redis

DatabaseCleaner[:redis].strategy = :truncation

class Guffin < Object
  attr_accessor :tryvar, :stopvar
  include Agis
  def agis_id
    3
  end
  
  def exm(a)
    return "Yes return " + a
  end
  
  def initialize
    stopvar = 0
    @agis_debugmode = true
    
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
      @agis_retrylimit = 3
      stopvar += 1
      raise StandardError unless stopvar == 2
      "hey ho this will return"
    end
    
    agis_defm0 :exceptor do
      stopvar += 1
      raise StandardError
    end
    
    agis_defm1 :setvar do |v|
      self.tryvar = v
    end
    
    agis_defm0 :exonce, :once do
      raise StandardError
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
  
  describe "#agis_mailbox" do
    it "fetches the correct mailbox id" do
      expect(Guffin.new.agis_mailbox).to eq "AGIS TERMINAL : Guffin : 3"
    end
  
    it "raises an error when neither agis_id or id are set" do
      class Nup
        include Agis
        
        def initialize
          agis_defm0 :ident do
            "Oops"
          end
        end
      end
      expect { Nup.new.agis_call($redis, :ident) }.to raise_error(Agis::NoAgisIDAvailable)
    end

    it "gets the id from the #id method" do
      class Pupy
        include Agis
        
        def id
          81
        end
        
        def initialize
          agis_defm0 :ident do
            "Oops"
          end
        end
      end
      expect(Pupy.new.agis_mailbox).to eq "AGIS TERMINAL : Pupy : 81"
    end
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
    
    it "defines a method only to be called once" do
      r = Guffin.new
      begin
        r.agis_call($redis, :exonce)
      rescue StandardError
      end
      expect(r.agis_call($redis, :ident)).to eq "Hello"
    end
  end
  
  describe "#agis_call" do
    it "captures an exception and fails to finish the call" do
      expect { Guffin.new.agis_call($redis, :exceptor) }.to raise_error(StandardError)
    end
    
    it "assures the setvar probe works" do
      g = Guffin.new
      g.agis_call($redis, :setvar, "Variable set")
      expect(g.tryvar).to eq "Variable set"
    end
    
    it "keeps the method call in the box after exception" do
      class Pepy
        include Agis
        
        def agis_id; "any"; end
        
        def exceptor
          raise StandardError
        end
        
        def identer
          "Pepsi"
        end
        
        def initialize
          agis_defm0 :exceptor
          agis_defm0 :identer
        end
      end
      
      ppy = Pepy.new
      expect {ppy.agis_call($redis, :exceptor)}.to raise_error(StandardError)
      expect {ppy.agis_call($redis, :identer)}.to raise_error(StandardError)
    end
    
    it "actually assures thread-safety" do
      class Trier
        include Agis
        def agis_id; "same"; end
        
        def upcount
          @counter = (@counter or 0) + 1
          @counter
        end
        
        def count
          @counter
        end
        
        def initialize
          @agis_debugmode = true
          $redis.del self.agis_mailbox
          agis_defm0 :upcount
        end
      end
      
      shared_trier = Trier.new
      
      t1 = Thread.new {
        11111.times do
          a = shared_trier.agis_call($redis, :upcount).to_s
          #puts "Thread 1 Trier counter: " + a
        end
      }
      t2 = Thread.new {
        11111.times do
          a = shared_trier.agis_call($redis, :upcount).to_s
          #puts "Thread 2 Trier counter: " + a
        end
      }
      t3 = Thread.new {
        11111.times do
          a = shared_trier.agis_call($redis, :upcount).to_s
          #puts "Thread 3 Trier counter: " + a
        end
      }
      t4 = Thread.new {
        11111.times do
          a = shared_trier.agis_call($redis, :upcount).to_s
          #puts "Thread 4 Trier counter: " + a
        end
      }
      t1.join
      t2.join
      t3.join
      t4.join
      puts "Final result: " + shared_trier.count.to_s + " out of 44444"
      expect(shared_trier.agis_call($redis, :upcount) >= 44445).to eq true
    end
    
    it "allows an actor to call another actor" do
      class User
        include Agis
        attr_accessor :id

        def reserve(v)
          $redis.set "USER" + self.id.to_s, v
        end
        
        def reservation
          $redis.get "USER" + self.id.to_s
        end
        
        def initialize(id)
          agis_defm1 :reserve
          self.id = id
        end
      end
      
      class Room
        include Agis
        
        def id; 3; end
        
        def addplayer(id)
          ply = User.new(id)
          ply.agis_call($redis, :reserve, "ROOM = " + self.id.to_s)
        end
        
        def initialize
          agis_defm1 :addplayer
        end
      end
      
      r = Room.new
      r.agis_call($redis, :addplayer, 41)
      expect(User.new(41).reservation).to eq "ROOM = 3"
    end
    
    it "allows a NOOP call for the message box" do
      g = Guffin.new
      g.agis_call($redis, :ident)
      g.agis_call($redis)
      expect(g.agis_call($redis, :ident)).to eq "Hello"
    end
  end
  
  describe "#agis_recall" do
    it "retries a method call" do
      expect(Guffin.new.agis_call($redis, :redo, 0)).to eq "A SUCCESS"
    end
  end
  
  describe "#agis_crunch_all_records" do
    class Pellet
      include Agis
      attr_accessor :id
      
      def self.find(id)
        return Pellet.new(id: id)
      end
      
      def aemote
        raise StandardError if $pelletmustfail
        $redis.set("emote " + self.id.to_s, 100)
      end
      
      def emote
        self.acall($redis, :aemote)
      end
      
      def value
        $redis.get("emote " + self.id.to_s).to_i
      end
      
      def initialize(hash)
        self.id = hash[:id]
        agis_defm0 :aemote
      end
    end
    
    it "crunches all calls of this class" do
      pellet1 = Pellet.new(id: 1)
      pellet2 = Pellet.new(id: 2)
      $pelletmustfail = true
      begin
        pellet1.emote
      rescue => e
      end
      begin
        pellet2.emote
      rescue => e
      end
      $pelletmustfail = false
      pellet1.agis_crunch_all_records($redis)
      expect(pellet1.value).to eq 100
      expect(pellet2.value).to eq 100
    end
  end
end

