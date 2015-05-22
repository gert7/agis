Agis
====

[![Gem Version](https://badge.fury.io/rb/agis.svg)](http://badge.fury.io/rb/agis)
[![Build Status](https://travis-ci.org/gert7/agis.svg)](https://travis-ci.org/gert7/agis)

Agis provides any Ruby object, class or some other selection with its own message box, which can be locked and executed by any instance of Ruby. This allows a system of "free actors" or "actorless actors" which can run the entire message box and return the last result when it is empty without creating a separate thread of execution

Agis is provided as a mixin that only requires a Redis instance as external data, while all functionality can be contained entirely in the class alone. Setting a custom agis_id method allows custom selections of records instead of the default call to .id

The Actor model doesn't provide concurrency or parallelism, it assumes that concurrent access to shared data will happen in the environment, wraps around it and becomes its 'agent', and executes every command in the message box one after another - it's inherently and forcefully single-threaded 

As of Agis 0.1.9, methods that crash or raise an exception above the method itself will be retried forever until they return, but only up to 3 times via a single call to agis_call before returning an AgisRetryAttemptsExceeded. This requires you to write idempotent but retry-guaranteed methods, which leads to more reliable code.

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
      
      def incif(arg1) # only increment the value if it's eq to arg1 when the actor calls this method
        @value = $redis.get("counter:" + self.id) or 0
        if(@value == arg1)
          @value += 1
          $redis.set("counter:" + self.id, @value)
        end
      end
      
      def initialize
        agis_defm1 :incif 
      end
    end
    
    pc = PerCounter.new
    pc.agis_call($redis, :incif, pc.value)
    puts pc.value

Bank accounts
--------

Let's assume we have a transaction class like this one:

    class Transaction
      attr_accessor :id, :amount, :sender, :receiver, :lastref, :senderbalance
      
      def agis_id
        sender.id
      end
    end

For simplicity, let's assume that a receiving account can accumulate money indefinitely, but a sending account cannot go below 0. We also need to keep track of the sending balance for fast access, and keep the transactions in the correct order via lastref to prevent double spending.

We can imagine making a transaction like so:

    Transaction.create(50, sender.id, recv.id) # agis_id refers to sender_id, this is the number that will be put on the message box, rather than the Transaction's own id
    
    # underneath this calls the agis call like so:
    agis_call($redis, :create, [50, sender.id, recv.id])

We defined agis_id as being the sender's id, since the sender is the sensitive part of the transaction and the one that senderbalance refers to.

The agis:create method will probably access the database to get lastref. Meanwhile, no one else is allowed to deal with the Transactions with this sender id, because the message box for it is locked.

Even better, if there's any reason for the transaction to fall out of order in-between, we can retry the transaction by calling the agis:create method again, in the agis method itself - and only give up if the sender's balance isn't enough (or some other reason like frozen accounts), possibly raising an error.

Retrying
--------

Agis allows retrying with agis_recall(), which accepts the same parameters as agis_call(). It doesn't tackle the message box, since it's already locked when called in an Agis method. This does nothing but call the given method among the agis_methods.

Agis doesn't remove any call from the message box that crashes or raises an exception. Instead it will retry it each time. A single agis_call will retry the failed call 3 times until raising an AgisRetryAttemptsExceeded error. As a result, you must write methods which:

- Assume they will be retried several times
- Will be retried if they raise an exception that isn't handled in the method itself

However, these restrictions are balanced by the following guarantees :

- Methods will be retried until they succeed
- Methods called through the same message box (classname + Object#agis_id) are guaranteed to run in a single thread, in sequence

Instance variable caveat
------------------------

If you write code that you assume will be retried, the only thing you can be sure of is the classname and agis_id on the message box, everything else is variable. If you write code like this:

    class User
    ...
      def bind # agis method
        v = self.bind_commit_id
        exceptional_procedure(v)
      end
    ...
    end
    
    usr = User.find(711)
    usr.bind_commit_id = Bind.create.id
    usr.agis_call($redis, :bind)

This code reads bind_commit_id from the current instance, but Agis almost assumes that the instance isn't the same as it was when the actor call was made. A working version of this code would accept instance variables as parameters:

    class User
    ...
      def bind(bid) # agis method
        exceptional_procedure(bid)
      end
    ...
    end
    
    usr = User.find(711)
    bid = Bind.create.id
    usr.agis_call($redis, :bind, bid)

