class KaraokeController < ApplicationController
  layout 'karaoke'

  requires_authentication :using => Proc.new { |username, password|
    password == 'ponies!' },
                          :realm     => 'Happy Cloud'

  def index
    render :layout=>false
  end

  def monitor
    @page_refresh = 30
    @playlist     = PlayList.find_by_name('mpshell', :include=>[:songs=>:lyric])
  end

  def search
    alphabet = params[:alphabet] || ""
    artist   = params[:artist]   || ""
    tag      = params[:tag]      || ""
    author   = params[:author]   || ""
    @ptn     = params[:ptn] || session[:search_ptn] || ""
    @records = []
    if alphabet != ""
      @ptn = "alphabet=#{alphabet}"
    elsif artist != ""
      @ptn = "artist=#{artist}"
    elsif tag != ""
      @ptn = "tag=#{tag}"
    elsif author != ""
      @ptn = "author=#{author}"
    end
    if !@ptn.empty?
      @records = Song.ext_search(@ptn)
      session[:search_ptn] = @ptn
    end

    @playlist = PlayList.find_by_name('mpshell', :include=>[:songs=>:lyric])

    if (cid = params[:id]) != nil
      @cursong = Song.find_by_id(cid.to_i)
      if (item = params[:item]) != nil
        offset = item.to_i - @playlist.curplay
        if offset != 0
          @playlist.song_step(offset)
        end
      end
    end
  end

  def command
    cid = params[:id]
    #playlist = PlayList.find_by_name('mpshell')
    playlist = PlayList.find_by_name('mpshell', :include=>[:songs=>:lyric])
    case cid
    when 'admin'
      session[:admin] = !session[:admin]
      return redirect_to :action=>:search
    when 'item'
      item = params[:item]
      song = Song.find_by_id(item.to_i)
      if song
        index = 0
        playlist.songs.each do |asong|
          if asong.id == song.id
            break
          end
          index += 1
        end
        offset = index - playlist.curplay
        if offset != 0
          playlist.song_step(offset)
        end
      end
    when 'kill_lyrics'
      item  = params[:item]
      song = Song.find_by_id(item.to_i)
      if song
        song.lyrics = nil
        song.save
      end
    when 'next'
      playlist.song_step(1)
    when 'pause'
      Player.send "pause"
    when 'play_now'
      item  = params[:item]
      song = Song.find_by_id(item.to_i)
      if song
        playlist.add_song(song, true)
      end
    when 'previous'
      playlist.song_step(-1)
    when 'rewind'
      Player.send "seek 1 2"
    when 'toggle_state'
      index     = params[:item].to_i
      play_item = playlist.pl_songs[index]
      if play_item.state == 0
        play_item.state = 1
      else
        play_item.state = 0
      end
      p play_item
      play_item.save
    when 'voice', 'karaoke'
      csong = playlist.current_song
      csong.normalize(cid.intern)
    when 'play_now'
      item  = params[:item]
      song = Song.find_by_id(item.to_i)
      if song
        playlist.add_song(song, true)
      end
    when 'reload'
      playlist.reload_list
    end
    respond_to do |format|
      format.html #
        return redirect_to :action=>:monitor
      format.xml
        return render :xml=>playlist
    end
  end

  def queue
    cid = params[:id]
    @song = Song.find(cid.to_i)
    #@playlist = PlayList.find_by_name('mpshell')
    @playlist = PlayList.find_by_name('mpshell', :include=>[:songs=>:lyric])
    @playlist.add_song(@song)
    #render :text=>@song.to_yaml
    redirect_to :action=>:monitor
  end

  # Queuing multiple songs
  def mqueue
    #return render :text=>params.to_yaml
    @playlist  = PlayList.find_by_name('mpshell', :include=>[:songs=>:lyric])
    #@playlist = PlayList.find_by_name('mpshell')
    clean = params[:clean]
    if params[:submit] == 'Add All'
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

# Show the lyric page
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
    @sameset = Lyric.find(:all, :conditions=>['name=?', @lyric.name])
  end

# Util to load in the lyric content from remote (cache link)
  def load_lyric
    lid = params[:id]
    lyric = Lyric.find(lid.to_i)
    lyric.load_content
    redirect_to :action=>:lyrics, :lid=>lid
  end

# Set the abbrev content field from UI.  Maybe rails could do this better.
  def abcontent
    lid = params[:lid]
    abcontent = params[:abcontent] || ""
    if !abcontent.empty?
      lyric = Lyric.find(lid.to_i)
      lyric.abcontent = abcontent
      lyric.save
    end
    redirect_to :action=>:lyrics, :lid=>lid
  end

# Debug cli to run various runner/admin commands
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
