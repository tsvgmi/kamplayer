class KaraokeController < ApplicationController
  layout 'karaoke'

  def index
    render :layout=>false
  end

  def monitor
    @page_refresh = 30
    @playlist     = PlayList.find_by_name('mpshell')
  end

  def search
    alphabet = params[:alphabet] || "-"
    artist   = params[:artist] || "-"
    tag      = params[:tag] || "-"
    author   = params[:author] || "-"
    @ptn     = params[:ptn] || ""
    @records = []
    if alphabet != "-"
      #@records = Song.find(:all, :conditions=>"song like '#{alphabet}%'")
      @ptn = "alphabet=#{alphabet}"
    elsif artist != "-"
      #@records = Song.find(:all, :conditions=>"artist like '%#{artist}%'")
      @ptn = "artist=#{artist}"
    elsif tag != "-"
      #@records = Song.find(:all, :conditions=>"tag like '%#{tag}%'")
      @ptn = "tag=#{tag}"
    elsif author != "-"
      #@records = []
      #conditions = "author like '%#{author}%'"
      #Lyric.find(:all, :conditions=>conditions).each do |r|
        #if r.songs.size > 0
          #@records.concat(r.songs)
        #end
      #end
      @ptn = "author=#{author}"
    end
    if !@ptn.empty?
      @records = Song.ext_search(@ptn)
    end
    if (cid = params[:id]) != nil
      @cursong = Song.find(cid.to_i)
    else
      @cursong = @records.first
    end
    @playlist = PlayList.find_by_name('mpshell')
    @artists  = Song.all_artists
    @tags     = Song.all_tags
    @authors  = Lyric.all_authors
  end

  def command
    cid = params[:id]
    playlist = PlayList.find_by_name('mpshell')
    case cid
    when 'next'
      playlist.song_step(1)
    when 'previous'
      playlist.song_step(-1)
    when 'rewind'
      Player.send "seek 1 2"
    when 'pause'
      Player.send "pause"
    when 'voice', 'karaoke'
      csong = playlist.current_song
      csong.normalize(cid.intern)
    end
    render :text=>"OK"
  end

  def rcommand
    cid = params[:id]
    playlist = PlayList.find_by_name('mpshell')
    case cid
    when 'next'
      playlist.song_step(1)
    when 'previous'
      playlist.song_step(-1)
    when 'item'
      item   = params[:item]
      offset = item.to_i - playlist.curplay
      playlist.song_step(offset)
    # Mplayer lost everything when it goes to the end, so we need to reload
    when 'reload'
      playlist.reload_list
    end
    redirect_to :action=>:monitor
  end

  def queue
    cid = params[:id]
    @song = Song.find(cid.to_i)
    @playlist = PlayList.find_by_name('mpshell')
    @playlist.add_song(@song)
    render :text=>@song.to_yaml
  end

  def mqueue
    #return render :text=>params.to_yaml
    @playlist = PlayList.find_by_name('mpshell')
    clean = params[:clean]
    if params[:all]
      ptn = params[:ptn]
      songlist = Song.ext_search(ptn)
    else
      songlist = []
      params.keys.grep(/^rec_/).each do |aparm|
        recid = aparm.sub(/^rec_/, '').to_i
        songlist << Song.find(recid)
      end
    end
    songlist.each do |song|
      if clean
        @playlist.add_song(song, true)
        clean = false
      else
        @playlist.add_song(song)
      end
    end
    redirect_to :action=>:search,:ptn=>ptn
  end

  def lyrics
    cid = params[:id]
    lid = params[:lid]
    if lid
      @lyric = Lyric.find(lid.to_i)
    else
      song = Song.find(cid.to_i)
      if song.lyric
        @lyric = song.lyric
      else
        @lyric = Lyric.new(:author=>song.author, :content=>song.lyrics)
      end
    end
  end

  def cli
    command = params[:command]

    if command =~ /^([0-9][0-9,]+)\s+/
      Song.cli_change($1, $')
    else
      cid = (params[:cid] || 0).to_i
      if cid > 0
        cursong = Song.find(cid)
      else
        cursong = PlayList.find_by_name('mpshell').current_song
      end
      Song.cli_change(".", command, cursong)
    end
    redirect_to :action=>:search
  end
end
