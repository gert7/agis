module Agis
  require 'redis'
  require 'redis-lock'
  require 'json'
  
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
  
  class MessageBoxEmpty < StandardError
  end
  
  def agis_id_prelim
    begin
      mid = self.agis_id
    rescue NoMethodError
    end
    begin
      mid ||= self.id
    rescue NoMethodError
    end
    return mid
  end

  # the name of the key used for the Agis message box in Redis
  # the lock is this string followed by ".LOCK"
  def agis_mailbox
    mid = agis_id_prelim
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
      a = "h:" + v.to_json.to_s
    when Array
      a = "a:" + v.to_json.to_s
    when Float
      a = "d:" + v.to_s
    when TrueClass
      a = "t:"
    when FalseClass
      a = "f:"
    when NilClass
      a = "n:"
    else
      a = "h:" + v.to_json.to_s
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
  def agis_defm0(name, mode=:retry, timeout=nil, &b)
    @agis_methods ||= Hash.new
    @agis_methods[name] = {arity: 0, method: b, mode: mode, timeout: timeout}
  end
  
  # create a method with one parameter
  def agis_defm1(name, mode=:retry, timeout=nil, &b)
    @agis_methods ||= Hash.new
    @agis_methods[name] = {arity: 1, method: b, mode: mode, timeout: timeout}
  end
  
  # create a method with two parameters
  def agis_defm2(name, mode=:retry, timeout=nil, &b)
    @agis_methods ||= Hash.new
    @agis_methods[name] = {arity: 2, method: b, mode: mode, timeout: timeout}
  end
  
  # create a method with three parameters
  def agis_defm3(name, mode=:retry, timeout=nil, &b)
    @agis_methods ||= Hash.new
    @agis_methods[name] = {arity: 3, method: b, mode: mode, timeout: timeout}
  end
  
  # alias for agis_defm3
  def agis_def(name, mode=:retry, timeout=nil, &b)
    agis_defm3(name, timeout, b)
  end
  
  def pretty_exception(args, e)
    ret = []
    ret << "Agis method call failed: " + args.to_s
    ret << "  " + e.class.to_s
    e.backtrace.each do |v|
      ret << v.to_s
    end
    ret
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
  
  def agis_chew(redis, lock)
    args = redis.lrange(self.agis_mailbox, 0, 4)
    mni  = args[0]
    if(mni and mni[0..1] == "m:")
      # don't do any signatures twice ever
      lusig = args[4][2..-1]
      #puts lusig
      if redis.hget self.agis_returnbox, lusig
        popfive redis
        return nil
      end
      mn        = mni[2..-1]
      mns       = mn.to_sym
      if mn == "AGIS_NOOP" # NOOP
        redis.hset self.agis_returnbox, lusig, "done"
        popfive(redis)
        return :next
      else
        mc        = @agis_methods[mns][:arity]
        mrm       = @agis_methods[mns][:mode]
        meti    = @agis_methods[mns][:method]
        case meti
        when Proc
          met = meti
        when Symbol
          met = self.method(meti)
        when NilClass
          met = self.method(mn.to_sym) # when proc is Nil, call the class methods all the same
        end
      end
      
      begin
        #raise Agis::RedisLockExpired if lock.stale_key?
        #begin
        #  lock.extend_life (@agis_methods[mn.to_sym][2] or 5)
        #rescue Redis::Lock::LockNotAcquired
        #  raise Agis::RedisLockExpired
        #end
        popfive(redis) if mrm == :once
        case mc
        when 0
          ret = agis_aconv(met.call())
        when 1
          ret = agis_aconv(met.call(agis_fconv(args[1])))
        when 2
          ret = agis_aconv(met.call(agis_fconv(args[1]), agis_fconv(args[2])))
        when 3
          ret = agis_aconv(met.call(agis_fconv(args[1]), agis_fconv(args[2]), agis_fconv(args[3])))
        end
        redis.multi do
          redis.hset self.agis_returnbox, lusig, ret
          popfive(redis) if mrm == :retry
        end
        return :next
      rescue Agis::RedisLockExpired => e
        puts "Agis lock expired for " + args.to_s if (@agis_debugmode == true)
        # popfive redis
        return :relock
      rescue => e
        #puts "feck"
        lock.unlock
        raise e
      end
    elsif not mni
      return :empty
    else
      puts "AGIS error: Unrecognized line!" + mni.to_s
    end
  end
  
  def agis_try_usig(redis, usig)
    mayb = redis.hget self.agis_returnbox, usig
    if mayb
      redis.hdel self.agis_returnbox, usig
      return mayb
    else
      return nil
    end
  end
  
  def _agis_crunch(redis, usig)
    loop do
      redis.lock(self.agis_boxlock, life: 10) do |lock|
        a = agis_chew(redis, lock)
        next if lock.stale_key?
        u = agis_try_usig(redis, usig)
        if a == :empty
          raise Agis::MessageBoxEmpty unless u
        end
        return agis_fconv(u) if u
      end
    end
  end
  
  # Find all mailboxes total
  def _agis_find_global_mailboxes(redis)
    redis.smembers("AGIS_MAILBOX_GLOBAL_LIST")
  end
  
  # Find all mailboxes for this class
  def agis_find_all_mailboxes(redis)
    redis.smembers("AGIS_MAILBOX_CLASS:" + self.class.to_s)
  end
  
  # Crunch all agis calls on a single model
  # found using the #find method with the
  # agis_id or id. Must be numeric
  def agis_crunch_all_records(redis)
    all = agis_find_all_mailboxes(redis)
    all.each do |id|
      self.class.find(id).agis_call(redis)
    end
  end
  
  # Crunch all agis calls on a single model
  # found using the #new method with id set
  # to agis_id or id
  def agis_crunch_all_records_new(redis)
    all = agis_find_all_mailboxes(redis)
    all.each do |id|
      self.class.new(id).agis_call(redis)
    end
  end
  
  # Get method in the format
  # [arity, method body]
  def agis_method(name)
    @agis_methods[name]
  end
  
  # Push a call and ncrunch immediately
  # this returns the last return value from the queue
  def agis_call(redis, name=nil, arg1=nil, arg2=nil, arg3=nil)
    name ||= "AGIS_NOOP"
    until_sig = Time.now.to_s + ":" + Process.pid.to_s + Random.new.rand(4000000000).to_s + Random.new.rand(4000000000).to_s
    loop do
      begin
        redis.sadd("AGIS_MAILBOX_CLASSES", self.class.to_s)
        redis.sadd("AGIS_MAILBOX_CLASS:" + self.class.to_s, self.agis_id_prelim)
        redis.sadd("AGIS_MAILBOX_GLOBAL_LIST", self.agis_mailbox)
        redis.multi do
          redis.rpush self.agis_mailbox, "m:" + name.to_s
          redis.rpush self.agis_mailbox, agis_aconv(arg1)
          redis.rpush self.agis_mailbox, agis_aconv(arg2)
          redis.rpush self.agis_mailbox, agis_aconv(arg3)
          redis.rpush self.agis_mailbox, "r:" + until_sig
        end
        return _agis_crunch(redis, until_sig)
      rescue Agis::MessageBoxEmpty
      end
    end
  end
  
  # Alias for agis_call
  def acall(redis, name=nil, arg1=nil, arg2=nil, arg3=nil)
    agis_call(redis, name, arg1, arg2, arg3)
  end
  
  # Method for calling another Agis method, or retrying.
  # this doesn't touch the message box because it should
  # only be called inside an Agis method, where the box
  # is already guaranteed to be locked
  def agis_recall(mn, arg1=nil, arg2=nil, arg3=nil)
    meti = @agis_methods[mn.to_sym][:method]
    case meti
    when Proc
      met = meti
    when Symbol
      met = self.method(meti)
    when NilClass
      met = self.method(mn.to_sym) # when proc is Nil, call the class methods all the same
    end
    
    case @agis_methods[mn.to_sym][:arity]
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

