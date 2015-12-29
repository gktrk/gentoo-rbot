require "shorturl"
class GentooShortenURLs < Plugin
  def initialize
    super
    @@cached = {}
    @@cached['lasturl'] = {}
  end

  def lurk?(m)
    replyto = nil
    replyto = m.replyto.to_s if m.is_a?(Irc::UserMessage)
    return true
    return false unless replyto
  end
  def listen(m)
    return if m.address?
    return unless m.is_a?(Irc::UserMessage)
    #return unless lurk?(m)
    return unless m.message =~ /(\b|^)[a-z]+:\/\/.*($|\s)/i
    m.message.split.each do |word|
      next unless word =~ /(\b|^)[a-z]+:\/\/.*($|\s)/i
      #next unless word.length >= 32
      #shrink(m, {:url => word})
      set_lasturl(m, word)
    end
  end
  def shrink(m, params)
    short = ShortURL.shorten(params[:url], :tinyurl)
    m.reply short
  end
  def fetch_lasturl(m)
    address = m.replyto.to_s
    url = [0, nil]
    url = @@cached['lasturl'][address] if @@cached['lasturl'].has_key?(address)
    return url
  end
  def set_lasturl(m, url)
    address = m.replyto.to_s
    @@cached['lasturl'][address] = [Time.now.tv_sec, url]
  end
  def lasturl(m, params)
  	url = fetch_lasturl(m)
	if url[1]
	  shrink(m, {:url => url})
	else
	  m.reply "No URL seen yet"
	end
  end
end
plugin = GentooShortenURLs.new
plugin.map 't :url',
  :action => 'shrink',
  :auth_path => 'view'
plugin.map 'lasturl',
  :action => 'lasturl',
  :auth_path => 'view'
