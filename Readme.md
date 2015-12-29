Drop-in replacement for Gentoo's rbot-based willikins chat bot

Setup
======
Since rbot is broken in Gentoo, this setup is for running rbot using
git sources under the local user.

 - Use portage to install some of the deps for rbot:

         USE="nls shorturl timezone" emerge -ova =net-irc/rbot-0.9.15_p20131020-r1

 - Merge the rest of the deps:

         emerge -va dev-ruby/mechanize dev-ruby/htmlentities

 - Clone rbot repository and clone this repository inside rbot:

         git clone git://github.com/ruby-rbot/rbot.git
         cd rbot && git clone --recursive git://github.com/gktrk/gentoo-rbot.git

Configuration
=============
Edit config.yaml file under gentoo-rbot to suit your needs.  Fields of
interest are:

 - auth.password: get something random
 - irc.nick, irc.user: specify the name for the bot
 - irc.join.channels: specify the channel name for the bot

Running
=======
Use the rbot's launch_here script:

    ruby20 ./launch_here.rb gentoo-rbot

Or, add '-b' to run is as a daemon:

    ruby20 ./launch_here.rb -b gentoo-rbot

Post-Setup
==========
You want to set up gentoo as the default bugzilla. Make sure you
authorize yourself to the bot using auth command:

    /msg <bot-name> auth <auth.password field in config.yaml>

Run the following command to set gentoo as the default bugzilla:

    /msg <bot-name> zilla default set <#insert-channel-name-here> gentoo on

Create the package list for gentoo module (for commands such as meta):

    qsearch -a > /dev/shm/qsearch.txt

Running it as init service
==========================
Edit config.yaml under gentoo-rbot to use absolute paths. Because the
code is using rbot git sources, the init script needs to be adjusted
for that.
