require 'set'
class Stack
  def initialize
    @hash = {}
  end

  def [](key)
    @hash[key] = [] unless @hash[key]
    @hash[key]
  end

  def contains?(key)
    @hash.has_key?(key)
  end

  def clear(key)
    @hash.delete(key)
  end
end

class GentooFixupPlugin < Plugin
  def initialize
    super
    @stack = Stack.new
    @action = nil
    @old_m = nil
  end

  # Name is overloaded
  def whois(m)
    nick = m.whois[:nick].downcase
    # need to see if the whois reply was invoked by this plugin
    return unless @stack.contains?(nick)
    #msg = "Real bot host:" + m.parse_channel_list.inspect
    channels = Set.new
    channels.merge(m.whois[:channels].map{|c|c[0].downcase}) if m.whois.include?(:channels)
    #msg = "Real bot channels:" + m.whois.channels
    if false
    elsif @action == 'ACTUAL'
      reply_actual_channels(@old_m, channels)
    elsif @action == 'AWOL'
      reply_awol_channels(@old_m, channels)
    elsif @action == 'FIX'
      apply_fixup(@old_m, channels) 
    end
    @action = nil
    @old_m = nil
    @stack.clear(nick)
  end

  def want_channels
    return Set.new(@bot.config['irc.join_channels'].compact.map{|c|c.downcase})
  end
  
  def awol_channels(actual_channels)
    return want_channels - actual_channels
  end

  def apply_fixup(m, actual_channels)
    missing_channels = awol_channels(actual_channels).to_a.sort
    s = missing_channels.join(', ')
    #@bot.say 'robbat2|na', 'Fixing '+s
    #@bot.say 'robbat2', 'Fixing '+s
    m.reply 'Fixing '+s
    missing_channels.each do |chan|
      @bot.part(chan, "Fixing bot channels")
      @bot.join(chan)
    end
  end

  def do_lookup(m, params)
    nick = @bot.config['irc.nick']
    nick.downcase!
    @stack[nick] << m.replyto
    @bot.whois(nick)
  end

  def fixup(m, params)
    @action = 'FIX'
    @old_m = m
    do_lookup(m, params)
  end
  
  def say_want_channels(m, params)
    c = want_channels.to_a.sort
    m.reply "Target channels (#{c.size}): "+c.join(', ')
  end
  
  def say_actual_channels(m, params)
    @action = 'ACTUAL'
    @old_m = m
    do_lookup(m, params)
  end
  def reply_actual_channels(m, channels)
    m.reply "Actual channels (#{channels.size}): " + channels.to_a.sort.join(', ')
  end

  def say_awol_channels(m, params)
    @action = 'AWOL'
    @old_m = m
    do_lookup(m, params)
  end

  def reply_awol_channels(m, channels)
    missing_channels = awol_channels(channels).to_a.sort
    m.reply "AWOL channels (#{missing_channels.size}): " + missing_channels.to_a.sort.join(', ')
  end


end
plugin = GentooFixupPlugin.new
plugin.map 'fixupjoin',
  :action => 'fixup',
  :auth_path => 'move'
plugin.map 'actualchannels',
  :action => 'say_actual_channels',
  :auth_path => 'move'
plugin.map 'wantchannels',
  :action => 'say_want_channels',
  :auth_path => 'move'
plugin.map 'awolchannels',
  :action => 'say_awol_channels',
  :auth_path => 'move'

# vim: et sts=2 ts=2 sw=2:
