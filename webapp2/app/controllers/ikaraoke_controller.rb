class MenuEntry
  attr_reader :caption, :url

  def initialize(caption, url)
    @caption = caption
    @url     = url
  end
end

class IkaraokeController < ApplicationController
  layout 'ikaraoke'

  protect_from_forgery :except=>[:search, :settings]

  acts_as_iphone_controller

  def index
    #@page_refresh = 30
    @playlist = PlayList.find_by_name('mpshell', :include=>[:songs])
    @iphone_menu = [
      MenuEntry.new("Songs",     :action=>:songs),
      MenuEntry.new("Playlist",  :action=>:playlist),
      MenuEntry.new("Settings",  :action=>:settings),
      MenuEntry.new("Stats",     :action=>:stats)
    ]
  end

  def playlist
    @page_refresh = 30
    @playlist     = PlayList.find_by_name('mpshell', :include=>[:songs])
    render :layout=>false
  end

  def command
    cid = params[:id]
    raise 222
    playlist   = PlayList.find_by_name('mpshell', :include=>[:songs])
    ajx_return = "NG"
    case cid
    when 'admin'
      session[:admin] = !session[:admin]
      return redirect_to :action=>:search
    when 'clap'
      sfiles = Dir.glob("sound/*.wav")
      if (fcount = sfiles.size) > 0
        sfile = sfiles[rand(fcount)]
        system "afplay --volume 8 #{sfile} &"
      end
    when 'next'
      playlist.song_step(1)
    when 'pause'
      Player.send "pause"
    when 'previous'
      playlist.song_step(-1)
    when 'rewind'
      Player.send "seek 1 2"
    when 'voice', 'karaoke'
      csong = playlist.current_song
      csong.normalize(cid.intern)
    end
    return render :text=>ajx_return
  end

  def play_in_queue
    item = params[:id]
    song = Song.find_by_id(item.to_i)
    if song
      playlist = PlayList.find_by_name('mpshell', :include=>[:songs])
      index    = 0
      playlist.songs.each do |asong|
        if asong.id == song.id
          break
        end
        index += 1
      end
      offset = index - playlist.curplay
      if offset != 0
        playlist.song_step(offset, true)
      end
    end
    redirect_to :action=>:playlist
  end

  def settings
    if request.post?
      playlist = PlayList.find_by_name('mpshell', :include=>[:songs])
      [:repeat, :shuffle, :karaoke].each do |aparm|
        if value = params[aparm]
          session[aparm] = value
          case aparm
          when :karaoke
            csong = playlist.current_song
            csong.normalize(value == "true" ? :karaoke : :voice)
          end
        end
      end
      redirect_to :action=>:index
    else
      render :layout=>false
    end
  end

  def search
    wclause = []
    logger.debug params.inspect
    [:artist, :song, :author].each do |aparm|
      if (value = params[aparm]) && !value.empty?
        if value == "Unknown"
          wclause << "#{aparm} is null"
        else
          wclause << "#{aparm} like '%#{value}%'"
        end
      end
    end
    logger.debug wclause
    if wclause.size > 0
      conditions = wclause.join(' and ')
      @records   = Song.find(:all, :conditions=>conditions,
              :order=>'song,artist', :limit=>2000)
    else
      @records = []
    end
    render :layout=>false
  end

  def queue
    item    = params[:id]
    playnow = params[:playnow]
    song    = Song.find(item.to_i)
    if song
      playlist = PlayList.find_by_name('mpshell', :include=>[:songs])
      if playnow && !playnow.empty?
        playlist.add_song(song, true)
      else
        playlist.add_song(song, false)
      end
    end
    redirect_to :action=>:playlist
  end

  def add_all
    items = params[:ids]
    reset = params[:reset]
    songlist = []
    items.split(/,/).each do |item|
      asong = Song.find(item.to_i)
      if asong
        songlist << asong
      end
    end
    if songlist.size > 0
      playlist = PlayList.find_by_name('mpshell', :include=>[:songs])
      clean = reset && !reset.empty?
      songlist.each do |song|
        if clean
          playlist.add_song(song, true)
          clean = false
        else
          playlist.add_song(song)
        end
      end
    end
    redirect_to :action=>:playlist
  end

  def artist
    @artists = Song.all_artists
    render :layout=>false
  end

end
