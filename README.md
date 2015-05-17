Agis
====

Agis is a Ruby class mixin that provides a rudimentary messagebox-based lock-free actor call mechanism through and for Redis.

- Classes are provided Agis-specific methods with 0, 1, 2 or 3 arguments
- The method calls & arguments are stored on Redis in a rudimentary 'call stack' implemented with RPUSH/LPOP
- Ideally each class runs all Redis-related calls through this actor model
- Incomplete calls can be pushed to stack and called immediately, or later, returning the value of the last method call
- Actors usually called "whenever" and end when their message box is empty (agis_ncrunch - 1 second timeout, agis_bcrunch - 60 second timeout)
- Actors can also be run forever (or a very long time) with agis_lcrunch
- Objects are redis-locked via @agis_id, otherwise self.id like ActiveModel/ActiveRecord

Requires [mlanett-redis-lock](http://www.github.com/mlanett/redis-lock), required as "redis-lock"

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
        agis_defm0 do :incif |redis, arg1|
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


