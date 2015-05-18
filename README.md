Agis
====

[![Gem Version](https://badge.fury.io/rb/agis.svg)](http://badge.fury.io/rb/agis)
[![Build Status](https://travis-ci.org/gert7/agis.svg)](https://travis-ci.org/gert7/agis)

Agis provides any Ruby object, class or some other selection with its own message box, which can be locked and executed by any instance of Ruby. This allows a system of "free actors" or "actorless actors" which can run the entire message box and return the last result when it is empty without creating a separate thread of execution

Agis is provided as a mixin that only requires a Redis instance as external data, while all functionality can be contained entirely in the class alone. Setting a custom agis_id method allows custom selections of records instead of the default call to .id

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
      def agis_id; "any"; end
      
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
    pc.agis_ncrunch($redis) # or push+ncrunch with agis_call
    puts pc.value

