module Agis
  require 'redis'
  require 'redis-lock'
  require 'json'
  
  attr_accessor :agis_methods, :agis_id
  
  # called whenever a parameter in the queue is of type method
  # this is unusual behavior
  class MethodCallInParameters < Exception
  end
  
  def initialize
    @agis_methods = Hash.new
  end

  # the name of the key used for the Agis message box in Redis
  # the lock is this string followed by ".LOCK"
  def agis_mailbox
    "AGIS TERMINAL : " + self.class.to_s + " : " + (self.agis_id or self.id.to_s)
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
  def agis_defm0(name, &b)
    push = Proc.new do |redis, arg1, arg2, arg3|
      redis.rpush self.agis_mailbox, "m:" + name.to_s
    end
    @agis_methods[name] = [0, push, b]
  end
  
  # create a method with one parameter
  def agis_defm1(name, &b)
    push = Proc.new do |redis, arg1, arg2, arg3|
      redis.multi do
        redis.rpush self.agis_mailbox, "m:" + name.to_s
        redis.rpush self.agis_mailbox, agis_aconv(arg1)
      end
    end
    @agis_methods[name] = [1, push, b]
  end
  
  # create a method with two parameters
  def agis_defm2(name, &b)
    push = Proc.new do |redis, arg1, arg2, arg3|
      redis.multi do
        redis.rpush self.agis_mailbox, "m:" + name.to_s
        redis.rpush self.agis_mailbox, agis_aconv(arg1)
        redis.rpush self.agis_mailbox, agis_aconv(arg2)
      end
    end
    @agis_methods[name] = [2, push, b]
  end
  
  # create a method with three parameters
  def agis_defm3(name, &b)
    push = Proc.new do |redis, arg1, arg2, arg3|
      redis.multi do
        redis.rpush self.agis_mailbox, "m:" + name.to_s
        redis.rpush self.agis_mailbox, agis_aconv(arg1)
        redis.rpush self.agis_mailbox, agis_aconv(arg2)
        redis.rpush self.agis_mailbox, agis_aconv(arg3)
      end
    end
    @agis_methods[name] = [3, push, b]
  end
  
  # alias for agis_defm3
  def agis_def(name, &b)
    agis_defm3(name, b)
  end
  
  def _agis_crunch(lock, redis, until_sig)
    # loop do
    #  a = redis.lpop(self.agis_mailbox)
    #  a ? puts a : break
    # end
    # return 0
    loop do
      mni = redis.lpop(self.agis_mailbox)
      if mni and mni[0..1] == "m:"
        args = []
        mn = mni[2..-1]
        mc = @agis_methods[mn.to_sym][0]
        meti = @agis_methods[mn.to_sym][2]
        case meti
        when Proc
          met = meti
        when Symbol
          met = self.method(meti)
        when NilClass
          met = self.method(mn.to_sym) # when proc is Nil, call the class methods all the same
        end
        
        mc.times do
          args.push agis_fconv(redis.lpop(self.agis_mailbox))
        end
        case mc
        when 0
          @last = met.call()
        when 1
          @last = met.call(args[0])
        when 2
          @last = met.call(args[0], args[1])
        when 3
          @last = met.call(args[0], args[1], args[2])
        end
        lock.extend_life 5
        mn = nil
      elsif mni[0..1] == "r:"
        if(mni[2..-1] == until_sig)
          return @last
        else
          puts "AGIS error 1: Orphaned return marker! An agis_call was here..."
        end
      elsif mni == nil
        return @last
      else
        puts "AGIS error 2: Unrecognized line! Might be an orphaned thread..."
      end
    end
  end
  
  # Wait until the lock is available, crunch forever
  def agis_lcrunch(redis)
    redis.lock(agis_mailbox + ".LOCK", life: 5, acquire: 10) do |lock|
      loop do
        _agis_crunch(lock, redis)
        lock.extend_life(5)
      end
    end
  end
  
  # Get method in the format
  # [arity, pushing method, method body]
  def agis_method(name)
    @agis_methods[name]
  end
  
  # Push a method call into the queue
  def agis_push(redis, name, arg1=nil, arg2=nil, arg3=nil)
    @agis_methods[name][1].call(redis, arg1, arg2, arg3)
  end
  
  # Push a call and ncrunch immediately
  # this returns the last return value from the queue
  def agis_call(redis, name, arg1=nil, arg2=nil, arg3=nil)
    redis.lock(agis_mailbox + ".LOCK", life: 4, acquire: 60) do |lock|
      @agis_methods[name][1].call(redis, arg1, arg2, arg3)
      until_sig = Time.now.to_s + ":" + Process.pid.to_s + Random.new.rand(4000000000).to_s
      redis.rpush self.agis_mailbox, "r:" + until_sig
      _agis_crunch(lock, redis, until_sig)
    end
  end
  
  # Method for calling another Agis method, or retrying.
  # this doesn't touch the message box because it should
  # only be called inside an Agis method, where the box
  # is already guaranteed to be locked
  def agis_recall(name, arg1=nil, arg2=nil, arg3=nil)
    met = @agis_methods[name][2].call(arg1, arg2, arg3)
  end
end

