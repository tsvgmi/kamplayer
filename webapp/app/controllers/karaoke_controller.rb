class KaraokeController < ApplicationController
  layout 'karaoke'

  requires_authentication :using => Proc.new { |username, password|
    password == 'ponies!' },
                          :realm     => 'Happy Cloud'

  def index
    render :layout=>false
  end

  def index2
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
          @playlist.song_step(offset, true)
        end
      end
    end
  end

  def command
    cid = params[:id]
    #playlist = PlayList.find_by_name('mpshell')
    
    playlist   = PlayList.find_by_name('mpshell', :include=>[:songs=>:lyric])
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
    when 'create_lyric'
      item = params[:item]
      song = Song.find_by_id(item.to_i)
      if song
        result = `emrun lyscanner.rb vid4scan #{song.song}`
        p result
        ajx_return = "OK"
        YAML.load(result).each do |song, author, href|
          lyric = Lyric.update_content(:author=>author,
                                       :name=>song, :url=>href)
          ajx_return = lyric.load_content
        end
      end
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
          playlist.song_step(offset, true)
        end
      end
    when 'kill_lyrics'
      item = params[:item]
      lid  = params[:lid]
      song = Song.find_by_id(item.to_i)
      if song
        if lid
          song.lyric = Lyric.find_by_id(lid.to_i)
        end
        song.lyrics = nil
        song.save
        ajx_return = song.lyric.abcontent
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
    when 'clear'
      playlist.clear_list
    end
    if request.xhr?
      return render :text=>ajx_return
    else
      return redirect_to :action=>:monitor
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
    @playlist  = PlayList.find_by_name('mpshell', :include=>[:songs=>:lyric])
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
    if params[:shuffle]
      p "Sort list"
      songlist = songlist.sort_by {|s| rand(100)}
    end
    #return render :text=>songlist.to_yaml
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

  # Show the lyric page based on lyric id, song id, or song name
  def lyrics
    cid  = params[:id]
    lid  = params[:lid]
    name = params[:name]
    if lid
      @lyric = Lyric.find(lid.to_i)
    elsif cid
      song = Song.find(cid.to_i)
      if song.lyric
        @lyric = song.lyric
      else
        @lyric = Lyric.new(:author=>song.author, :name=>song.song)
      end
    elsif name
      if (@lyric = Lyric.find_by_name(name)) == nil
        @lyric = Lyric.new(:author=>"", :name=>name)
      end
    end
    @sameset = Lyric.find(:all, :conditions=>['name=?', @lyric.name])
  end

  # Delete the lyric specified by id
  def lyrics_del
    cid   = params[:id]
    lyric = Lyric.find_by_id(cid.to_i)
    if lyric
      name  = lyric.name
      lyric.destroy
    end
    redirect_to :action=>:lyrics, :name=>name
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
    lid       = params[:lid]
    abcontent = params[:abcontent] || ""
    if !abcontent.empty?
      lyric = Lyric.find(lid.to_i)
      lyric.abcontent = abcontent
      lyric.save
    end
    redirect_to :action=>:lyrics, :lid=>lid
  end

  def youtubeset
    lid       = params[:lid]
    newvideos = (params[:youtubes] || "").split(/\s*,\s*/).
      map{|v| v.sub(/^.*=/, '')}
    lyric     = Lyric.find(lid.to_i)
    if lyric && newvideos.size > 0
      cvideos = lyric.youtubes.map{|r| r.video}
      if cvideos != newvideos
        lyric.youtubes.each do |atube|
          atube.destroy
          atube.save
        end
        newvideos.each do |avideo|
          # Escape hack to remove all entries
          next if (avideo == '-')
          if (atube = Youtube.find_by_video(avideo)) == nil
            atube = Youtube.new(:video=>avideo)
          end
          lyric.youtubes << atube
          atube.save
        end
      else
        p "no change"
      end
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

  def testtube
    count = (params[:count] || 10).to_i
    result = Lyric.load_utube(count)
    render :text=>"<pre>" + result.to_yaml
  end
end
