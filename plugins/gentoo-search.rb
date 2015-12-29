#-- vim:sw=2:et:ft=ruby

GOOGLE_WAP_SEARCH = "http://www.google.com/m/search?hl=en&q="
GOOGLE_WAP_LINK = /<a href="(?:.*?u=(.*?)|(http:\/\/.*?))">(.*?)<\/a>/im

class GentooSearchPlugin < Plugin
  def listen(m)
    #return if m.address?
    # if the channel is #gentoo, you MUST use "g? $QUERY" to cut down on spam.
    return if m.target.to_s == "#gentoo" && m.message !~ /^g\? (.+)$/
    # Otherwise, you can use "g? $QUERY" or "? $QUERY" to search.
    return if m.message !~ /^g?\? (.+)$/i
    search = $1
    #m.reply "doing search for #{search}"
    params = {}
    params[:words] = search
    return gentoo_search(m, params)
  end

  def gentoo_search(m, params)
    params[:site] = 'gentoo.org'
    return google(m, params)
  end
  
  def google(m, params)
    what = params[:words].to_s
    searchfor = CGI.escape what
    # This method is also called by other methods to restrict searching to some sites
    if params[:site]
      site = "site:#{params[:site]}+"
    else
      site = ""
    end
    # It is also possible to choose a filter to remove constant parts from the titles
    # e.g.: "Wikipedia, the free encyclopedia" when doing Wikipedia searches
    filter = params[:filter] || ""

    url = GOOGLE_WAP_SEARCH + site + searchfor

    hits = params[:hits] || @bot.config['google.hits']
    hits = 1 if params[:lucky]

    first_pars = params[:firstpar] || @bot.config['google.first_par']

    single = params[:lucky] || (hits == 1 and first_pars == 1)

    begin
      wml = @bot.httputil.get(url)
      raise unless wml
    rescue => e
      m.reply "error googling for #{what}"
      return
    end
    results = wml.scan(GOOGLE_WAP_LINK)

    if results.length == 0
      m.reply "no results found for #{what}"
      return
    end

    single ||= (results.length==1)
    urls = Array.new
    n = 0
    results = results[0...hits].map { |res|
      n += 1
      t = res[2].ircify_html(:img => "[%{src} %{alt} %{dimensions}]").strip
      u = URI.unescape(res[0] || res[1])
      urls.push(u)
      "%{n}%{b}%{t}%{b}%{sep}%{u}" % {
        :n => (single ? "" : "#{n}. "),
        :sep => (single ? " -- " : ": "),
        :b => Bold, :t => t, :u => u
      }
    }

     if params[:lucky]
       m.reply results.first
       return
     end

    result_string = results.join(" | ")

    # If we return a single, full result, change the output to a more compact representation
    if single
      m.reply "Result for %s: %s -- %s" % [what, result_string, Utils.get_first_pars(urls, first_pars)], :overlong => :truncate
      return
    end

    m.reply "Results for #{what}: #{result_string}", :split_at => /\s+\|\s+/

    return unless first_pars > 0

    Utils.get_first_pars urls, first_pars, :message => m

  end
end

plugin = GentooSearchPlugin.new

#plugin.map "? *words", :action => 'gentoo_search', :threaded => true
