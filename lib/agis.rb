module Agis
  require 'redis'
  require 'redis-lock'
  require 'json'
  
  attr_accessor :agis_methods, :agis_id
  
  def initialize
    @agis_methods = Hash.new
  end

  def agis_mailbox
    "AGIS TERMINAL : " + self.class.to_s + " : " + (@agis_id or self.id.to_s)
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
      a = "f:" + v.to_s
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
    when "f:"
      v[2..-1].to_f
    end
  end
  
  def agis_defm0(name, &b)
    push = Proc.new do |redis, arg1, arg2, arg3|
      redis.rpush self.agis_mailbox, name
    end
    @agis_methods[name] = [0, push, b]
  end
  
  def agis_defm1(name, &b)
    push = Proc.new do |redis, arg1, arg2, arg3|
      redis.rpush self.agis_mailbox, name
      redis.rpush self.agis_mailbox, agis_aconv(arg1)
    end
    @agis_methods[name] = [1, push, b]
  end
  
  def agis_defm2(name, &b)
    push = Proc.new do |redis, arg1, arg2, arg3|
      redis.rpush self.agis_mailbox, name
      redis.rpush self.agis_mailbox, agis_aconv(arg1)
      redis.rpush self.agis_mailbox, agis_aconv(arg2)
    end
    @agis_methods[name] = [2, push, b]
  end
  
  def agis_defm3(name, &b)
    push = Proc.new do |redis, arg1, arg2, arg3|
      redis.rpush self.agis_mailbox, name
      redis.rpush self.agis_mailbox, agis_aconv(arg1)
      redis.rpush self.agis_mailbox, agis_aconv(arg2)
      redis.rpush self.agis_mailbox, agis_aconv(arg3)
    end
    @agis_methods[name] = [3, push, b]
  end
  
  def _agis_crunch(lock, redis)
    # loop do
    #  a = redis.lpop(self.agis_mailbox)
    #  a ? puts a : break
    # end
    # return 0
    loop do
      if mn = redis.lpop(self.agis_mailbox)
        args = []
        mc = @agis_methods[mn.to_sym][0]
        met = @agis_methods[mn.to_sym][2]

        mc.times do
          args.push agis_fconv(redis.lpop(self.agis_mailbox))
        end
        case mc
        when 0
          @last = met.call(redis)
        when 1
          @last = met.call(redis, args[0])
        when 2
          @last = met.call(redis, args[0], args[1])
        when 3
          @last = met.call(redis, args[0], args[1], args[2])
        end
        lock.extend_life 5
        mn = nil
      else
        return @last
      end
    end
  end
  
  # Crunch if the lock is available, returns when box is empty, lock timeout 1 second
  def agis_ncrunch(redis)
    redis.lock(agis_mailbox + ".LOCK", life: 4, acquire: 1) do |lock|
      _agis_crunch(lock, redis)
    end
  end
  
  # Wait until the lock is available, returns when box is empty, lock timeout 60 seconds
  def agis_bcrunch(redis)
    redis.lock(agis_mailbox + ".LOCK", life: 4, acquire: 60) do |lock|
      _agis_crunch(lock, redis)
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
  
  # Get method
  def agis_method(name)
    @agis_methods[name]
  end
  
  # Call method -> push
  def agis_push(redis, name, arg1=nil, arg2=nil, arg3=nil)
    @agis_methods[name][1].call(redis, arg1, arg2, arg3)
  end
  
  # Call and ncrunch immediately
  def agis_call(redis, name, arg1=nil, arg2=nil, arg3=nil)
    @agis_methods[name][1].call(redis, arg1, arg2, arg3)
    agis_ncrunch(redis)
  end
end

