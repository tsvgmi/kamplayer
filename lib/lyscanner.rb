#!/usr/bin/env ruby
#---------------------------------------------------------------------------
# File:        vnc.rb
# $Id: lyscanner.rb 6 2010-11-26 10:59:34Z tvuong $
#---------------------------------------------------------------------------
#+++
require File.dirname(__FILE__) + "/../../etc/toolenv"
require 'yaml'
require 'fileutils'
require 'tempfile'
require 'open-uri'
require 'hpricot'
require 'mtool/core'
require 'mtool/rename'

class VnhimPage
  attr_reader :type

  def initialize(url)
    @url = url
    @doc = LyScanner.page_load(url)
    if url =~ /(http:\/\/[^\/]+)/i
      @baseurl = $1
    end
    if url =~ /\/(artist|viewartist)(-\d+)?\//
      @type = $1.intern
    end
  end

  def children
    result = []
    author = self.class.extract_name(@url)
    @doc.search("a.lyric").each do |aref|
      song  = aref.html.to_s
      href  = "#{@baseurl}/#{aref['href']}"
      tsong = self.class.extract_name(href)
      result << [tsong, author, href]
    end
    result
  end

  def lyrics
    ltext = @doc.search(".lyric_text")
    ltext.html
  end

  def self.extract_name(string)
    File.basename(string).sub(/\.html$/,'').gsub(/-/, ' ')
  end
end

class Video4VietPage
  attr_reader :type

  def self.extract_name(string)
    File.basename(string).sub(/^.*\&q=/,'').
        sub(/\&.*$/,'').gsub(/\+/, ' ')
  end

  def initialize(url)
    require 'digest/md5'

    @url  = url
    @doc  = LyScanner.page_load(url)
    if url =~ /(http:[^\?]+)/i
      @baseurl = $1
    end
    if url =~ /act=(search|view)/
      @type = $1.intern
      @song = Video4VietPage.extract_name(url)
    end
  end

  def children
    result      = []
    index       = 0
    tsong, href = nil, nil
    @doc.search("td.lyricrow a").each do |aref|
      if index == 0
        tsong = aref.html.strip
        href  = "#{@baseurl}#{aref['href']}"
      else
        author = aref.html.strip
        if href
          result << [@song, author, href]
          href   = nil
          author = nil
        else
          Plog.error "No href found for #{tsong}/#{author}"
        end
      end
      index = (index == 0) ? 1 : 0
    end
    result
  end

  def lyrics
    ltext = nil
    @doc.search("center").each do |ablock|
      if ablock.search("h3")
        ltext = ablock
        break
      end
    end
    if ltext
      return ltext.html
    else
      return nil
    end
  end
end

# Helper for vnc script.
class LyScanner
  extendCli __FILE__

  def self.scan_auth(rurl)
    DbAccess.instance
    nhpage = VnhimPage.new(rurl)
    nhpage.children.each do |tsong, author, href|
      puts "#{author} #{tsong} #{href}"
      case nhpage.type
      when :artist
        scan_auth(href)
      when :viewartist
        Lyric.update_content(:author=>author, :name=>tsong, :url=>href)
      end
    end
    true
  end

  def self.vid4scan(*title)
    require 'cgi'

    title = CGI::escape(title.join(' '))
    rurl  = "http://www.video4viet.com/lyrics.html?act=search&q=#{title}&type=title"
    nhpage = Video4VietPage.new(rurl)
    if getOption(:update)
      DbAccess.instance
      nhpage.children.each do |tsong, author, href|
        Lyric.update_content(:author=>author, :name=>tsong, :url=>href)
        puts "#{tsong}, #{author}, #{href}"
      end
    else
      return nhpage.children.to_yaml
    end
  end

  def self.update_lyrics(cfile)
    DbAccess.instance
    Lyric.transaction do
      YAML.load(File.read(cfile)).each do |irec|
        Lyric.update_content(irec)
      end
    end
  end
  
  def self.update_count
    DbAccess.instance
    Lyric.transaction do
      Lyric.find(:all, :order=>'name').each do |r|
        if r.songs.size > 0
          r.scount = r.songs.size.to_i
          r.save_wait
          print "."
          STDOUT.flush
        end
      end
    end
    puts
  end

  def self.load_lyrics
    DbAccess.instance
    Lyric.find(:all, :conditions=>'scount>0 and content is null', :order=>'name').each do |r|
      r.content = VnhimPage.new(r.url).lyrics
      r.save_wait
      p r
    end
    true
  end

  def self.abbrev_lyrics
    DbAccess.instance
    Lyric.find(:all, :conditions=>'content is not null', :order=>'name').each do |r|
      r.abcontent = r.content[0..120].gsub(/<br *\/?>/i, '')
      r.save_wait
      p r.abcontent
    end
    true
  end

  def self.page_load(url)
    require 'hpricot'
    require 'digest/md5'

    sig = Digest::MD5.hexdigest(url)
    cfile = "/tmp/#{sig}.html"
    unless test(?f, cfile)
      Plog.info "Caching #{url} to #{cfile}"
      begin
        fid  = open(url)
        page = fid.read
        fid.close
        fod  = File.open(cfile, "w")
        fod.puts(page)
        fod.close
      rescue => errmsg
        page = ""
        p errmsg
      end
    else
      page = File.read(cfile)
    end
    Hpricot(page)
  end
end

if (__FILE__ == $0)
  LyScanner.handleCli(
        ['--update',  '-u', 0]
        )
end

