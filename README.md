Agis
====

[![Gem Version](https://badge.fury.io/rb/agis.svg)](http://badge.fury.io/rb/agis)

Agis is a Ruby class mixin that provides a rudimentary messagebox-based lock-free actor call mechanism through and for Redis. It allows commands to be pushed to an autonomous message box in Redis associated with the Object. The calls in the box are then crunched with a call to the agis_crunch methods. The locking mechanism ensures that only one actor crunch routine runs at any time, which can then optionally return a value.

However, it is not designed to be an asynchronous job queue like Sidekiq. A single actor should run on a single thread at any time.

- Classes are provided Agis-specific methods with 0, 1, 2 or 3 arguments
- The method calls & arguments are stored on Redis in a rudimentary 'call stack' implemented with RPUSH/LPOP
- Ideally each class runs all Redis-related calls through this actor model
- Incomplete calls can be pushed to stack and called immediately, or later, returning the value of the last method call
- Actors usually called "whenever" and end when their message box is empty (agis_ncrunch - 1 second timeout, agis_bcrunch - 60 second timeout)
- Actors can also be run forever (or a very long time) with agis_lcrunch
- Objects are redis-locked via @agis_id, otherwise self.id like ActiveModel/ActiveRecord
- Arguments are stored as JSON objects, hashes are string-keyed instead of symbol-keyed

Installation
---

Requires [mlanett-redis-lock](http://www.github.com/mlanett/redis-lock), required as "redis-lock"

    gem 'agis'

Example
---

    require 'agis'
    require 'redis'
    
    $redis = Redis.new
    
    class PerCounter < ActiveRecord::Base
      attr_accessor :value
      
      include Agis
      def initialize
        # only increment the value if it's eq to arg1 when the actor calls this method
        agis_defm1 do :incif |redis, arg1|
          @value = redis.get("counter:" + self.id) or 0
          if(@value == arg1)
            @value += 1
            redis.set("counter:" + self.id, @value)
          end
        end
      end
    end
    
    pc = PerCounter.new
    pc.agis_push($redis, :incif, pc.value)
    pc.agis_ncrunch($redis)
    puts pc.value

