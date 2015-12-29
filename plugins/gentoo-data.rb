# Gentoo centric plugin for rbot
# Copyright (c) 2008 Mark Loeser <mark@halcy0n.com>
#
#  This program is free software: you can redistribute it and/or modify
#  it under the terms of the GNU Affero General Public License as
#  published by the Free Software Foundation, either version 3 of the
#  License, or (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU Affero General Public License for more details.
#
#  You should have received a copy of the GNU Affero General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.

# This does not always actually get run!
#class Hash
#  def grep(key)
#    keys = self.keys.grep(key)
#    result = {}
#    keys.each do |k| 
#      result[k] = self[k]
#      #warning("#{k} => #{self[k]}")
#    end
#    return result
#  end
#end

#VALID_PACKAGE_SRC = "http://tinderbox.dev.gentoo.org/misc/qsearch.txt"
#GLSA_SRC = "http://www.gentoo.org/security/en/glsa/glsa-@GLSA_ID@.xml?passthru=1"
VALID_PACKAGE_SRC = "/dev/shm/qsearch.txt"
GLSA_SRC = "#{ENV['PORTDIR']}/metadata/glsa/glsa-@GLSA_ID@.xml"
HERDS_SRC = 'https://api.gentoo.org/packages/herds.xml'

class GentooPlugin < Plugin
  Config.register Config::StringValue.new('gentoo.scriptdir',
    :requires_rescan => true,
    :desc => "Directory for finding external scripts.")
  Config.register Config::StringValue.new('gentoo.python',
    :requires_rescan => true,
    :desc => "Patch to Python binary")

  def scriptdir
    sd = @bot.config['gentoo.scriptdir']
    sd = "@BOTCLASS@/gentoo-scripts" unless sd
    sd.sub!('@BOTCLASS@', @bot.botclass)
    return sd
  end

  def python
    py = @bot.config['gentoo.python']
    py = '/usr/bin/python' unless py
    return py
  end
  
  def meta(m, params)
    cp = params[:pkg]
    cp = validate_package(m, cp)
    return if cp.nil?
    f = IO.popen("#{python} #{scriptdir}/metadata.py '#{cp}'")
    r = f.readlines
    f.close
    if r.length > 0
      m.reply "#{r}"
    else
      m.reply "Cannot find metadata for '#{cp}'"
    end
  end
  
  def validpkg(m, params)
    icp = params[:pkg]
    cp = validate_package(m, icp)
    return if cp.nil?
    m.reply "#{icp} => #{cp} is valid"
  end

  def meta_verbose(m, params)
    cp = params[:pkg]
    cp = validate_package(m, cp)
    return if cp.nil?
    f = IO.popen("#{python} #{scriptdir}/metadata.py '#{cp}'")
    output = f.readlines
    f.close
    m.reply "#{output}"
    herds = []
    output[0].gsub!(/(Maintainer:|Description:).*/,'')
    mre = /Herd: +([-[:alnum:], ]+) .*/.match(output[0])
    herds = mre[1].strip.split(/[, ]+/).map { |s| s.strip }.flatten if mre and mre[1]
    herds.each { |h|
      debug("meta -v calling herd for #{h}")
      p = params.clone
      p[:herd] = h
      herd(m, p)
    }
  end

  def changelog(m, params)
    cp = params[:pkg]
    cp = validate_package(m, cp)
    return if cp.nil?
    f = IO.popen("#{python} #{scriptdir}/changelog.py '#{cp}'")
    m.reply "#{f.readlines}"
    f.close
  end

  def devaway(m, params)
    dev = params[:dev].downcase
    res = @bot.httputil.get("http://dev.gentoo.org/devaway/index-csv.php?who=#{dev}")
    if res.length > 0 then
      m.reply "#{dev}: #{res}"
    else
      m.reply "#{dev} has no devaway!"
    end
  end

  def initialize
    super
    @@cached = {}
    @@cached['herds'] = [0, nil]
    @@cached['pkgindex'] = [0, nil]
    @@cached['alias'] = [0, nil]
    @@cached['notherds'] = [0, nil]
  end

  def herd(m, params)
    now = Time.now.tv_sec
    unless @@cached['herds'] and @@cached['herds'][0] > now-600
      #m.reply "Fetch #{@@cached['herds'][0]} > #{now-600}"
      res = @bot.httputil.get(HERDS_SRC)
      herds = REXML::Document.new(res)
      @@cached['herds'] = [now, herds]
    else
      #m.reply "Cache #{@@cached['herds'][0]} > #{now-600}"
      herds = @@cached['herds'][1]
    end

    unless @@cached['notherds'] and @@cached['notherds'][0] > now-600
      notherds = {}
      File.foreach("#{scriptdir}/not-a-herd.txt") { |line|
        k,v = line.split(/\s+/, 2)
        notherds[k] = v
      }
      if notherds.length > 0
        @@cached['notherds'] = [now, notherds]
      else
        @@cached['notherds'] = [0, nil]
      end
    else
      notherds = @@cached['notherds'][1]
    end

    # Parse data
    # xpath queries with REXML appear to be extremely slow, which is why we took the approach below
    herd = nil
    herds.elements[1].each_element { |elem|
        if elem.get_elements('name')[0].text == params[:herd]
          herd = elem
          break
        end }
    if herd
      emails = []
      for maintainer in herd.get_elements("maintainer")
        emails << maintainer.get_elements('email')[0].text.split('@')[0]
      end
      for project in herd.get_elements("maintainingproject")
        res = @bot.httputil.get("http://www.gentoo.org/#{project.text}?passthru=1")
        proj_xml = REXML::Document.new(res)
        for dev in proj_xml.get_elements("/project/dev")
          emails << dev.text
        end
      end
      m.reply "(#{params[:herd]}) #{emails.sort.join(', ')}"
    elsif notherds.has_key?(params[:herd])
      herddata = notherds[params[:herd]]
      m.reply "(#{params[:herd]}) #{herddata}"      
    else
      m.reply "No such herd #{params[:herd]}"
    end
  end

  def expand_alias(m, params)
    now = Time.now.tv_sec
    unless @@cached['alias'] and @@cached['alias'][0] > now-600
      #m.reply "Fetch #{@@cached['alias'][0]} > #{now-600}"
      #res = @bot.httputil.get('http://dev.gentoo.org/~solar/.alias')
      res = @bot.httputil.get('http://dev.gentoo.org/.alias.cache')
      alias_hash = {}
      for line in res
        split_line = line.split(' = ')
        alias_hash[split_line[0]] = split_line[1]
      end
      @@cached['alias'] = [now, alias_hash]
    else
      #m.reply "Cache #{@@cached['alias'][0]} > #{now-600}"
      alias_hash = @@cached['alias'][1]
    end

    m.reply "#{params[:alias]} = #{alias_hash[params[:alias]]}"
  end

  def glsa(m, params)
    source = GLSA_SRC.sub('@GLSA_ID@', params[:glsa_id])
    res = fetch_file_or_url(source)
    if res
      glsa_body = REXML::Document.new(res)
      refs = nil
      for ref in glsa_body.get_elements('/glsa/references/uri')
        if refs.nil?
          refs = ''
          refs << ref.text
        else
          refs << ', ' << ref.text
        end
      end
      m.reply "#{glsa_body.get_elements("/glsa/title")[0].text} #{refs}"
    else
      m.reply "Unable to find GLSA #{params[:glsa_id]}"
    end
  end

  def glsa_search(m, params)
    m.reply 'TODO'
  end
  
  def fetch_file_or_url(f)
    if (f =~ /^http/) == 0
      return @bot.httputil.get(f)
    else
      return File.read(f)
    end
  end

  def get_pkgindex(m)
    now = Time.now.tv_sec
    #m.reply "In validate_package"
    @@cached['pkgindex'] = [0, nil] unless
    unless @@cached.key?('pkgindex') and @@cached['pkgindex'][0] > now-600
      #m.reply "Fetch #{@@cached['pkgindex'][0]} > #{now-600}"
      pkgindex_a = fetch_file_or_url(VALID_PACKAGE_SRC).split("\n")
      pkgindex = {}
      pkgindex_a.each do |pkg|
        cp, desc = pkg.split(' ', 2)
        pkgindex[cp] = desc
      end
      @@cached['pkgindex'] = [now, pkgindex]
    else
      #m.reply "Cache #{@@cached['pkgindex'][0]} > #{now-600}"
      pkgindex = @@cached['pkgindex'][1]
    end
    return pkgindex
  end

  def validate_package(m, pn)
    begin
      pkgindex = get_pkgindex(m)

      pn = pn.gsub('+','\\\+')
      rx = (pn =~ /\//) ? /^#{pn}$/ : /\/#{pn}$/

      packages = pkgindex.keys.grep(rx)

      case packages.length
      when 1
        return packages[0]
      when 0
        m.reply "No matching packages for '#{pn}'."
        return nil
      else
        m.reply "Ambiguous name '#{pn}'. Possible options: #{packages.join(' ')}"
        return nil
      end
    rescue ::Exception => e
      m.reply e.message
    end
  end

  def depcommon(m, type, url, params)
    cp = params[:pkg]
    cp = validate_package(m, cp)
    return if cp.nil?

    # Watch out for network problems
    begin
      packages = @bot.httputil.get(url+cp)
    rescue ::Exception => e
      m.reply e.message
      return
    end

    # 404 error => nil response
    packages = '' if packages.nil?

    # Only then can we split it
    packages = packages.split("\n")

    if packages.length == 0
      m.reply "No packages have a reverse #{type} on #{cp}."
    elsif packages.join(' ').length > 400
      m.reply "Too many packages have reverse #{type} on #{cp}, go to #{url+cp} instead."
    else
      m.reply "Reverse #{type} for #{cp}: #{packages.join(' ')}"
    end
  end

  def ddep(m, params)
    depcommon(m, 'DEPEND', 'http://qa-reports.gentoo.org/output/genrdeps/dindex/', params)
  end

  def pdep(m, params)
    depcommon(m, 'PDEPEND', 'http://qa-reports.gentoo.org/output/genrdeps/pindex/', params)
  end

  def rdep(m, params)
    depcommon(m, 'RDEPEND', 'http://qa-reports.gentoo.org/output/genrdeps/rindex/', params)
  end

  def earch(m, params)
    cp = params[:pkg]
    cp = validate_package(m, cp)
    return if cp.nil?
    f = IO.popen("#{python} #{scriptdir}/earch --nocolor --quiet -c '#{cp}'")
    output = f.readlines
    f.close
    if output[0] =~ /^!!!/
      m.reply "Unable to find package #{cp}"
      return
    end
    output[0].gsub!(/^.*#{cp}/,cp)
    output.map!{ |l| l.gsub(/^#{cp}-/,'').chomp }
    m.reply "#{cp} #{output.join(' ')}"
  end

  @@help_gentoo = {
    "gentoo" => "Available commands: #{Bold}meta#{Bold}, #{Bold}changelog#{Bold}, #{Bold}devaway#{Bold}, #{Bold}herd#{Bold}, #{Bold}expn#{Bold}, #{Bold}glsa#{Bold}, #{Bold}earch#{Bold}, #{Bold}rdep#{Bold}, #{Bold}ddep#{Bold}, #{Bold}pdep#{Bold}",
    "meta" => [
            "meta #{Bold}[cat/]package#{Bold} : Print metadata for the given package",
            "meta -v #{Bold}[cat/]package#{Bold} : Print metadata for the given package and the members of the package herds.", 
            ].join("\n"),
    "changelog" => "changelog #{Bold}[cat/]package#{Bold} : Produce changelog statistics for a given package",
    "devaway" => "devaway #{Bold}devname|list#{Bold} : Print the .away for a developer (if any). Using 'list' shows the developers who are away.",
    "herd" => "herd #{Bold}herdname#{Bold} : Print the members of a herd.",
    "expn" => "expn #{Bold}alias#{Bold} : Print the addresses on a Gentoo mail alias.",
    "glsa" => [
            "glsa #{Bold}GLSA-ID#{Bold} : Prints the title and reference IDs for a given GLSA.",
            "glsa -s #{Bold}[cat/]package#{Bold} : Prints all GLSA IDs for a given package.",
            ].join("\n"),
    "earch" => "earch #{Bold}[cat/]package#{Bold} : Prints the versions and effective keywords for a given package.",
    "rdep" => "rdep #{Bold}[cat/]package#{Bold} : Prints the reverse RDEPENDs for a given package.",
    "ddep" => "ddep #{Bold}[cat/]package#{Bold} : Prints the reverse DEPENDS for a given package.",
    "pdep" => "pdep #{Bold}[cat/]package#{Bold} : Prints the reverse PDEPENDs for a given package.",
  }


  def help(plugin, topic = "")
    cmd = plugin
    cmd += " "+topic if topic.length > 0
    if @@help_gentoo.has_key?(cmd)
      return @@help_gentoo[cmd]
    else
      return @@help_gentoo['gentoo']
    end
  end
end

plugin = GentooPlugin.new

plugin.default_auth( 'modify', false )
plugin.default_auth( 'view', true )

REGEX_CP = /^(?:[-[:alnum:]]+\/)?[-+_[:alnum:]]+$/
REGEX_DEV = /^[-_[:alnum:]]+$/
REGEX_HERD = /^[-_[:alnum:]]+$/
REGEX_GLSA = /^[-1234567890]+$/

plugin.map 'meta -v :pkg',
  :requirements => {
    :pkg => REGEX_CP,
  },
  :action => 'meta_verbose',
  :thread => 'yes',
  :auth_path => 'view'

plugin.map 'meta :pkg',
  :requirements => {
    :pkg => REGEX_CP,
  },
  :action => 'meta',
  :thread => 'yes',
  :auth_path => 'view'

plugin.map 'validpkg :pkg',
  :requirements => {
    :pkg => REGEX_CP,
  },
  :action => 'validpkg',
  :auth_path => 'view'

plugin.map 'changelog :pkg',
  :requirements => {
    :pkg => REGEX_CP,
  },
  :action => 'changelog',
  :thread => 'yes',
  :auth_path => 'view'

plugin.map 'devaway :dev',
  :requirements => {
    :dev => REGEX_DEV,
  },
  :action => 'devaway',
  :thread => 'yes',
  :auth_path => 'view'

plugin.map 'away :dev',
  :requirements => {
    :dev => REGEX_DEV,
  },
  :action => 'devaway',
  :thread => 'yes',
  :auth_path => 'view'

plugin.map 'herd :herd',
  :requirements => {
    :herd => REGEX_HERD,
  },
  :action => 'herd',
  :thread => 'yes',
  :auth_path => 'view'

plugin.map 'expn :alias',
  :requirements => {
    :alias => REGEX_DEV,
  },
  :action => 'expand_alias',
  :thread => 'yes',
  :auth_path => 'view'

plugin.map 'glsa :glsa_id',
  :requirements => {
    :alias => REGEX_GLSA,
  },
  :action => 'glsa',
  :thread => 'yes',
  :auth_path => 'view'

plugin.map 'glsa -s :text',
  :requirements => {
    :text => /^[^ ]+$/,
  },
  :action => 'glsa_search',
  :thread => 'yes',
  :auth_path => 'view'

plugin.map 'ddep :pkg',
  :requirements => {
    :pkg => REGEX_CP,
  },
  :action => 'ddep',
  :thread => 'yes',
  :auth_path => 'view'

plugin.map 'pdep :pkg',
  :requirements => {
    :pkg => REGEX_CP,
  },
  :action => 'pdep',
  :thread => 'yes',
  :auth_path => 'view'

plugin.map 'rdep :pkg',
  :requirements => {
    :pkg => REGEX_CP,
  },
  :action => 'rdep',
  :thread => 'yes',
  :auth_path => 'view'

plugin.map 'earch :pkg',
  :requirements => {
    :pkg => REGEX_CP,
  },
  :action => 'earch',
  :thread => 'yes',
  :auth_path => 'view'

# vim: ft=ruby ts=2 sts=2 et:
