# Bugzilla plugin for rbot
# Copyright (c) 2005-2008 Diego Pettenò <flameeyes@gmail.com> & Robin H. Johnson <robbat2@orbis-terrarum.net>
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

require 'set'
require 'rexml/document'
require 'csv'
require 'htmlentities'

module BugzillaStringExtensions
  def decode_entities
    return HTMLEntities.new().decode(self)
  end
end
String.send(:include, BugzillaStringExtensions)

# Valid statuses
# 'DONE' and 'OPEN' are special cases that expand to the rest of the statuses in that array
DONE_STATUS = ['DONE','RESOLVED','VERIFIED','CLOSED']
OPEN_STATUS = ['OPEN','UNCONFIRMED','NEW','ASSIGNED','REOPENED', 'IN_PROGRESS', 'CONFIRMED']
VALID_RESO  = ['FIXED', 'INVALID', 'WONTFIX', 'LATER', 'REMIND', 'DUPLICATE', 'WORKSFORME', 'CANTFIX', 'NEEDINFO', 'TEST-REQUEST', 'UPSTREAM']

# Each zilla instance may have these parameters
# TODO: Add 'nicename' that is used for output to IRC. Defaults to name.capitialize
OPTIONS = [ 'name', 'baseurl', 'dataurl', 'showbugurl', 'reporturl', 'buglisturl', 'template' ]

# Now life gets fun, these are regular expresses to check the above arrays
_STATUS_INPUT = (DONE_STATUS+OPEN_STATUS+['ALL']).uniq.join('|')
STATUS_INPUT_1 = /^(?:#{_STATUS_INPUT})$/
STATUS_INPUT_N = /^(?:#{_STATUS_INPUT})(?:,(?:#{_STATUS_INPUT}))*$/
_RESO_INPUT = (VALID_RESO+['ALL']).uniq.join('|')
RESO_INPUT_1 = /^(?:#{_RESO_INPUT})$/
RESO_INPUT_N = /^(?:#{_RESO_INPUT})(?:,(?:#{_RESO_INPUT}))*$/
_OPTIONS_INPUT = OPTIONS.join('|')
OPTIONS_INPUT_1 = /^(?:#{_OPTIONS_INPUT})$/
OPTIONS_INPUT_N = /^(?:#{_OPTIONS_INPUT})(?:,(?:#{_OPTIONS_INPUT}))*$/

class BugzillaPlugin < Plugin
  Config.register Config::IntegerValue.new('bugzilla.announce_interval',
    :requires_rescan => true,
    :default => 300,
    :desc => "Timer interval for announcements")

  # Exception class to raise when requesting information about an
  # unknown zilla instance.
  class EMissingZilla < ::Exception
    def initialize(zilla)
      @zilla = zilla
    end

    def message
      "Undefined zilla #{@zilla}"
    end
  end

  # Base Bugzilla exception, to avoid repeating the initialize every
  # time in the next exceptions
  class Exception < ::Exception
    def initialize(zilla, bugno)
      @zilla = zilla
      @bugno = bugno
    end
  end

  # Exception class for an error loading the bug data.
  # It is thrown when REXML can't create a new document from the data
  # returned by the HTTP connection
  class EErrorLoading < Exception
    def message
      "Unable to load bug ##{@bugno} from #{@zilla}"
    end
  end

  # Exception class for an error parsing the bug data.
  # It is thrown when the XML document does not contain either a <bug>
  # or <issue> element that is recognised.
  class EErrorParsing < Exception
    def message
      "Unable to parse bug ##{@bugno} from #{@zilla}: no valid document element."
    end
  end

  # Exception class for a not found bug.
  # When asking for a non-existant bug, Bugzilla will return a proper
  # status code of 404 on the XML itself.
  class ENotFound < Exception
    def message
      "Bug ##{@bugno} not found in #{@zilla}"
    end
  end
  
  # Exception class for bugs that are security-locked
  # It is thrown when the XML document does not contain either a <bug>
  # or <issue> element that is recognised.
  class ENotPermitted < Exception
    def message
      "No permissions to access Bug ##{@bugno} in #{@zilla}"
    end
  end

  # Exception class for an invalid bugzilla instance data.
  #
  # When loading a bugzilla instance from the registry, if the data is
  # inconsistent, throw a fit by raising this exception.
  class EInvalidInstance < ::Exception
    def initialize(zilla, extramessage)
      @zilla = zilla
      @extramessage = extramessage
    end

    def message
      "Invalid bugzilla instance #{@zilla}: #{@extramessage}"
    end
  end

  # Class handling the data for a bugzilla instance.
  #
  # This class maintain all the information needed to access the
  # bugzilla, and takes care of getting the information out of it.
  class BugzillaInstance
    attr_reader :name

    def baseurl
      @registry["zilla.#{name}.baseurl"]
    end

    def baseurl=(val)
      val = val[0..-2] if val[-1].chr == '/'
      @registry["zilla.#{name}.baseurl"] = val
      delete_client
    end

    def dataurl
      @dataurl = @registry["zilla.#{name}.dataurl"] unless @dataurl

      unless @dataurl
        guess_dataurl
      end

      return @dataurl
    end

    def dataurl=(val)
      @dataurl = @registry["zilla.#{name}.dataurl"] = val
    end

    def showbugurl
      @showbugurl = @registry["zilla.#{name}.showbugurl"] unless @showbugurl

      unless @showbugurl
        guess_showbugurl
      end

      return @showbugurl
    end

    def showbugurl=(val)
      @showbugurl = @registry["zilla.#{name}.showbugurl"] = val
    end

    def reporturl
      @reporturl = @registry["zilla.#{name}.reporturl"] unless @reporturl

      unless @reporturl
        guess_reporturl
      end

      return @reporturl
    end

    def reporturl=(val)
      @reporturl = @registry["zilla.#{name}.reporturl"] = val
    end

    def buglisturl
      @buglisturl = @registry["zilla.#{name}.buglisturl"] unless @buglisturl

      unless @buglisturl
        guess_buglisturl
      end

      return @buglisturl
    end

    def buglisturl=(val)
      @buglisturl = @registry["zilla.#{name}.buglisturl"] = val
    end

    def template
      @template = @registry["zilla.#{name}.template"] unless @template

      unless @template
      	#@template = "Bug @BUGNO@; \"@DESC@\"; @PRODCOMP@; @STATUS@; @REPORTER@ -> @ASSIGNEE@; @URL@"
      	@template = "@URL@ \"@DESC@\"; @PRODCOMP@; @STATUS@; @REPORTER@:@ASSIGNEE@"
      end

      return @template
    end

    def template=(val)
      @template = @registry["zilla.#{name}.template"] = val
    end

    def lastseenid
      return @registry["zilla.#{name}.lastseenid"]
    end

    def lastseenid=(val)
      @registry["zilla.#{name}.lastseenid"] = val
    end

    def initialize(registry, bot)
      raise EInvalidInstance("", "Missing registry instance") unless registry
      raise EInvalidInstance("", "Missing bot instance") unless bot

      @registry = registry
      @bot = bot
    end

    def create(name, baseurl)
      raise EInvalidInstance("", "Missing instance name") unless name
      raise EInvalidInstance("", "Missing instance base URL") unless baseurl

      @name = name
      self.baseurl = baseurl

      # Do this otherwise the array is not saved properly in the registry
      @registry["zillas"] = (@registry["zillas"] << @name)
    end

    def delete
      @registry["zillas"] = (@registry["zillas"] - [@name])

      OPTIONS.each do |s|
        @registry.delete("zilla.#{name}.#{s}")
      end
    end

    def load(name)
      raise EInvalidInstance("", "Missing instance name") unless name

      @name = name
    end

    # Guess at the public URL to show for a bug.
    def guess_showbugurl
      @showbugurl = baseurl
      @showbugurl += "/" unless baseurl[-1..-1] == "/"
      @showbugurl += "show_bug.cgi?id=@BUGNO@@COMMENT@"
    end

    # Guess at the URL for the XML format of any given bug.
    #
    # We don't need to know a correct bug number for this as we can
    # check the answer for a 404 status code or notfound error.
    def guess_dataurl
      # First off let's see if xml.cgi is present
      begin
        test_dataurl = "#{baseurl}/xml.cgi?id=@BUGNO@"
        test_bugdata = REXML::Document.new(@bot.httputil.get(test_dataurl.gsub("@BUGNO@", "50")))
        if test_bugdata.root.name == "bugzilla"
          @dataurl = test_dataurl
          return
        end
      rescue
        nil
      end

      # If not fall back to asking for the XML data to show_bug.cgi
      begin
        test_dataurl = showbugurl
        test_dataurl += '?' unless test_dataurl =~ ('?')
        test_dataurl += "&ctype=xml"
        test_bugdata = REXML::Document.new(@bot.httputil.get(test_dataurl.gsub("@BUGNO@", "50")))
        if test_bugdata.root.name == "bugzilla"
          @dataurl = test_dataurl
          return
        end
      rescue
        nil
      end

      @dataurl = nil
    end

    # Guess at the default URL to use for generating CSV tables format out of reports.
    def guess_reporturl
      @reporturl = "#{baseurl}/report.cgi?action=wrap&ctype=csv&format=table"
    end

    # Guess at the default URL to use for generating CSV output for a search
    def guess_buglisturl
      @buglisturl = "#{baseurl}/buglist.cgi?ctype=csv&order=bugs.bug_id"
    end

    # Deletes the client object if any
    def delete_client
      # TODO: httpclient does not seem to provide a way to close the
      # connection as of now, until that is implemented this is just a
      # dummy function, and the plugin will leak connections on
      # rescan.

      @client = nil
    end
  
    # TODO: Promote EMAIL_REPLACEMENTS to a config hash instead, with a nice
    # large set of defaults.
    EMAIL_REPLACEMENTS = { 'gentoo.org' => 'g.o', 'gentooexperimental.org' => 'ge.o' }
    def shrink_email(email)
      domain = email.split(/@/)[1]
      if EMAIL_REPLACEMENTS.key?(domain)
        email.sub!(/@#{domain}$/, '@'+EMAIL_REPLACEMENTS[domain])
      end
      return email
    end

    # Return the summary for a given bug.
    def summary(bugno, comment="")
      raise EInvalidInstance.new(self.name, "No XML data URL available") if dataurl == nil

      bugdata = REXML::Document.new(@bot.httputil.get(dataurl.gsub("@BUGNO@", bugno).gsub("@COMMENT@", "")))

      raise EErrorLoading.new(name, bugno) unless bugdata

      # OpenOffice's issuezilla is tricky, they call it issue_status, so
      # we have to consider the alternative in case there is an <issue>
      # as document element.
      bugxml = bugdata.root.get_elements("bug")[0]
      bugxml = bugdata.root.get_elements("issue")[0] unless bugxml

      raise EErrorParsing.new(name, bugno) unless bugxml

      if bugxml.attribute("status_code").to_s == "404" or
          bugxml.attribute("error").to_s.downcase == "notfound"
        raise ENotFound.new(name, bugno)
      end
      bug_error = bugxml.attribute("error").to_s
      if bug_error.length > 0
        # TODO: Create Exception classes for other error modes.
        case bug_error.downcase
        when "notpermitted"
          raise ENotPermitted.new(name, bugno)
        else
          raise EErrorParsing.new(name, bugno)
        end
      end

      product = bugxml.get_text("product").to_s
      component = bugxml.get_text("component").to_s
      product_component =
        "#{product}, #{component}".chomp(", ")

      bug_status = bugxml.get_text("bug_status").to_s
      issue_status = bugxml.get_text("issue_status").to_s
      reso = bugxml.get_text("resolution").to_s

      status = bug_status[0..3]
      status += ", #{issue_status[0..3]}" if issue_status and issue_status.length > 0
      status += ", #{reso[0..3]}" if reso and reso.length > 0

      desc = bugxml.get_text("short_desc").to_s.decode_entities
      reporter = bugxml.get_text("reporter").to_s
      reporter = shrink_email(reporter)
      assignee = bugxml.get_text("assigned_to").to_s
      assignee = shrink_email(assignee)

      mapping = {
	'BUGNO' => bugno,
	'COMMENT' => comment,
	'DESC' => desc,
	'PRODUCT' => product,
	'COMPONENT' => component,
	'PRODCOMP' => product_component,
	'BUGSTATUS' => bug_status,
	'ISSUESTATUS' => issue_status,
	'RESO' => reso,
	'STATUS' => status,
	'REPORTER' => reporter,
	'ASSIGNEE' => assignee,
	'URL' => showbugurl.gsub('@BUGNO@', bugno).gsub('@COMMENT@', comment.length > 0 ? '#c'+comment : '' ),
      }
      output = template.dup
      mapping.each { |k,v|
      	output.gsub!("@#{k}@", v)
      }
      return output
    end

    def add_announcement(channel_name)
      @registry["zilla.#{@name}.announcements"] = Set.new unless @registry["zilla.#{@name}.announcements"]

      @registry["zilla.#{@name}.announcements"] = @registry["zilla.#{@name}.announcements"] + [channel_name]
    end

    def delete_announcement(channel_name)
      return unless @registry["zilla.#{@name}.announcements"]

      @registry["zilla.#{@name}.announcements"] = @registry["zilla.#{@name}.announcements"] - [channel_name]
    end

    def announce
      return unless @registry["zilla.#{@name}.announcements"]
      recent_url = nil
      if lastseenid == nil
        recent_url = "chfieldfrom=-6h&chfieldto=Now&chfield=%5BBug+creation%5D"
      else
        recent_url = "field0-0-0=bug_id&remaction=&type0-0-0=greaterthan&value0-0-0=#{lastseenid}"
      end

      buglist = search(recent_url)
      buglist.delete_at(0)
      upper_bound = [buglist.size, 5].min
      buglist[-upper_bound..-1].each do |bug|
        bugsummary = summary(bug[0])

        @registry["zilla.#{@name}.announcements"].each do |chan|
          @bot.say chan, "New bug: #{bugsummary}"
        end
      end

      self.lastseenid = buglist[-1][0].to_i if buglist.size > 0
    end

    def search(urlparams, params = nil)
      url = buglisturl + '&' + urlparams
      searchdata = CSV.parse(@bot.httputil.get(url))
      return searchdata
    end

    def report(urlparams, params = nil)
      url = "#{reporturl}&#{urlparams}"
      reportdata = CSV.parse(@bot.httputil.get(url))
      if params and params[:total]
        sum = 0
        column = params[:total]
        reportdata.each do |row|
          if row[column] =~ /^[0-9]+$/
            sum += row[column].to_i
          end
        end
        reportdata << ["Total", sum]
      end
      return reportdata
    end

  end

  # Initialise the bugzilla plugin.
  #
  def initialize
    super

    @zillas = {}

    if @registry["zillas"]
      @registry["zillas"].each do |zilla|
        instance = BugzillaInstance.new(@registry, @bot)
        instance.load(zilla)
        @zillas[zilla] = instance
      end
    else
      @registry["zillas"] = Array.new
    end

    @defaults = Hash.new
    if @registry["channel_defaults"]
      channel_defaults_reload
    else
      @registry["channel_defaults"] = Hash.new
    end

    @polling_timer = @bot.timer.add(@bot.config['bugzilla.announce_interval']) {
      poll_zillas
    }
  end

  # Cleanup the plugin on reload
  #
  # This function is used to remove timers and close HTTPClient
  # instances, otherwise they'll be kept open with no good reason.
  def cleanup
    @bot.timer.remove(@polling_timer)

    super
  end

  # Check for the existence of zilla in the registry.
  # This function checks if a given zilla is present in the registry
  # file by checking for presence of a zilla. entry. It raises
  # an exception if it is missing.
  def check_zilla(name)
    raise EMissingZilla.new(name) unless
      @zillas.has_key?(name)
  end

  # Given a user or channel name that is communicating with us, check to see if
  # we have a specific zilla to use for them.
  def get_zilla(m)
    replyto = nil
    replyto = m.replyto.to_s if m.is_a?(Irc::UserMessage)
    return nil unless replyto
    return nil unless @defaults[replyto]
    return nil unless @defaults[replyto][:zilla]
    return @zillas[@defaults[replyto][:zilla]]
  end

  # Should we be lurking here to watch for bugs?
  def lurk?(m)
    replyto = nil
    replyto = m.replyto.to_s if m.is_a?(Irc::UserMessage)
    return false unless replyto
    return false unless @defaults[replyto]
    return true if @defaults[replyto][:eavesdrop]
  end

  # Function "eavesdropping" on all the messages the bot receives.
  #
  # This function is used to check if an user requested bug
  # information inline in the text of a message rather than directly
  # to the bot.
  def listen(m)
    return if m.address?
    return unless lurk?(m)
    return if m.message !~ /\bbug(?:[[:space:]]*)?#?([0-9]+)(?:(?:#c| comment #?)([0-9]+))?/i
    bugno = $1
    comment = $2 || ""
    bugno.gsub!(/^#/,'')
    comment.gsub!(/^#c?/,'')
    zilla = get_zilla(m)
    m.reply zilla.summary(bugno, comment)
  end

  # Function checking when a new channel is joined
  #
  # This function will calculate the channel default.
  def join(m)
    return unless m.address?
    channel_defaults_reload(m)
  end

  # This is the main function of the plugin, answering to bug information
  # requests from users. We provide a form that takes a zilla instance name, as
  # well as a form that just figures out the zilla name based on the channel or
  # user. They DO however have seperate commands, because the automatic logic
  # can be easily confused:
  # <@GentooDev> !bug 240182 <--- hey SomeGuy, look at this one
  # In both cases, bug aliases are supported.
  #
  # Answer to a bug information request, long form.
  def buglong(m, params)
    begin
      comment = ""
      if params[:garbage] == 'comment' and params[:comment] =~ /^(?:#|#c)?([0-9]+)$/
        comment = $1
      end
      if params[:number].chomp("#") =~ /#?([0-9]+)(?:(?:#c|comment #?)([0-9]+))?/i
        bugno = $1
        comment = $2 if $2
        bugno.gsub!(/^#/,'')
      else
        m.reply "Wrong parameters - invalid bugnumber, see 'help bug' for help."
        return
      end
      comment.gsub!(/^#c?/,'')

      if params[:zilla] and bugno
        check_zilla(params[:zilla])
        zilla = @zillas[params[:zilla]]
      else
        m.reply "Wrong parameters - unknown zilla, see 'help bug' for help."
        return
      end
      m.reply zilla.summary(bugno, comment)
    rescue ::Exception => e
      m.reply e.message
    end
  end

  # Answer to a bug information request, short form.
  def bug(m, params)
    begin
      comment = ""
      if params[:garbage] == 'comment' and params[:comment] =~ /^(?:#|#c)?([0-9]+)$/
        comment = $1
      end
      if params[:number].chomp("#") =~ /#?([0-9]+)(?:(?:#c|comment #?)([0-9]+))?/i
        bugno = $1
        comment = $2 if $2
        bugno.gsub!(/^#/,'')
      else
        m.reply "Wrong parameters - invalid bugnumber, see 'help bug' for help."
        return
      end
      comment.gsub!(/^#c?/,'')

      zilla = get_zilla(m)

      if not zilla
        m.reply "Wrong parameters - unknown zilla, see 'help bug' for help."
      end
      m.reply zilla.summary(bugno, comment)
    rescue ::Exception => e
      m.reply e.message
    end
  end

  # Produce support of all bug status counts
  def bugstats(m, params)
    begin
      if params[:zilla]
        check_zilla(params[:zilla])
        zilla = @zillas[params[:zilla]]
      elsif get_zilla(m)
        zilla = get_zilla(m)
      else
        m.reply "Wrong parameters (no bugzilla specified), see 'help bugstats' for help."
        return
      end

      title = "#{zilla.name.capitalize} bug status totals"

      # Build our URL
      query = 'x_axis_field=bug_status'
      #status.each { |s| query += "&bug_status=#{s}" }
      #reso.each { |r| query += "&resolution=#{r}" }

      # Get the data
      results = zilla.report(query, {:total => 1})

      # Remove the CSV header
      results.shift

      # Display output
      m.reply title+" "+(results.map { |b| "#{b[0]}(#{b[1]})" }.join(' '))

    rescue ::Exception => e
      m.reply e.message
    end
  end

  # Produce architecture statistics using Bugzilla reports
  #
  # Using the bugzilla reporting functionality, we can produce a
  # simple report of bugs by architecture, for any specific
  # status/resolution.
  # x_axis_field=rep_platform
  # x_axis_field=rep_platform&bug_status=UNCONFIRMED&bug_status=NEW&bug_status=ASSIGNED
  # x_axis_field=rep_platform&resolution=FIXED&resolution=INVALID&resolution=WONTFIX
  def archstats(m, params)
    begin
      # First of all, we need to fix up the input
      # as rbot gets it confused sometimes
      # First we take them in the original order
      begin
        newparams = []
        newparams << params[:zilla] if params[:zilla]
        newparams << params[:status] if params[:status]
        newparams << params[:reso] if params[:reso]
        params = newparams
      end

      zilla = nil
      status = nil
      reso = nil

      #m.reply "p:#{params.inspect} s=#{status} r=#{reso} z=#{zilla}"

      params.each_index do |i|
        v = params[i]
        next if v.nil?
        if v =~ STATUS_INPUT_N
          status = v
          params.delete_at(i)
          break
        end
      end
      #m.reply "p:#{params.inspect} s=#{status} r=#{reso} z=#{zilla}"

      params.each_index do |i|
        v = params[i]
        next if v.nil?
        if v =~ RESO_INPUT_N
          reso = v
          params.delete_at(i)
          break
        end
      end
      #m.reply "p:#{params.inspect} s=#{status} r=#{reso} z=#{zilla}"

      case params.length
      when 1
        zilla = params[0]
        check_zilla(zilla)
        zilla = @zillas[zilla]
      when 0
        zilla = get_zilla(m)
      else
        zilla = nil
        m.reply "Wrong parameters, see 'help archstats' for help."
        return
      end
      #m.reply "p:#{params.inspect} s=#{status} r=#{reso} z=#{zilla.to_s}"

      if zilla.nil?
        m.reply "Wrong parameters (no bugzilla provided), see 'help archstats' for help."
        return
      end

      # Now the real defaults
      status = 'ALL' unless status
      reso = '' unless reso

      # Validate all input
      status = status.split(/,/)
      exclude_reso = true
      status.each do |s|
          exclude_reso = false if DONE_STATUS.include?(s) or s == 'ALL'
          raise ArgumentError.new("Invalid status (#{s}), see 'help archstats' for help.") if not DONE_STATUS.include?(s) and not OPEN_STATUS.include?(s) and s != 'ALL'
      end
      reso = [] if exclude_reso
      reso = reso.split(/,/) if reso and reso.is_a?(String)
      reso.each do |r|
            raise ArgumentError.new("Invalid resolution (#{r}), see 'help archstats' for help.") if not VALID_RESO.include?(r)
      end

      # Nice header
      title = "#{zilla.name.capitalize} platform bug totals"
      if status.length > 0  or reso.length > 0
          title += " (#{status.join(',')}"
          title += "/#{reso.join(',')}" if reso.length > 0
          title += ")"
      end

      # Special cases
      if status.include?('ALL')
        status << 'OPEN'
        status << 'DONE'
        status.delete('ALL')
      end

      if status.include?('OPEN')
        status += OPEN_STATUS
        status.uniq!
        status.delete('OPEN')
      end

      if status.include?('DONE')
        status += DONE_STATUS
        status.uniq!
        status.delete('DONE')
      end

      # Build our URL
      query = 'x_axis_field=rep_platform'
      status.each { |s| query += "&bug_status=#{s}" }
      reso.each { |r| query += "&resolution=#{r}" }

      # Get the data
      results = zilla.report(query, {:total => 1})

      # Remove the CSV header
      results.shift

      # Display output
      m.reply title+" "+(results.map { |b| "#{b[0]}(#{b[1]})" }.join(' '))

    rescue ::Exception => e
      m.reply e.message
    end
  end

  # Adds a new instance to the available instances
  #
  # This function creates a new BugzillaInstance object, loads the new
  # data on it, and then adds it to the hash of zillas.
  #
  # Only the base url of the instance is needed, the rest of the
  # parameters will either default or get guessed by the bot.
  #
  # To override the settings, use the set zilla command
  def instance_add(m, params)
    if @zillas.has_key?("#{params[:zilla]}")
      m.reply "Bugzilla #{params[:zilla]} already present."
      return
    end

    instance = BugzillaInstance.new(@registry, @bot)
    instance.create(params[:zilla], params[:baseurl])
    @zillas[params[:zilla]] = instance

    m.reply "Added #{params[:zilla]}"
  end

  # Set parameters for the given bugzilla
  #
  # There is a special bit of behavior here. If you want to UNSET an option, so
  # that the default is used, then set it to 'nil'.
  def instance_set(m, params)
    begin
      # This is to save us from having an 'unset' command
      params[:value] = nil if params[:value].match(/^nil$/)

      # We are evil
      @zillas[params[:zilla]].send("#{params[:setting]}=", params[:value])

    rescue ::Exception => e
      m.reply e.message
    end
  end

  # Removes an instance to the available instances.
  #
  # The opposite of instance_add, this function deletes an instance of
  # Bugzilla or Issuezilla from the registry.
  def instance_delete(m, params)
    @zillas[params[:zilla]].delete
    @zillas.delete(params[:zilla])

    m.okay
  end

  # Shows the list of available instances to the users.
  def instance_list(m, params)
    m.reply @registry["zillas"].join(", ")
  end

  # Show the information known about the bugzilla.
  #
  # This function emits a summary of the data regarding the bugzilla,
  # its output can be used to set the bugzilla back up again on this
  # or other instances.
  def instance_show(m, params)
    begin
      check_zilla(params[:zilla])

      msg = "#{params[:zilla]}"
      for s in OPTIONS
        if params[:full] == 'full'
          o = @zillas[params[:zilla]].send(s)
        elsif params[:full] == 'registry'
          o = @registry['zilla.' + params[:zilla] + ".#{s}"]
        end
        msg += " #{s}: #{o}" if o
      end

      m.reply msg
    rescue ::Exception => e
      m.reply e.message
    end
  end

  # Reloads the defaults for the current joined channels
  #
  # This function scans through the list of channel defaults found in
  # the registry and report them in the locally accessed objects.
  def channel_defaults_reload(m=nil)
    begin
      @registry["channel_defaults"].each do |chanrexp, defaults|
        if chanrexp =~ /^\/.*\/$/
          chanrexp = Regexp.new(chanrexp[1..-2], Regexp::IGNORECASE)
          @bot.server.channels.each do |chan|
            _channel_defaults_reload_set(chan.to_s, defaults) if chan.to_s =~ chanrexp
          end
        else
          _channel_defaults_reload_set(chanrexp, defaults)
        end
      end
    rescue ::Exception => e
      if m
        m.reply e.message
      else
        debug(e.message + "\n" + e.backtrace.join("\n\t"))
      end
    end
  end

  # Helper function only
  def _channel_defaults_reload_set(chan, defaults)
    @defaults[chan] = {
      :eavesdrop => defaults[:eavesdrop],
      :zilla => defaults[:zilla]
    }
  end

  # Sets the default zilla for the given channel regexp
  #
  # The default zilla is the zilla used when an user requests info
  # about a bug number, without saying which zilla to take the data
  # from.
  def channel_defaults_set(m, params)
    begin
      @registry["channel_defaults"] = @registry["channel_defaults"].merge(params[:channel] => { :zilla => params[:zilla], :eavesdrop => params[:eavesdrop] == "on" })
      channel_defaults_reload

      m.okay
    rescue ::Exception => e
      m.reply e.message
    end
  end

  # Unsets the default zilla for the given channel regexp
  # TODO: This is broken
  def channel_defaults_unset(m, params)
    begin
      @registry["channel_defaults"].delete(params[:channel])
      channel_defaults_reload

      m.okay
    rescue ::Exception => e
      m.reply e.message
    end
  end

  # Display the list of channels/users for which we have defaults
  def channel_defaults_list(m, params)
    begin
      m.reply @registry["channel_defaults"].keys.join(', ')
    rescue ::Exception => e
      m.reply e.message
    end
  end

  # Show the default for a given channel/user
  def channel_defaults_show(m, params)
    begin
      defl = @registry["channel_defaults"][params[:channel]]
      m.reply "#{params[:channel]}: #{defl.inspect}"
    rescue ::Exception => e
      m.reply e.message
    end
  end

  def channel_defaults_dump(m, params)
    begin
      m.reply @defaults.inspect
    rescue ::Exception => e
      m.reply e.message
    end
  end

  # Adds announcement for bugs on the given zilla to the channel
  #
  # When this function is called, the given zilla is added to the list
  # of zilla to announce in the given channel.
  #
  # Zillas being announced mean they get polled at a fixed interval
  # for new bugs, and the summary for those is sent to the channel
  # asking for them.
  #
  # Actually, it's the channel being added to the announcement for
  # the given zilla, as that makes it quite easier to track down which
  # ones to poll.
  def channel_announcement_add(m, params)
    begin
      @zillas[params[:zilla]].add_announcement params[:channel]
      m.okay
    rescue ::Exception => e
      m.reply e.message
    end
  end

  # Removes an announcement of a given zilla on a channel.
  #
  # This basically is an undo function for the function above.
  def channel_announcement_delete(m, params)
    begin
      @zillas[params[:zilla]].delete_announcement(params[:channel])
      m.okay
    rescue ::Exception => e
      m.reply e.message
    end
  end

  def poll_zillas
    @zillas.each do |name, zilla|
      begin
        zilla.announce
      rescue Exception => e
        debug(e.message + "\n" + e.backtrace.join("\n\t"))
      end
    end
  end

  # Help strings to give the users when they are asking for it.
  @@help_zilla = {
    "bugzilla" => "Bugzilla IRC interface: #{Bold}bug#{Bold}|#{Bold}archstats#{Bold}|#{Bold}zilla#{Bold} (zilla contains all admin and info tools)",

    "bug" => "bug #{Bold}number#{Bold} : show the data about given bugzilla's bug # or alias. See also #{Bold}!bugl#{Bold}",
    "bugl" => "bug #{Bold}bugzilla#{Bold} #{Bold}number#{Bold} : show the data about given bugzilla's bug # or alias.",

    "archstats" => "archstats #{Bold}[bugzilla]#{Bold} #{Bold}[status]#{Bold} #{Bold}[reso]#{Bold} : show architecture summaries for given bug statuses.",

    "zilla"                 => "zilla #{Bold}instance#{Bold}|#{Bold}default#{Bold}|#{Bold}source#{Bold}|#{Bold}credits#{Bold} : manages bugzilla lists.",
    "zilla instance"        => "zilla instance #{Bold}add#{Bold}|#{Bold}delete#{Bold}|#{Bold}set#{Bold}|#{Bold}show#{Bold}|#{Bold}list#{Bold} : handle bugzilla instances",
    "zilla instance add"    => "zilla instance add #{Bold}name#{Bold} #{Bold}baseurl#{Bold} : adds a new bugzilla",
    "zilla instance delete" => "zilla instance delete #{Bold}name#{Bold} : delete the named bugzilla",
    "zilla instance set"    => "zilla instance set #{Bold}name#{Bold} #{Bold}option#{Bold} #{Bold}value#{Bold} : set the option to a given value for the zilla. Valid options are " + OPTIONS.join(", "),
    "zilla instance list"   => "zilla instance list : shows current querable bugzilla instancess",
    "zilla instance show"   => "zilla instance show #{Bold}name#{Bold} : shows the configuration for the named bugzilla.",

    "zilla default"       => "zilla default #{Bold}set#{Bold}|#{Bold}unset#{Bold}|#{Bold}list#{Bold}|#{Bold}show#{Bold} : handles default zilla for channels",
    "zilla default set"   => "zilla default set #{Bold}channel_name#{Bold} #{Bold}zilla_name#{Bold} #{Bold}eavesdrop_on|off#{Bold} : sets the default zilla for a given channel, use on or off to enable or disable eavesdropping for bug references.",
    "zilla default unset" => "zilla default unset #{Bold}channel_name#{Bold} : unsets the default zilla for a given channel",
    "zilla default list"  => "zilla default list : shows all channels for which a default is set",
    "zilla default show"  => "zilla default show #{Bold}channel_name#{Bold} : show the default for a given channel",

    # TODO: Document the announcement stuff

    "zilla source"  => "zilla source : shows a link to the plugin's sources.",
    "zilla credits" => "zilla credits : shows the plugin's credits and license."
  }

  def help(plugin, topic = "")
    cmd = plugin
    cmd += " "+topic if topic.length > 0
    if @@help_zilla.has_key?(cmd)
      return @@help_zilla[cmd]
    else
      return "no help available for #{cmd}"
    end
  end

  def plugin_sources(m, params)
    m.reply "http://www.flameeyes.eu/projects#rbot-bugzilla"
  end

  def plugin_credits(m, params)
    m.reply "Copyright (C) 2005-2008 Diego Pettenò & Robin H. Johnson. Distributed under Affero General Public License version 3."
  end

end

plugin = BugzillaPlugin.new

plugin.default_auth( 'modify', false )
plugin.default_auth( 'view', true )

plugin.map 'bug :number :garbage :comment',
  :requirements => {
    :number => /^[^ ]+$/,
    :garbage => /^[^ ]+$/,
    :comment => /^[^ ]+$/,
  },
  :defaults => { :garbage => "", :comment => "" },
  :action => 'bug',
  :thread => 'yes',
  :auth_path => 'view'

plugin.map 'bugl :zilla :number :garbage :comment',
  :requirements => {
    :number => /^[^ ]+$/,
    :zilla => /^[^ ]+$/,
    :garbage => /^[^ ]+$/,
    :comment => /^[^ ]+$/,
  },
  :defaults => { :garbage => "", :comment => "" },
  :action => 'buglong',
  :thread => 'yes',
  :auth_path => 'view'

plugin.map 'bugstats :zilla',
  :requirements => {
    :zilla => /^[^ ]+$/,
  },
  :defaults => {
    :zilla => nil,
  },
  :action => 'bugstats',
  :thread => 'yes',
  :auth_path => 'view'

plugin.map 'archstats :zilla :status :reso',
  :requirements => {
    :status => STATUS_INPUT_N,
    :reso => RESO_INPUT_N,
    :zilla => /^[^ ]+$/,
  },
  :defaults => {
    :zilla => nil,
    :status => nil,
    :reso => nil,
  },
  :action => 'archstats',
  :thread => 'yes',
  :auth_path => 'view'

plugin.map 'zilla instance add :zilla :baseurl',
  :action => 'instance_add',
  :requirements => {
    :zilla => /^[^ ]+$/,
    :baseurl => /^https?:\/\/.*/,
  },
  :auth_path => 'modify'

plugin.map 'zilla instance set :zilla :setting :value',
  :action => 'instance_set',
  :requirements => {
    :zilla => /^[^\. ]+$/,
    :setting => OPTIONS_INPUT_1,
  },
  :auth_path => 'modify'

plugin.map 'zilla instance delete :zilla',
  :action => 'instance_delete',
  :requirements => {
    :zilla => /^[^ ]+$/
  },
  :auth_path => 'modify'

plugin.map 'zilla instance list',
  :action => 'instance_list',
  :auth_path => 'view'

plugin.map 'zilla instance show :zilla :full',
  :action => 'instance_show',
  :requirements => {
    :zilla => /^[^ ]+$/,
    :full => /^full|registry$/,
  },
  :defaults => { :full => "registry" },
  :auth_path => 'view'

plugin.map 'zilla default set :channel :zilla :eavesdrop',
  :action => 'channel_defaults_set',
  :requirements => {
    #:channel => /^[^\/][^ ]+[^\/]$|^\/#[^ ]+\/$/,
    :channel => /^[^ ]+$/,
    :zilla => /^[^ ]+$/,
    :eavesdrop => /^(?:on|off)$/,
  },
  :defaults => { :eavesdrop => "off" },
  :auth_path => 'modify'

plugin.map 'zilla default unset :channel',
  :action => 'channel_defaults_unset',
  :requirements => {
    #:channel => /^[^\/][^ ]+[^\/]$|^\/#[^ ]+\/$/,
  },
  :auth_path => 'modify'

plugin.map 'zilla default list',
  :action => 'channel_defaults_list',
  :auth_path => 'view'

plugin.map 'zilla default show :channel',
  :action => 'channel_defaults_show',
  :requirements => {
    :channel => /^[^\/][^ ]+[^\/]$|^\/#[^ ]+\/$/,
  },
  :auth_path => 'view'

plugin.map 'zilla default dump',
  :action => 'channel_defaults_dump',
  :thread => 'yes',
  :auth_path => 'view'

plugin.map 'zilla announcement add :zilla :channel',
  :action => 'channel_announcement_add',
  :requirements => {
    :channel => /^#[^ ]+$/,
    :zilla => /^[^ ]+$/
  },
  :auth_path => 'modify'

plugin.map 'zilla announcement remove :zilla :channel',
  :action => 'channel_announcement_delete',
  :requirements => {
    :channel => /^#[^ ]+$/,
    :zilla => /^[^ ]+$/
  },
  :auth_path => 'modify'

# TODO: add the full announcement engine after discussions with solar. Probably
# need a full input file to handle ordering.

plugin.map 'zilla source',
  :action => 'plugin_sources',
  :auth_path => 'view'

plugin.map 'zilla credits',
  :action => 'plugin_credits',
  :auth_path => 'view'
