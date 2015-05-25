module Agis
  require 'redis'
  require 'redis-lock'
  require 'json'
  
  attr_accessor :agis_methods
  
  # called whenever a parameter in the queue is of type method
  # this is unusual behavior
  class MethodCallInParameters < StandardError
  end
  
  class AgisRetryAttemptsExceeded < StandardError
  end
  
  class NoAgisIDAvailable < StandardError
  end
  
  class RedisLockExpired < StandardError
  end
  
  def initialize
    @agis_methods = Hash.new
  end

  # the name of the key used for the Agis message box in Redis
  # the lock is this string followed by ".LOCK"
  def agis_mailbox
    begin
      mid = self.agis_id
    rescue NoMethodError
    end
    begin
      mid ||= self.id
    rescue NoMethodError
    end
    raise NoAgisIDAvailable unless mid
    a = "AGIS TERMINAL : " + self.class.to_s + " : " + mid.to_s
  end
  
  def agis_aconv(v)
    a = ""
    case v
    when String
      a = "s:" + v
    when Symbol
      a = "s:" + v.to_s
    when Integer
      a = "i:" + v.to_s
    when Hash
      a = "h:" + v.to_json
    when Array
      a = "a:" + v.to_json
    when Float
      a = "d:" + v.to_s
    when TrueClass
      a = "t:"
    when FalseClass
      a = "f:"
    when NilClass
      a = "n:"
    else
      a = "h:" + v.to_json
    end
    return a
  end
  
  def agis_fconv(v)
    case v[0..1]
    when "s:"
      v[2..-1]
    when "i:"
      v[2..-1].to_i
    when "h:"
      JSON.parse!(v[2..-1], symbolize_names: false)
    when "a:"
      JSON.parse!(v[2..-1], symbolize_names: false)
    when "d:"
      v[2..-1].to_f
    when "t:"
      true
    when "f:"
      false
    when "n:"
      nil
    when "m:"
      raise MethodCallInParameters
    end
  end
  
  # create a method with no parameters
  def agis_defm0(name, timeout=nil, &b)
    @agis_methods ||= Hash.new
    @agis_methods[name] = [0, b]
  end
  
  # create a method with one parameter
  def agis_defm1(name, timeout=nil, &b)
    @agis_methods ||= Hash.new
    @agis_methods[name] = [1, b]
  end
  
  # create a method with two parameters
  def agis_defm2(name, timeout=nil, &b)
    @agis_methods ||= Hash.new
    @agis_methods[name] = [2, b]
  end
  
  # create a method with three parameters
  def agis_defm3(name, timeout=nil, &b)
    @agis_methods ||= Hash.new
    @agis_methods[name] = [3, b]
  end
  
  # alias for agis_defm3
  def agis_def(name, timeout=nil, &b)
    agis_defm3(name, timeout, b)
  end
  
  def pretty_exception(args, e)
    puts "Agis method call failed: " + args.to_s
    puts "  " + e.class.to_s
    e.backtrace.each do |v|
      puts v.to_s
    end
  end
  
  def popfive(redis)
    redis.multi do
      redis.lpop self.agis_mailbox
      redis.lpop self.agis_mailbox
      redis.lpop self.agis_mailbox
      redis.lpop self.agis_mailbox
      redis.lpop self.agis_mailbox
    end
  end
  
  def agis_boxlock
    self.agis_mailbox + ".LOCK"
  end
  
  def agis_returnbox
    self.agis_mailbox + ".RETN"
  end
  
  def _agis_crunch(redis, usig)
    # loop do
    #  a = redis.lpop(self.agis_mailbox)
    #  a ? puts a : break
    # end
    # return 0
    agis_last = nil
    
    redis.lock(self.agis_boxlock, life: 5) do |lock|
      loop do
        mayb = redis.hget self.agis_returnbox, usig
        if mayb
          redis.hdel self.agis_returnbox, usig
          return agis_fconv(mayb)
        end
        args = redis.lrange(self.agis_mailbox, 0, 4)
        mni  = args[0]
        return agis_last unless mni
        if(mni and mni[0..1] == "m:")
          if redis.hget self.agis_returnbox, args[4][2..-1]
            popfive redis
            next
          end
          mn        = mni[2..-1]
          mc        = @agis_methods[mn.to_sym][0]
          meti      = @agis_methods[mn.to_sym][1]
          until_sig = "r:" + usig
          case meti
          when Proc
            met = meti
          when Symbol
            met = self.method(meti)
          when NilClass
            met = self.method(mn.to_sym) # when proc is Nil, call the class methods all the same
          end
          
          begin
            raise Agis::RedisLockExpired if lock.stale_key?
            begin
              lock.extend_life (@agis_methods[mn.to_sym][2] or 5)
            rescue Redis::Lock::LockNotAcquired
              raise Agis::RedisLockExpired
            end
            case mc
            when 0
              redis.hset self.agis_returnbox, usig, agis_aconv(met.call())
            when 1
              redis.hset self.agis_returnbox, usig, agis_aconv(met.call(agis_fconv(args[1])))
            when 2
              redis.hset self.agis_returnbox, usig, agis_aconv(met.call(agis_fconv(args[1]), agis_fconv(args[2])))
            when 3
              redis.hset self.agis_returnbox, usig, agis_aconv(met.call(agis_fconv(args[1]), agis_fconv(args[2]), agis_fconv(args[3])))
            end
          rescue Agis::RedisLockExpired => e
            puts "Agis lock expired for " + args.to_s if (@agis_debugmode == true)
          rescue => e
            #puts "feck"
            lock.unlock
            raise Agis::AgisRetryAttemptsExceeded, pretty_exception(args, e)
          end
        else
          puts "AGIS error 2: Unrecognized line! Might be an orphaned thread..." + mni.to_s
        end
      end
    end
  end
  
  # Wait until the lock is available, crunch forever
  def agis_lcrunch(redis)
    loop do
      _agis_crunch(lock, redis)
      #lock.extend_life (@agis_locktimeout or 4)
    end
  end
  
  # Get method in the format
  # [arity, method body]
  def agis_method(name)
    @agis_methods[name]
  end
  
  # Push a call and ncrunch immediately
  # this returns the last return value from the queue
  def agis_call(redis, name, arg1=nil, arg2=nil, arg3=nil)
    until_sig = Time.now.to_s + ":" + Process.pid.to_s + Random.new.rand(4000000000).to_s
    redis.multi do
      redis.rpush self.agis_mailbox, "m:" + name.to_s
      redis.rpush self.agis_mailbox, agis_aconv(arg1)
      redis.rpush self.agis_mailbox, agis_aconv(arg2)
      redis.rpush self.agis_mailbox, agis_aconv(arg3)
      redis.rpush self.agis_mailbox, "r:" + until_sig
    end
    _agis_crunch(redis, until_sig)
  end
  
  # Alias for agis_call
  def acall(redis, name, arg1=nil, arg2=nil, arg3=nil)
    agis_call(redis, name, arg1, arg2, arg3)
  end
  
  # Method for calling another Agis method, or retrying.
  # this doesn't touch the message box because it should
  # only be called inside an Agis method, where the box
  # is already guaranteed to be locked
  def agis_recall(mn, arg1=nil, arg2=nil, arg3=nil)
    meti = @agis_methods[mn.to_sym][1]
    case meti
    when Proc
      met = meti
    when Symbol
      met = self.method(meti)
    when NilClass
      met = self.method(mn.to_sym) # when proc is Nil, call the class methods all the same
    end
    
    case @agis_methods[mn.to_sym][0]
    when 0
      return met.call()
    when 1
      return met.call(arg1)
    when 2
      return met.call(arg1, arg2)
    when 3
      return met.call(arg1, arg2, arg3)
    end
  end
end

