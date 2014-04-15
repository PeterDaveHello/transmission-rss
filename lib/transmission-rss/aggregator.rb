require 'etc'
require 'fileutils'
require 'open-uri'
require 'rss'

libdir = File.dirname(__FILE__)
require File.join(libdir, 'log')
require File.join(libdir, 'callback')

module TransmissionRSS
  # Class for aggregating torrent files through RSS feeds.
  class Aggregator
    extend Callback
    callback :on_new_item # Declare callback for new items.

    attr_accessor :feeds

    def initialize(feeds = [])
      @feeds = feeds
      @seen = []

      # Initialize log instance.
      @log = Log.instance

      # Generate path for seen torrents store file.
      @seenfile = File.join \
        Etc.getpwuid.dir,
        '/.config/transmission/seen-torrents.conf'

      # Make directories in path if they are not existing.
      FileUtils.mkdir_p File.dirname(@seenfile)

      # Touch seen torrents store file.
      unless File.exists? @seenfile
        FileUtils.touch @seenfile
      end

      # Open file, read torrent URLs and add to +@seen+.
      open(@seenfile).readlines.each do |line|
        @seen.push line.chomp
      end

      # Log number of +@seen+ URIs.
      @log.debug @seen.size.to_s + ' uris from seenfile'
    end

    # Get file enclosures from all feeds items and call on_new_item callback
    # with torrent file URL as argument.
    def run(interval = 600)
      @log.debug 'aggregator start'

      while true
        feeds.each do |url|
          url = URI.encode(url)
          @log.debug 'aggregate ' + url

          begin
            content = open(url).readlines.join("\n")
            items = RSS::Parser.parse(content, false).items
          rescue Exception => e
            @log.debug "retrieval error (#{e.message})"
            next
          end

          items.each do |item|
            link = item.enclosure.url rescue item.link
   
            # Item contains no link.
            next if link.nil?

            # Link is not a String directly.
            link = link.href if link.class != String

            # The link is not in +@seen+ Array.
            unless seen? link
              @log.debug 'on_new_item event ' + link
              begin
                on_new_item link
              rescue Errno::ECONNREFUSED
#             @log.debug 'not added to seenfile'
              else
                add_seen link
              end
            end
          end
        end

        sleep interval
      end
    end

    # To add a link into the list of seen links.
    def add_seen(link)
      @seen.push link

      File.open(@seenfile, 'w') do |file|
        file.write @seen.join("\n")
      end
    end

    # To test if a link is in the list of seen links.
    def seen?(link)
      @seen.include? link
    end
  end
end
